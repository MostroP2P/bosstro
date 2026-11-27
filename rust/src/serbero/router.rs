//! Serbero's reports to the loaded key, followed live: one kind 14
//! subscription authored by the Serbero pubkey trusted on the active node and
//! `p`-tagged to the loaded key, kept alive by `nostr::live_subs`, beside the
//! node's answers (`mostro::replies`) and the chats (`chat::router`).
//!
//! It reaches [`BACKLOG_SECS`] back, so a handoff sent while the app was
//! closed still arrives; storage keeps one row per event, so the backlog read
//! again on each start stores nothing twice. Without a trusted Serbero pubkey
//! there is no subscription, and nothing is read or kept.

use std::sync::{Arc, Mutex, OnceLock};

use nostr_sdk::prelude::{
    Client, ClientNotification, Event, Keys, Kind, PublicKey, RelayMessage, StreamExt,
    SubscriptionId, Timestamp,
};
use tokio::sync::{broadcast, mpsc};

use super::intake::{accept, reports_filter, BACKLOG_SECS};
use super::{SerberoRecord, SerberoRef};
use crate::db::Storage;
use crate::nostr::live_subs::LiveSubs;

/// How many updates a slow reader may fall behind before it reads again.
const UPDATE_CAPACITY: usize = 64;

/// A dispute whose Serbero reports changed on a node.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SerberoUpdate {
    pub mostro_pubkey: String,
    pub dispute_id: String,
}

#[derive(Clone)]
struct Target {
    node: PublicKey,
    keys: Keys,
    serbero: PublicKey,
    sub: SubscriptionId,
}

impl Target {
    fn same_as(&self, other: &Target) -> bool {
        self.node == other.node
            && self.keys.public_key() == other.keys.public_key()
            && self.serbero == other.serbero
    }
}

/// The subscription id of `node`, `serbero` and `solver` (all hex), within
/// NIP-01's 64 characters. The node is part of it so a late notification of
/// a previous node's subscription never matches the current one, even when
/// both trust the same Serbero.
fn subscription_id(node: &str, serbero: &str, solver: &str) -> SubscriptionId {
    let short = |s: &str| s.chars().take(16).collect::<String>();
    SubscriptionId::new(format!(
        "serbero-{}-{}-{}",
        short(node),
        short(serbero),
        short(solver)
    ))
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

pub(crate) struct Router {
    client: Arc<Client>,
    subs: &'static LiveSubs,
    target: Mutex<Option<Target>>,
    /// Serialises retargets, each closing the previous subscription.
    retarget_lock: tokio::sync::Mutex<()>,
}

impl Router {
    pub(crate) fn new(client: Arc<Client>, subs: &'static LiveSubs) -> Arc<Self> {
        Arc::new(Self {
            client,
            subs,
            target: Mutex::new(None),
            retarget_lock: tokio::sync::Mutex::new(()),
        })
    }

    /// Read the client's notifications for as long as it lives, passing on
    /// only the kind 14 events of the current subscription, in order; a
    /// second task opens and stores them (as `mostro::replies`).
    fn spawn_reader(self: &Arc<Self>) {
        // Each event travels with the target it was received under, so one
        // queued before a retarget is never stored under the next target.
        let (tx, mut rx) = mpsc::unbounded_channel::<(Box<Event>, Target)>();
        let mut notifications = self.client.notifications();
        let router = self.clone();
        crate::rt::spawn(async move {
            while let Some(notification) = notifications.next().await {
                let ClientNotification::Message { message, .. } = notification else {
                    continue;
                };
                let RelayMessage::Event {
                    subscription_id,
                    event,
                } = *message
                else {
                    continue;
                };
                if event.kind != Kind::PrivateDirectMessage {
                    continue;
                }
                let Some(target) = router.target_for(&subscription_id) else {
                    continue;
                };
                if tx.send((Box::new(event.into_owned()), target)).is_err() {
                    break;
                }
            }
        });
        let router = self.clone();
        crate::rt::spawn(async move {
            while let Some((event, target)) = rx.recv().await {
                let Some(db) = crate::db::app_db::db() else {
                    continue;
                };
                router.handle_for(db, &event, target).await;
            }
        });
    }

    /// The target a notification of `sub` belongs to: the current one if it
    /// is that subscription's, none otherwise.
    fn target_for(&self, sub: &SubscriptionId) -> Option<Target> {
        self.current_target().filter(|t| t.sub == *sub)
    }

    fn current_target(&self) -> Option<Target> {
        lock(&self.target).clone()
    }

    /// Follow `serbero`'s reports to `keys` on `node`, or nothing. Following
    /// what it already follows changes nothing.
    pub(crate) async fn retarget(
        &self,
        node: Option<PublicKey>,
        keys: Option<Keys>,
        serbero: Option<PublicKey>,
    ) {
        let _guard = self.retarget_lock.lock().await;
        let next = match (node, keys, serbero) {
            (Some(node), Some(keys), Some(serbero)) => Some(Target {
                sub: subscription_id(
                    &node.to_hex(),
                    &serbero.to_hex(),
                    &keys.public_key().to_hex(),
                ),
                node,
                keys,
                serbero,
            }),
            _ => None,
        };
        let previous = {
            let mut target = lock(&self.target);
            let same = match (&*target, &next) {
                (Some(a), Some(b)) => a.same_as(b),
                (None, None) => true,
                _ => false,
            };
            if same {
                return;
            }
            std::mem::replace(&mut *target, next.clone())
        };
        if let Some(previous) = previous {
            self.subs.close(&self.client, &previous.sub).await;
        }
        let Some(target) = next else {
            return;
        };
        let since =
            Timestamp::from_secs((crate::rt::unix_now().max(0) as u64).saturating_sub(BACKLOG_SECS));
        let filter = reports_filter(&target.serbero, &target.keys.public_key(), since);
        if let Err(e) = self
            .subs
            .replace(&self.client, target.sub.clone(), filter)
            .await
        {
            log::warn!("[serbero] subscribe {} failed: {e}", target.sub);
        }
    }

    /// One kind 14 of the current subscription: kept when it is a report of
    /// the trusted Serbero to the loaded key. Returns the update it made.
    #[cfg(test)]
    pub(crate) async fn handle(&self, db: &impl Storage, event: &Event) -> Option<SerberoUpdate> {
        let target = self.current_target()?;
        self.handle_for(db, event, target).await
    }

    /// [`Self::handle`] for an event received while `target` was followed:
    /// dropped when the router follows another target by now.
    async fn handle_for(
        &self,
        db: &impl Storage,
        event: &Event,
        target: Target,
    ) -> Option<SerberoUpdate> {
        let current = || lock(&self.target).as_ref().is_some_and(|t| t.same_as(&target));
        if !current() {
            return None;
        }
        let accepted = accept(&target.keys, &target.serbero, event).await?;
        let record = SerberoRecord {
            conversation: SerberoRef {
                mostro_pubkey: target.node.to_hex(),
                dispute_id: accepted.report.dispute_id.clone(),
                solver_pubkey: target.keys.public_key().to_hex(),
            },
            event_id: accepted.event_id,
            serbero_pubkey: target.serbero.to_hex(),
            content: format!(
                "Dispute {} · {}\n{}",
                accepted.report.dispute_id, accepted.report.subject, accepted.report.body
            ),
            created_at: accepted.created_at,
            received_at: crate::rt::unix_now(),
        };
        // A retarget while it was opened: the report is not this target's.
        if !current() {
            return None;
        }
        match db.insert_serbero_message(&record).await {
            Ok(true) => {}
            Ok(false) => return None,
            Err(e) => {
                log::warn!("[serbero] a report was not stored: {e}");
                return None;
            }
        }
        let update = SerberoUpdate {
            mostro_pubkey: record.conversation.mostro_pubkey,
            dispute_id: record.conversation.dispute_id,
        };
        let _ = updates().send(update.clone());
        Some(update)
    }
}

static ROUTER: OnceLock<Arc<Router>> = OnceLock::new();

fn updates() -> &'static broadcast::Sender<SerberoUpdate> {
    static UPDATES: OnceLock<broadcast::Sender<SerberoUpdate>> = OnceLock::new();
    UPDATES.get_or_init(|| broadcast::channel(UPDATE_CAPACITY).0)
}

/// Every report stored from now on, as the dispute it changed.
pub(crate) fn subscribe_updates() -> broadcast::Receiver<SerberoUpdate> {
    updates().subscribe()
}

/// Start the router on the relay pool's client. Called once the pool
/// exists; later calls only re-point it.
pub(crate) async fn start(client: Arc<Client>) {
    let router = ROUTER.get_or_init(|| {
        let router = Router::new(client, crate::nostr::live_subs::live_subs());
        router.spawn_reader();
        router
    });
    follow_with(router).await;
}

/// Re-point the router at the active node, the loaded key and the Serbero
/// pubkey trusted on that node, after any of them changes. A no-op before
/// the pool started.
pub(crate) async fn follow() {
    if let Some(router) = ROUTER.get() {
        follow_with(router).await;
    }
}

async fn follow_with(router: &Router) {
    // One follow at a time, from reading the state to installing it: an
    // older call that read the previous node must not install it after a
    // newer one. `handle` never takes this lock.
    static FOLLOWING: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
    let _following = FOLLOWING.lock().await;
    let keys = crate::solver_slot::SOLVER_SLOT.keys().await;
    let node = crate::config::active_mostro_pubkey();
    let serbero = match (&node, crate::db::app_db::db()) {
        (Some(node), Some(db)) => crate::api::serbero::trusted_serbero(db, node)
            .await
            .ok()
            .flatten(),
        _ => None,
    };
    let parse = |hex: Option<String>| hex.and_then(|h| PublicKey::from_hex(&h).ok());
    router.retarget(parse(node), keys, parse(serbero)).await;
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::serbero::intake::tests::{serbero_dm, transcript_text, DISPUTE};

    async fn router_for(node: &Keys, solver: &Keys, serbero: &Keys) -> Arc<Router> {
        let router = Router::new(Arc::new(Client::new()), crate::nostr::live_subs::live_subs());
        router
            .retarget(
                Some(node.public_key()),
                Some(solver.clone()),
                Some(serbero.public_key()),
            )
            .await;
        router
    }

    #[tokio::test]
    async fn a_report_is_stored_once_for_the_node_and_key() {
        let db = crate::db::sqlite::tests::store().await;
        let (node, solver, serbero) = (Keys::generate(), Keys::generate(), Keys::generate());
        let router = router_for(&node, &solver, &serbero).await;
        let event = serbero_dm(&serbero, &solver.public_key(), &transcript_text());

        let update = router.handle(&db, &event).await;
        assert_eq!(
            update,
            Some(SerberoUpdate {
                mostro_pubkey: node.public_key().to_hex(),
                dispute_id: DISPUTE.into(),
            })
        );
        assert_eq!(router.handle(&db, &event).await, None, "a copy");

        let rows = db
            .list_serbero_messages(&SerberoRef {
                mostro_pubkey: node.public_key().to_hex(),
                dispute_id: DISPUTE.into(),
                solver_pubkey: solver.public_key().to_hex(),
            })
            .await
            .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].event_id, event.id.to_hex());
        assert_eq!(rows[0].serbero_pubkey, serbero.public_key().to_hex());
        assert_eq!(rows[0].content, transcript_text());
    }

    #[tokio::test]
    async fn without_a_trusted_serbero_nothing_is_kept() {
        let db = crate::db::sqlite::tests::store().await;
        let (node, solver, serbero) = (Keys::generate(), Keys::generate(), Keys::generate());
        let router = Router::new(Arc::new(Client::new()), crate::nostr::live_subs::live_subs());
        router
            .retarget(Some(node.public_key()), Some(solver.clone()), None)
            .await;
        let event = serbero_dm(&serbero, &solver.public_key(), &transcript_text());
        assert_eq!(router.handle(&db, &event).await, None);
    }

    #[tokio::test]
    async fn a_report_from_an_untrusted_key_is_not_kept() {
        let db = crate::db::sqlite::tests::store().await;
        let (node, solver, serbero, other) = (
            Keys::generate(),
            Keys::generate(),
            Keys::generate(),
            Keys::generate(),
        );
        let router = router_for(&node, &solver, &serbero).await;
        let event = serbero_dm(&other, &solver.public_key(), &transcript_text());
        assert_eq!(router.handle(&db, &event).await, None);
    }

    /// Found by review: a report queued under one target must not be stored
    /// under the next one (two nodes can share a Serbero and a solver key,
    /// so the subscription id alone does not tell them apart).
    #[tokio::test]
    async fn a_report_received_for_a_previous_target_is_not_kept() {
        let db = crate::db::sqlite::tests::store().await;
        let (node_a, node_b, solver, serbero) = (
            Keys::generate(),
            Keys::generate(),
            Keys::generate(),
            Keys::generate(),
        );
        let router = router_for(&node_a, &solver, &serbero).await;
        let received_under = router.current_target().unwrap();
        router
            .retarget(
                Some(node_b.public_key()),
                Some(solver.clone()),
                Some(serbero.public_key()),
            )
            .await;
        let event = serbero_dm(&serbero, &solver.public_key(), &transcript_text());

        assert_eq!(router.handle_for(&db, &event, received_under).await, None);
        for node in [&node_a, &node_b] {
            let rows = db
                .list_serbero_messages(&SerberoRef {
                    mostro_pubkey: node.public_key().to_hex(),
                    dispute_id: DISPUTE.into(),
                    solver_pubkey: solver.public_key().to_hex(),
                })
                .await
                .unwrap();
            assert!(rows.is_empty());
        }
    }

    /// Found by review: a late notification of a previous node's
    /// subscription must not match the current one.
    #[test]
    fn each_node_has_its_own_subscription() {
        let (a, b, solver, serbero) = (
            Keys::generate().public_key().to_hex(),
            Keys::generate().public_key().to_hex(),
            Keys::generate().public_key().to_hex(),
            Keys::generate().public_key().to_hex(),
        );
        let id = |node: &str| subscription_id(node, &serbero, &solver);
        assert_ne!(id(&a), id(&b));
        assert_eq!(id(&a), id(&a), "back on a node, its own subscription again");
        assert!(id(&a).to_string().len() <= 64, "NIP-01");
    }

    /// Found by review: notifications read late, after the node changed,
    /// through the reader's own matching (A → B, then back to A).
    #[tokio::test]
    async fn a_late_notification_is_kept_only_under_the_node_it_was_for() {
        let db = crate::db::sqlite::tests::store().await;
        let (node_a, node_b, solver, serbero) = (
            Keys::generate(),
            Keys::generate(),
            Keys::generate(),
            Keys::generate(),
        );
        let router = router_for(&node_a, &solver, &serbero).await;
        let sub_a = router.current_target().unwrap().sub;
        let retarget = |node: &Keys| {
            let node = node.public_key();
            let (router, solver, serbero) = (router.clone(), solver.clone(), serbero.public_key());
            async move { router.retarget(Some(node), Some(solver), Some(serbero)).await }
        };
        let rows = |node: &Keys| {
            let reports = SerberoRef {
                mostro_pubkey: node.public_key().to_hex(),
                dispute_id: DISPUTE.into(),
                solver_pubkey: solver.public_key().to_hex(),
            };
            let db = &db;
            async move { db.list_serbero_messages(&reports).await.unwrap().len() }
        };
        let event = serbero_dm(&serbero, &solver.public_key(), &transcript_text());

        // A → B: A's notification, read now, matches no target.
        retarget(&node_b).await;
        assert!(router.target_for(&sub_a).is_none());
        assert_eq!((rows(&node_a).await, rows(&node_b).await), (0, 0));

        // B → A: the same late notification is A's again, and kept under A.
        retarget(&node_a).await;
        let target = router.target_for(&sub_a).expect("A's own subscription");
        assert!(router.handle_for(&db, &event, target).await.is_some());
        assert_eq!((rows(&node_a).await, rows(&node_b).await), (1, 0));
    }
}
