//! Push notifications to the solver, across the bridge: the watch of the
//! active node's new disputes on the push server (`crate::push::watch`).
//!
//! Dart owns the device side (the FCM token, the permission, the toggle's
//! screen) and tells Rust what changed; Rust owns the rule, the storage and
//! the requests. Dart asks for a [`reconcile_push`] at startup, when the app
//! returns to the foreground, and after the node, the key, the token or the
//! toggle changed. A change of the key goes through `unload_solver_key`,
//! which does not reconcile by itself: replacing a key unloads the old one
//! first, and the watch is per node, not per key, so only Dart knows when
//! the operation has settled.
//!
//! Nothing here returns text: [`PushWatchStatus`] is a marker Dart maps to
//! its own copy. The token is never logged.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::OnceLock;

use anyhow::Result;

use crate::push::watch::{Inputs, Outcome, Status, Watcher};
use crate::rt::time::Duration;
use crate::solver_slot::SOLVER_SLOT;

/// Where the watch of the active node's new disputes stands.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PushWatchStatus {
    /// The solver has notifications off.
    Off,
    /// On, and something is missing: the device's token, a node or a key.
    Waiting,
    /// The push server rings this device for the active node's disputes.
    Registered,
    /// The push server refused the device's token. Nothing more is asked
    /// until the token or the node changes.
    TokenRefused,
    /// The active node is not one the push server rings for. Nothing more
    /// is asked until the node changes.
    NodeNotTrusted,
    /// The push server asked to wait; it is asked again by itself.
    RateLimited,
    /// The push server failed or could not be reached; it is asked again
    /// by itself.
    ServerUnavailable,
}

impl From<Status> for PushWatchStatus {
    fn from(status: Status) -> Self {
        match status {
            Status::Off => Self::Off,
            Status::Waiting => Self::Waiting,
            Status::Registered => Self::Registered,
            Status::TokenRefused => Self::TokenRefused,
            Status::NodeNotTrusted => Self::NodeNotTrusted,
            Status::RateLimited => Self::RateLimited,
            Status::ServerUnavailable => Self::ServerUnavailable,
        }
    }
}

fn watcher() -> &'static Watcher {
    static WATCHER: OnceLock<Watcher> = OnceLock::new();
    WATCHER.get_or_init(Watcher::production)
}

/// Whether the solver turned notifications on. Off until they do.
///
/// **Errors**: `StorageUnavailable`, when what is stored could not be read
/// this time. It is not "off": ask again.
pub async fn push_enabled() -> Result<bool> {
    watcher().enabled(crate::db::app_db::db()).await
}

/// Whether what was stored about notifications was found unreadable and
/// started over, said once. The switch then reads off while Google still
/// holds the device's token: Dart deletes it.
pub async fn take_push_state_lost() -> bool {
    watcher().take_lost(crate::db::app_db::db()).await
}

/// Whether to offer the solver notifications now. Yes at most once in the
/// life of the install, and never when they are already on: asking marks the
/// offer as made.
pub async fn take_push_offer() -> bool {
    watcher().take_offer(crate::db::app_db::db()).await
}

/// Turn the notifications of new disputes on or off, and bring the push
/// server in step: turning them off drops the watch. Dart deletes the
/// device's token itself and says so with [`set_push_token`].
///
/// **Errors**: `StorageUnavailable`, with nothing changed.
pub async fn set_push_enabled(enabled: bool) -> Result<PushWatchStatus> {
    watcher()
        .set_enabled(crate::db::app_db::db(), enabled)
        .await?;
    reconcile_push().await
}

/// Keep the device's FCM token (a new one, or the same one again), or
/// forget it with `None` once Dart deleted it, and bring the push server in
/// step.
///
/// **Errors**: `InvalidToken`, for what cannot be an FCM token;
/// `StorageUnavailable`, with nothing changed.
pub async fn set_push_token(token: Option<String>) -> Result<PushWatchStatus> {
    watcher()
        .set_token(crate::db::app_db::db(), token)
        .await?;
    reconcile_push().await
}

/// Make the push server agree with what should be watched: the active node,
/// when notifications are on, the device has a token and a key is loaded.
/// Cheap when nothing changed: a watch is asked for again only once a day.
///
/// A run that has to be tried again (the server down, a rate limit, an
/// unwatch that failed) is, by itself, while the process lives.
///
/// Call it once a key change has settled, never in the middle of one: this
/// run takes "no key" for a logout and drops the watch.
///
/// **Errors**: `StorageUnavailable`, when what is stored could not be read:
/// nothing was asked of the server. It is tried again by itself.
pub async fn reconcile_push() -> Result<PushWatchStatus> {
    let outcome = run(true).await;
    retry_later(match &outcome {
        Ok(outcome) => outcome.retry_in,
        Err(_) => Some(crate::push::watch::STORAGE_RETRY_SECS),
    });
    Ok(outcome?.status.into())
}

/// One run. `key_settled` says whether "no key" is a logout
/// (`crate::push::watch::Inputs::key_settled`): yes when Dart asks, no
/// from the retry task.
async fn run(key_settled: bool) -> Result<Outcome> {
    // Read by the run once it has its turn, not here: this may wait behind
    // another run, and the node or the key may change meanwhile.
    let inputs = || async move {
        Inputs {
            node: crate::config::active_mostro_pubkey(),
            has_key: SOLVER_SLOT.keys().await.is_some(),
            key_settled,
        }
    };
    watcher()
        .reconcile_with(crate::db::app_db::db(), inputs, crate::rt::unix_now())
        .await
}

/// Run again in `retry_in` seconds, and after that for as long as a run
/// asks for another. Only the retry asked for last runs: every call here,
/// with or without a wait, retires the one before.
fn retry_later(retry_in: Option<i64>) {
    static LATEST: AtomicU64 = AtomicU64::new(0);
    let mine = LATEST.fetch_add(1, Ordering::SeqCst) + 1;
    let Some(mut wait) = retry_in else { return };
    crate::rt::spawn(async move {
        loop {
            crate::rt::time::sleep(Duration::from_secs(wait.max(1) as u64)).await;
            if LATEST.load(Ordering::SeqCst) != mine {
                return;
            }
            match run(false).await {
                Ok(Outcome {
                    retry_in: Some(next),
                    ..
                }) => wait = next,
                Ok(_) => return,
                Err(_) => wait = crate::push::watch::STORAGE_RETRY_SECS,
            }
        }
    });
}
