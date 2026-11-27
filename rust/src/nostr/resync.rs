//! Bringing the core back in step with the relays when the app returns to
//! the foreground. From MostroP2P/app's `api/nostr.rs` (`resync`), without
//! what Bosstro does not have: no outbox, and no subscription to re-arm by
//! hand, since every long-lived one is recorded in [`super::live_subs`].
//!
//! Android freezes a background process whole, and its sockets die with it.
//! The SDK reconnects on its own schedule (ten seconds, growing to a minute),
//! and until then the screens show what they held when the app was left. One
//! pass, in order:
//!
//! 1. **Reconnect.** Every relay found disconnected is bounced, so it
//!    connects now ([`super::relay_probe::reconnect_disconnected_now`]), and
//!    every relay still marked connected is asked whether it answers, and
//!    bounced when it does not
//!    ([`super::relay_probe::reconnect_unresponsive_now`]): the network can
//!    drop a socket without the SDK hearing of it. Then `connect()` starts
//!    the relays that have no connection task at all, and the pass waits a
//!    bounded time for the first relay to be connected.
//! 2. **Subscriptions.** Whatever a relay that is up still lacks is issued
//!    again ([`super::live_subs::LiveSubs::repair_all`]). The relays still
//!    connecting get theirs from the repair task as they connect.
//!
//! Nothing is asked again by hand: a relay that reconnects is sent every REQ
//! again by the SDK and answers with what it stores, which is how a dispute
//! opened meanwhile reaches the feed.

use std::future::Future;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use nostr_sdk::prelude::{Client, RelayStatus};

use super::live_subs::LiveSubs;

/// How long a pass waits for a relay to connect before it reports what it
/// found. Long enough for a handshake on a radio that just woke; short
/// enough that a resume with no network does not hold whoever waits for it.
const CONNECT_WAIT: Duration = Duration::from_secs(5);

/// How often the wait looks at the relays.
const CONNECT_POLL: Duration = Duration::from_millis(50);

/// One pass over `client`. Returns whether a relay is connected at its end.
pub(crate) async fn pass(client: &Client, subs: &LiveSubs) -> bool {
    let (dropped, silent) = futures_util::future::join(
        super::relay_probe::reconnect_disconnected_now(client),
        super::relay_probe::reconnect_unresponsive_now(client),
    )
    .await;
    if dropped + silent > 0 {
        log::info!("[relay] resync: reconnecting now {dropped} dropped, {silent} silent relay(s)");
    }
    client.connect().await;
    wait_for_a_relay(client).await;

    let repaired = subs.repair_all(client).await;
    if repaired > 0 {
        log::info!("[relay] resync: repaired {repaired} subscription(s)");
    }

    let online = any_connected(client).await;
    log::info!("[relay] resync: done, online={online}");
    online
}

async fn any_connected(client: &Client) -> bool {
    client
        .relays()
        .await
        .values()
        .any(|relay| relay.status() == RelayStatus::Connected)
}

/// Wait until one relay is connected, at most [`CONNECT_WAIT`]. The first
/// one, not all of them (`Connect::and_wait`): one unreachable relay would
/// hold every pass for the whole wait. The relays that connect later get
/// their subscriptions from the repair task.
async fn wait_for_a_relay(client: &Client) {
    let mut waited = Duration::ZERO;
    while waited < CONNECT_WAIT && !any_connected(client).await {
        crate::rt::time::sleep(CONNECT_POLL).await;
        waited += CONNECT_POLL;
    }
}

/// One pass at a time, and none for a call that a pass started after it
/// already serves.
pub(crate) struct SingleFlight<T> {
    lock: tokio::sync::Mutex<()>,
    /// Passes started so far. Written under `lock`.
    started: AtomicU64,
    last: std::sync::Mutex<Option<T>>,
}

impl<T: Clone> SingleFlight<T> {
    pub(crate) const fn new() -> Self {
        Self {
            lock: tokio::sync::Mutex::const_new(()),
            started: AtomicU64::new(0),
            last: std::sync::Mutex::new(None),
        }
    }

    /// Runs `pass`, or returns the result of one that started after this
    /// call was made. The flag says which: `true` when this call ran no pass
    /// of its own.
    ///
    /// Only a pass that **started** after the call may stand for it: it saw
    /// the relays as they were after the call. A pass already running when
    /// the call arrives may have looked at them before whatever the call is
    /// about (the app left again and came back while it waited), so the call
    /// waits for it to end and then runs its own. Calls that waited together
    /// share that one.
    pub(crate) async fn run<F, Fut>(&self, pass: F) -> (T, bool)
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = T>,
    {
        let seen = self.started.load(Ordering::Acquire);
        let _guard = self.lock.lock().await;
        if self.started.load(Ordering::Acquire) != seen {
            if let Some(last) = self.last.lock().ok().and_then(|last| last.clone()) {
                return (last, true);
            }
        }
        self.started.fetch_add(1, Ordering::Release);
        let outcome = pass().await;
        if let Ok(mut last) = self.last.lock() {
            *last = Some(outcome.clone());
        }
        (outcome, false)
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use nostr_sdk::prelude::{Filter, Keys, Kind, MockRelay, SubscriptionId};
    use std::sync::atomic::AtomicU32;
    use std::sync::Arc;

    /// Two calls in sequence are two passes: the second is not "the same
    /// resume".
    #[tokio::test]
    async fn sequential_calls_each_run_a_pass() {
        let flight = SingleFlight::new();
        let runs = Arc::new(AtomicU32::new(0));
        for expected in 1..=2 {
            let counter = runs.clone();
            let (_, coalesced) = flight
                .run(|| async move {
                    counter.fetch_add(1, Ordering::SeqCst);
                })
                .await;
            assert!(!coalesced);
            assert_eq!(runs.load(Ordering::SeqCst), expected);
        }
    }

    /// A call that arrives while a pass runs is not served by it: that pass
    /// looked at the relays before the call. The calls that waited run one
    /// more pass between them.
    #[tokio::test]
    async fn calls_made_during_a_pass_share_one_pass_that_starts_after_them() {
        let flight = Arc::new(SingleFlight::new());
        let runs = Arc::new(AtomicU32::new(0));
        let (release_tx, release_rx) = tokio::sync::oneshot::channel::<()>();
        let (started_tx, started_rx) = tokio::sync::oneshot::channel::<()>();

        let first = {
            let (flight, runs) = (flight.clone(), runs.clone());
            tokio::spawn(async move {
                flight
                    .run(|| async move {
                        runs.fetch_add(1, Ordering::SeqCst);
                        let _ = started_tx.send(());
                        let _ = release_rx.await;
                        3
                    })
                    .await
            })
        };
        started_rx.await.unwrap();

        let followers: Vec<_> = (0..3)
            .map(|_| {
                let (flight, runs) = (flight.clone(), runs.clone());
                tokio::spawn(async move {
                    flight
                        .run(|| async move {
                            runs.fetch_add(1, Ordering::SeqCst);
                            99
                        })
                        .await
                })
            })
            .collect();
        // Let the followers reach the lock before the first pass ends.
        tokio::task::yield_now().await;
        release_tx.send(()).unwrap();

        assert_eq!(first.await.unwrap(), (3, false));
        let mut own = 0;
        for follower in followers {
            let (outcome, coalesced) = follower.await.unwrap();
            assert_eq!(outcome, 99, "never the pass that was already running");
            if !coalesced {
                own += 1;
            }
        }
        assert_eq!(own, 1, "one of the three ran the pass the others share");
        assert_eq!(runs.load(Ordering::SeqCst), 2, "two passes for four calls");
    }

    /// One unreachable relay does not hold the pass for the whole wait.
    #[tokio::test]
    async fn a_pass_does_not_wait_for_a_relay_that_cannot_be_reached() {
        // Arrange: a healthy relay, and a port nothing listens on.
        let relay = MockRelay::run().await.unwrap();
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.unwrap();
        client.add_relay("ws://127.0.0.1:1").await.unwrap();
        let started = tokio::time::Instant::now();

        // Act
        let online = pass(&client, &LiveSubs::default()).await;

        // Assert
        assert!(online);
        assert!(started.elapsed() < CONNECT_WAIT - Duration::from_secs(1));
    }

    /// A relay the OS cut is back when the pass ends, not when its retry
    /// interval (ten seconds) runs out.
    #[tokio::test]
    async fn a_pass_reconnects_a_dropped_relay() {
        // Arrange
        let url = crate::nostr::relay_probe::tests::relay_that_drops_the_first_connection().await;
        let client = crate::nostr::relay_probe::tests::dropped_relay(&url).await;
        let started = tokio::time::Instant::now();

        // Act
        let online = pass(&client, &LiveSubs::default()).await;

        // Assert
        assert!(online);
        assert!(started.elapsed() < Duration::from_secs(8));
    }

    /// A subscription asked for while its relay was down exists nowhere
    /// (`live_subs`); the pass connects the relay and issues it.
    #[tokio::test]
    async fn a_pass_issues_the_subscription_a_relay_lacks() {
        // Arrange: a relay known to the client and never connected.
        let relay = MockRelay::run().await.unwrap();
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.unwrap();
        let subs = LiveSubs::default();
        let id = SubscriptionId::new("resync-test");
        let filter = Filter::new()
            .kind(Kind::PrivateDirectMessage)
            .pubkey(Keys::generate().public_key());
        subs.replace(&client, id.clone(), filter).await.unwrap();
        let sdk_relay = client.relay(&url).await.unwrap().unwrap();
        assert!(!sdk_relay.subscriptions().await.contains_key(&id));

        // Act
        let online = pass(&client, &subs).await;

        // Assert
        assert!(online);
        assert!(sdk_relay.subscriptions().await.contains_key(&id));
    }

    #[tokio::test]
    async fn a_pass_over_a_healthy_pool_changes_nothing() {
        // Arrange
        let relay = MockRelay::run().await.unwrap();
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.unwrap();
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .unwrap();

        // Act
        let online = pass(&client, &LiveSubs::default()).await;

        // Assert
        assert!(online);
        let relay = client.relay(&url).await.unwrap().unwrap();
        assert_eq!(relay.status(), RelayStatus::Connected);
        assert!(relay.subscriptions().await.is_empty());
    }

    #[tokio::test]
    async fn a_pass_with_no_relay_reachable_reports_offline() {
        // Arrange: a port nothing listens on.
        let client = Client::new();
        client.add_relay("ws://127.0.0.1:1").await.unwrap();
        client.connect().await;

        // Act
        let online = tokio::time::timeout(
            CONNECT_WAIT + Duration::from_secs(5),
            pass(&client, &LiveSubs::default()),
        )
        .await
        .expect("the pass is bounded");

        // Assert
        assert!(!online);
    }
}
