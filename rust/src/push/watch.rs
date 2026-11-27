//! The watch of the active node's new disputes, on
//! [mostro-push-server](https://github.com/MostroP2P/mostro-push-server)
//! (`POST /api/disputes/watch`, `POST /api/disputes/unwatch`).
//!
//! The server rings every device watching a node when that node opens a
//! dispute. A watch names the device's FCM token and the node's (public)
//! pubkey, and nothing else: no solver key, no signature. The server still
//! sees the device's IP address next to that node.
//!
//! **The rule:** the active node is watched when the solver turned
//! notifications on, the device has a token, and a key is loaded. Anything
//! else is no watch.
//!
//! [`Watcher::reconcile`] makes the server agree with the rule, one run at a
//! time:
//!
//! 1. A stored watch that is not the wanted one (another node, another
//!    token, notifications off, logged out) joins the unwatches still to do.
//! 2. Those are tried. One that fails stays for the next run and **does not
//!    hold back the new watch**: a solver who switched node must be rung by
//!    the new one even if the old one could not be told.
//! 3. The wanted watch is asked for when it is missing or older than a day.
//!    The server keeps a watch 30 days from the last time it was asked for.
//!
//! What is stored (the settings store, which is not encrypted, A4): the
//! switch, the token, the watch the server holds and the unwatches to do.
//! The token alone lets nobody send a push. What makes a run wait (a
//! refusal, a rate limit, a failure) is kept in memory only: after a
//! restart the first run asks again.
//!
//! **The token is never logged**, and no type that holds it prints it.

use serde::{Deserialize, Serialize};

use super::http_client;
use crate::db::{settings_keys, Storage};
use crate::rt::time::Duration;

/// A watch older than this is asked for again, far inside the 30 days the
/// server keeps it.
const RENEW_AFTER_SECS: i64 = 86_400;

/// An unwatch that could not be done for this long is dropped: the server
/// has let the watch lapse by then.
const FORGET_UNWATCH_AFTER_SECS: i64 = 30 * 86_400;

/// More unwatches to do than this and the oldest are dropped. Each is a
/// request per run.
const MAX_PENDING_UNWATCHES: usize = 8;

const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);

/// The waits after a failure that may pass (the server down, no
/// connection), one per failure in a row; the last one repeats.
const RETRY_WAITS_SECS: [i64; 4] = [30, 120, 600, 3_600];

/// The wait after a `429` that names none, and the longest one taken from a
/// `Retry-After`. The server allows one new watch per IP every 12 minutes.
const RATE_LIMIT_WAIT_SECS: i64 = 720;
const MAX_RETRY_AFTER_SECS: i64 = 3_600;

/// How long until unwatches that failed are tried again, when nothing else
/// asks for a run sooner.
const UNWATCH_RETRY_SECS: i64 = 600;

/// No FCM token is near this long.
const MAX_TOKEN_LEN: usize = 4_096;

/// What the server is asked to ring: a device, for a node.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
struct Target {
    /// The node's pubkey (hex).
    node: String,
    /// The device's FCM token.
    token: String,
}

impl std::fmt::Debug for Target {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Target")
            .field("node", &self.node)
            .field("token", &"<not shown>")
            .finish()
    }
}

/// A watch the server took.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct Watch {
    #[serde(flatten)]
    target: Target,
    /// When it was last asked for (Unix seconds).
    registered_at: i64,
}

/// A watch the server still holds and must drop.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct PendingUnwatch {
    #[serde(flatten)]
    target: Target,
    /// Since when (Unix seconds).
    since: i64,
}

/// What is kept across restarts.
#[derive(Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
struct Stored {
    /// The solver turned notifications on.
    #[serde(default)]
    enabled: bool,
    /// The device's FCM token, once Dart got one.
    #[serde(default)]
    token: Option<String>,
    /// The watch the server holds, as far as this app knows.
    #[serde(default)]
    watch: Option<Watch>,
    #[serde(default)]
    unwatch: Vec<PendingUnwatch>,
    /// The solver was asked once whether they want notifications.
    #[serde(default)]
    offered: bool,
}

/// Where the watch stands. Markers: Dart maps them to its own copy.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Status {
    /// The solver has notifications off.
    Off,
    /// On, and something is missing: a token, a node or a key.
    Waiting,
    /// The server holds the watch of the active node.
    Registered,
    /// The server refused the token (`400`). Nothing more is asked until
    /// the token or the node changes.
    TokenRefused,
    /// The node is not on the server's trusted list (`403`). Nothing more
    /// is asked until the node or the token changes.
    NodeNotTrusted,
    /// The server asked to wait (`429`).
    RateLimited,
    /// The server failed or could not be reached; tried again later.
    ServerUnavailable,
}

/// What the rule depends on besides what is stored.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Inputs {
    /// The active node's pubkey (hex).
    pub(crate) node: Option<String>,
    /// Whether a solver key is loaded.
    pub(crate) has_key: bool,
}

/// What one run found.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Outcome {
    pub(crate) status: Status,
    /// When another run is worth it (seconds from now), if nothing else
    /// asks for one sooner.
    pub(crate) retry_in: Option<i64>,
}

/// Why the watch of a target is not asked for right now.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Hold {
    target: Target,
    status: Status,
    /// Until when (Unix seconds); `None` is until the target changes.
    until: Option<i64>,
}

#[derive(Default)]
struct Inner {
    /// Read from storage at the first use.
    stored: Option<Stored>,
    hold: Option<Hold>,
    /// Failures that may pass, in a row.
    failures: usize,
}

/// Keeps one push server's watch in step with the rule.
pub(crate) struct Watcher {
    /// The server's base URL; `None` asks nobody.
    server: Option<String>,
    /// The lock is also what makes it one run at a time.
    inner: tokio::sync::Mutex<Inner>,
}

impl Watcher {
    /// The one the app uses: the real server, unless a debug build was
    /// pointed elsewhere ([`super::TEST_SERVER_ENV`]).
    pub(crate) fn production() -> Self {
        match super::test_server() {
            Some(server) => Self::new(server),
            None => Self::to(super::SERVER_URL),
        }
    }

    /// One that asks the server at `server` (a base URL).
    pub(crate) fn to(server: &str) -> Self {
        Self::new(Some(server.trim_end_matches('/').to_string()))
    }

    fn new(server: Option<String>) -> Self {
        Self {
            server,
            inner: tokio::sync::Mutex::new(Inner::default()),
        }
    }

    /// Whether the solver has notifications on.
    pub(crate) async fn enabled(&self, db: Option<&impl Storage>) -> bool {
        let mut inner = self.inner.lock().await;
        stored(&mut inner, db).await.enabled
    }

    /// Whether to offer notifications to the solver now, which is said yes
    /// to once: they are off and were never offered. The offer is marked as
    /// made here, before it shows, so it cannot show twice.
    pub(crate) async fn take_offer(&self, db: Option<&impl Storage>) -> bool {
        let mut inner = self.inner.lock().await;
        let stored = stored(&mut inner, db).await;
        if stored.offered {
            return false;
        }
        stored.offered = true;
        save(db, stored).await;
        !stored.enabled
    }

    /// Turn notifications on or off. The server learns of it at the next
    /// [`Self::reconcile`].
    pub(crate) async fn set_enabled(&self, db: Option<&impl Storage>, enabled: bool) {
        let mut inner = self.inner.lock().await;
        let stored = stored(&mut inner, db).await;
        if stored.enabled != enabled {
            stored.enabled = enabled;
            save(db, stored).await;
        }
    }

    /// Keep the device's token, or forget it with `None` (Dart deleted it).
    /// The server learns of it at the next [`Self::reconcile`].
    ///
    /// **Errors**: `InvalidToken`, for what cannot be an FCM token.
    pub(crate) async fn set_token(
        &self,
        db: Option<&impl Storage>,
        token: Option<String>,
    ) -> anyhow::Result<()> {
        if token.as_deref().is_some_and(|token| !is_token(token)) {
            anyhow::bail!("InvalidToken");
        }
        let mut inner = self.inner.lock().await;
        let stored = stored(&mut inner, db).await;
        if stored.token != token {
            stored.token = token;
            save(db, stored).await;
        }
        Ok(())
    }

    /// Make the server agree with the rule (see the module). `now` is Unix
    /// seconds.
    pub(crate) async fn reconcile(
        &self,
        db: Option<&impl Storage>,
        inputs: &Inputs,
        now: i64,
    ) -> Outcome {
        let mut inner = self.inner.lock().await;
        stored(&mut inner, db).await;
        let Inner {
            stored: Some(stored),
            hold,
            failures,
        } = &mut *inner
        else {
            unreachable!("stored() fills it");
        };
        let before = stored.clone();

        let wanted = match (&stored.token, &inputs.node) {
            (Some(token), Some(node)) if stored.enabled && inputs.has_key => Some(Target {
                node: node.clone(),
                token: token.clone(),
            }),
            _ => None,
        };
        // What made the old target wait says nothing of this one.
        if hold.as_ref().map(|hold| &hold.target) != wanted.as_ref() {
            *hold = None;
            *failures = 0;
        }

        // 1. A watch that is not the wanted one is to be dropped.
        if let Some(watch) = &stored.watch {
            if Some(&watch.target) != wanted.as_ref() {
                stored.unwatch.push(PendingUnwatch {
                    target: watch.target.clone(),
                    since: now,
                });
                stored.watch = None;
            }
        }
        // Wanted again (the solver switched back): not to be dropped.
        stored
            .unwatch
            .retain(|pending| Some(&pending.target) != wanted.as_ref());
        stored
            .unwatch
            .retain(|pending| now - pending.since < FORGET_UNWATCH_AFTER_SECS);
        if stored.unwatch.len() > MAX_PENDING_UNWATCHES {
            let excess = stored.unwatch.len() - MAX_PENDING_UNWATCHES;
            stored.unwatch.drain(..excess);
        }

        let Some(server) = &self.server else {
            if *stored != before {
                save(db, stored).await;
            }
            return Outcome {
                status: match wanted {
                    Some(_) => Status::ServerUnavailable,
                    None => idle(stored.enabled),
                },
                retry_in: None,
            };
        };

        // 2. The unwatches. The first that cannot reach the server ends the
        // round: the others would wait out the same timeout.
        let mut left = Vec::new();
        let mut pending = std::mem::take(&mut stored.unwatch).into_iter();
        for unwatch in pending.by_ref() {
            match post(server, "unwatch", &unwatch.target).await {
                // Done, or refused for good: nothing to try again.
                Ok(reply) if reply.status == 200 || is_refusal(reply.status) => {}
                Ok(reply) => {
                    log::info!("[push] unwatch not done: server returned {}", reply.status);
                    left.push(unwatch);
                }
                Err(e) => {
                    log::info!("[push] unwatch not done: {e}");
                    left.push(unwatch);
                    break;
                }
            }
        }
        left.extend(pending);
        stored.unwatch = left;

        // 3. The wanted watch.
        let status = match &wanted {
            None => idle(stored.enabled),
            Some(target) => {
                let held = hold
                    .as_ref()
                    .filter(|hold| hold.until.is_none_or(|until| holds(until, now)))
                    .map(|hold| hold.status);
                let fresh = stored.watch.as_ref().is_some_and(|watch| {
                    now >= watch.registered_at && now - watch.registered_at < RENEW_AFTER_SECS
                });
                match held {
                    // A renewal that has to wait: the server still holds
                    // the watch.
                    Some(_) if stored.watch.is_some() => Status::Registered,
                    Some(status) => status,
                    None if fresh => Status::Registered,
                    None => {
                        let asked = ask(server, target, *failures).await;
                        match asked {
                            Asked::Taken => {
                                stored.watch = Some(Watch {
                                    target: target.clone(),
                                    registered_at: now,
                                });
                                *hold = None;
                                *failures = 0;
                                Status::Registered
                            }
                            Asked::Refused(status) => {
                                // The server does not hold it, whatever
                                // this app thought.
                                stored.watch = None;
                                *hold = Some(Hold {
                                    target: target.clone(),
                                    status,
                                    until: None,
                                });
                                status
                            }
                            Asked::Later { status, wait, failed } => {
                                if failed {
                                    *failures += 1;
                                }
                                *hold = Some(Hold {
                                    target: target.clone(),
                                    status,
                                    until: Some(now + wait),
                                });
                                if stored.watch.is_some() {
                                    Status::Registered
                                } else {
                                    status
                                }
                            }
                        }
                    }
                }
            }
        };

        if *stored != before {
            save(db, stored).await;
        }
        let watch_retry = hold
            .as_ref()
            .and_then(|hold| hold.until)
            .map(|until| (until - now).max(1));
        let unwatch_retry = (!stored.unwatch.is_empty()).then_some(UNWATCH_RETRY_SECS);
        Outcome {
            status,
            retry_in: match (watch_retry, unwatch_retry) {
                (Some(a), Some(b)) => Some(a.min(b)),
                (a, b) => a.or(b),
            },
        }
    }
}

/// With no watch wanted: off, or on and waiting for what is missing.
fn idle(enabled: bool) -> Status {
    if enabled {
        Status::Waiting
    } else {
        Status::Off
    }
}

/// Whether a wait set to end at `until` still holds at `now`. A clock set
/// back by more than the longest wait does not hold the watch for ever.
fn holds(until: i64, now: i64) -> bool {
    now < until && until - now <= MAX_RETRY_AFTER_SECS
}

/// A `4xx` that no retry changes. `429` asks to wait, and `408` is a
/// timeout.
fn is_refusal(status: u16) -> bool {
    (400..500).contains(&status) && status != 429 && status != 408
}

/// What can be an FCM token: printable ASCII with no space, not empty and
/// not absurdly long. The server checks a new token with FCM itself.
fn is_token(token: &str) -> bool {
    !token.is_empty() && token.len() <= MAX_TOKEN_LEN && token.bytes().all(|b| b.is_ascii_graphic())
}

/// How asking for a watch went.
enum Asked {
    Taken,
    /// Not until the target changes.
    Refused(Status),
    /// Not for `wait` seconds. `failed` tells a failure from a rate limit.
    Later {
        status: Status,
        wait: i64,
        failed: bool,
    },
}

async fn ask(server: &str, target: &Target, failures: usize) -> Asked {
    let failure = |why: String| {
        log::info!("[push] watch not registered: {why}");
        Asked::Later {
            status: Status::ServerUnavailable,
            wait: RETRY_WAITS_SECS[failures.min(RETRY_WAITS_SECS.len() - 1)],
            failed: true,
        }
    };
    match post(server, "watch", target).await {
        Ok(reply) => match reply.status {
            200 => Asked::Taken,
            403 => {
                log::info!("[push] watch refused: the node is not trusted by the server");
                Asked::Refused(Status::NodeNotTrusted)
            }
            429 => Asked::Later {
                status: Status::RateLimited,
                wait: reply
                    .retry_after
                    .unwrap_or(RATE_LIMIT_WAIT_SECS)
                    .clamp(1, MAX_RETRY_AFTER_SECS),
                failed: false,
            },
            status if is_refusal(status) => {
                log::info!("[push] watch refused: server returned {status}");
                Asked::Refused(Status::TokenRefused)
            }
            status => failure(format!("server returned {status}")),
        },
        Err(e) => failure(e.to_string()),
    }
}

struct Reply {
    status: u16,
    /// `Retry-After`, when it is a number of seconds.
    retry_after: Option<i64>,
}

/// `POST /api/disputes/<action>` for `target`.
async fn post(server: &str, action: &str, target: &Target) -> anyhow::Result<Reply> {
    let mut body = serde_json::json!({
        "mostro_pubkey": target.node,
        "token": target.token,
    });
    if action == "watch" {
        body["platform"] = "android".into();
    }
    // Per request: the wasm builder has no timeout.
    let response = http_client()?
        .post(format!("{server}/api/disputes/{action}"))
        .header(reqwest::header::CONTENT_TYPE, "application/json")
        .body(body.to_string())
        .timeout(REQUEST_TIMEOUT)
        .send()
        .await
        // The URL an error names is the server's, never the token.
        .map_err(|e| anyhow::anyhow!("request failed: {e}"))?;
    Ok(Reply {
        status: response.status().as_u16(),
        retry_after: response
            .headers()
            .get(reqwest::header::RETRY_AFTER)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.trim().parse().ok()),
    })
}

/// What is stored, read once. Without storage, or when what is stored
/// cannot be read, it starts empty: notifications off.
async fn stored<'a>(inner: &'a mut Inner, db: Option<&impl Storage>) -> &'a mut Stored {
    if inner.stored.is_none() {
        let read = match db {
            Some(db) => match db.get_setting(settings_keys::PUSH_WATCH).await {
                Ok(Some(json)) => serde_json::from_str(&json).unwrap_or_else(|_| {
                    log::warn!("[push] the stored watch is not readable; starting over");
                    Stored::default()
                }),
                Ok(None) => Stored::default(),
                Err(e) => {
                    log::warn!("[push] the stored watch was not read: {e}");
                    Stored::default()
                }
            },
            None => Stored::default(),
        };
        inner.stored = Some(read);
    }
    inner.stored.as_mut().expect("just filled")
}

/// Best effort, as the other settings: a failed write is logged and the
/// session goes on from memory.
async fn save(db: Option<&impl Storage>, stored: &Stored) {
    let Some(db) = db else { return };
    let json = match serde_json::to_string(stored) {
        Ok(json) => json,
        Err(e) => {
            log::warn!("[push] the watch was not stored: {e}");
            return;
        }
    };
    if let Err(e) = db.set_setting(settings_keys::PUSH_WATCH, &json).await {
        log::warn!("[push] the watch was not stored: {e}");
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::db::sqlite::SqliteStorage;
    use crate::push::wake::tests::{serve, serve_with, Request, Seen};
    use std::sync::atomic::{AtomicU16, Ordering};
    use std::sync::Arc;

    const NOW: i64 = 1_800_000_000;
    const NODE_A: &str = "aa00000000000000000000000000000000000000000000000000000000000001";
    const NODE_B: &str = "bb00000000000000000000000000000000000000000000000000000000000002";
    const TOKEN: &str = "device-token:APA91b_one";
    const OTHER_TOKEN: &str = "device-token:APA91b_two";

    async fn store() -> SqliteStorage {
        crate::db::sqlite::tests::store().await
    }

    fn on(node: &str) -> Inputs {
        Inputs {
            node: Some(node.to_string()),
            has_key: true,
        }
    }

    /// A watcher with notifications on and a token.
    async fn ready(server: &str, db: &SqliteStorage) -> Watcher {
        let watcher = Watcher::to(server);
        watcher.set_enabled(Some(db), true).await;
        watcher
            .set_token(Some(db), Some(TOKEN.to_string()))
            .await
            .unwrap();
        watcher
    }

    /// What the server was asked, in order: the path's last part, the node
    /// and the token.
    fn asked(seen: &Seen) -> Vec<(String, String, String)> {
        seen.lock().unwrap().iter().map(request).collect()
    }

    fn request(request: &Request) -> (String, String, String) {
        let path = request.line.split(' ').nth(1).unwrap();
        let body: serde_json::Value = serde_json::from_str(&request.body).unwrap();
        (
            path.rsplit('/').next().unwrap().to_string(),
            body["mostro_pubkey"].as_str().unwrap().to_string(),
            body["token"].as_str().unwrap().to_string(),
        )
    }

    fn call(action: &str, node: &str, token: &str) -> (String, String, String) {
        (action.to_string(), node.to_string(), token.to_string())
    }

    /// A server whose answer to a watch and to an unwatch can be changed.
    async fn server(watch: u16, unwatch: u16) -> (String, Seen, Arc<AtomicU16>, Arc<AtomicU16>) {
        let watch = Arc::new(AtomicU16::new(watch));
        let unwatch = Arc::new(AtomicU16::new(unwatch));
        let (w, u) = (watch.clone(), unwatch.clone());
        let (base, seen) = serve_with(move |request| {
            let status = if request.line.contains("/unwatch") {
                u.load(Ordering::SeqCst)
            } else {
                w.load(Ordering::SeqCst)
            };
            (status, Vec::new())
        })
        .await;
        (base, seen, watch, unwatch)
    }

    #[tokio::test]
    async fn the_watch_names_the_node_the_token_and_the_platform_and_nothing_else() {
        let (base, seen) = serve(200).await;
        let db = store().await;
        let watcher = ready(&format!("{base}/"), &db).await;

        let outcome = watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;

        assert_eq!(
            outcome,
            Outcome {
                status: Status::Registered,
                retry_in: None
            }
        );
        let requests = seen.lock().unwrap().clone();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].line, "POST /api/disputes/watch HTTP/1.1");
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&requests[0].body).unwrap(),
            serde_json::json!({ "mostro_pubkey": NODE_A, "token": TOKEN, "platform": "android" })
        );
        let head = requests[0].head.to_ascii_lowercase();
        assert!(head.contains("content-type: application/json"));
        for header in ["authorization:", "cookie:", "user-agent:", "x-request-id:"] {
            assert!(!head.contains(header), "{header} is sent");
        }
    }

    #[tokio::test]
    async fn nothing_is_asked_while_notifications_are_off_or_something_is_missing() {
        let (base, seen) = serve(200).await;
        let db = store().await;
        let watcher = Watcher::to(&base);

        // Off, the state of a new install.
        let off = watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;
        assert_eq!(off.status, Status::Off);

        // On, with no token yet.
        watcher.set_enabled(Some(&db), true).await;
        let no_token = watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;
        assert_eq!(no_token.status, Status::Waiting);

        // A token, and no node or no key.
        watcher
            .set_token(Some(&db), Some(TOKEN.to_string()))
            .await
            .unwrap();
        for inputs in [
            Inputs {
                node: None,
                has_key: true,
            },
            Inputs {
                node: Some(NODE_A.to_string()),
                has_key: false,
            },
        ] {
            let outcome = watcher.reconcile(Some(&db), &inputs, NOW).await;
            assert_eq!(outcome.status, Status::Waiting, "{inputs:?}");
        }

        assert!(seen.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_fresh_watch_is_not_asked_for_again_and_one_a_day_old_is_renewed() {
        let (base, seen) = serve(200).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;

        watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;
        let soon = watcher
            .reconcile(Some(&db), &on(NODE_A), NOW + RENEW_AFTER_SECS - 1)
            .await;
        assert_eq!(soon.status, Status::Registered);
        assert_eq!(seen.lock().unwrap().len(), 1);

        let later = watcher
            .reconcile(Some(&db), &on(NODE_A), NOW + RENEW_AFTER_SECS)
            .await;
        assert_eq!(later.status, Status::Registered);
        assert_eq!(
            asked(&seen),
            vec![call("watch", NODE_A, TOKEN), call("watch", NODE_A, TOKEN)]
        );
    }

    #[tokio::test]
    async fn the_watch_survives_a_restart() {
        let (base, seen) = serve(200).await;
        let db = store().await;
        ready(&base, &db)
            .await
            .reconcile(Some(&db), &on(NODE_A), NOW)
            .await;

        // Another process, the same storage.
        let restarted = Watcher::to(&base);
        assert!(restarted.enabled(Some(&db)).await);
        let outcome = restarted
            .reconcile(Some(&db), &on(NODE_A), NOW + 60)
            .await;

        assert_eq!(outcome.status, Status::Registered);
        assert_eq!(seen.lock().unwrap().len(), 1, "still fresh: not asked again");
    }

    #[tokio::test]
    async fn a_node_switch_drops_the_old_watch_and_asks_for_the_new_one() {
        let (base, seen) = serve(200).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;
        watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;

        let outcome = watcher.reconcile(Some(&db), &on(NODE_B), NOW + 5).await;

        assert_eq!(
            outcome,
            Outcome {
                status: Status::Registered,
                retry_in: None
            }
        );
        assert_eq!(
            asked(&seen),
            vec![
                call("watch", NODE_A, TOKEN),
                call("unwatch", NODE_A, TOKEN),
                call("watch", NODE_B, TOKEN),
            ]
        );
    }

    #[tokio::test]
    async fn a_failed_unwatch_does_not_hold_back_the_new_watch_and_is_tried_again() {
        let (base, seen, _watch, unwatch) = server(200, 500).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;
        watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;

        // The switch: the old node cannot be told, the new one is watched.
        let switched = watcher.reconcile(Some(&db), &on(NODE_B), NOW + 5).await;
        assert_eq!(switched.status, Status::Registered);
        assert_eq!(switched.retry_in, Some(UNWATCH_RETRY_SECS));

        // The next run tries the unwatch again, and only that.
        unwatch.store(200, Ordering::SeqCst);
        let later = watcher.reconcile(Some(&db), &on(NODE_B), NOW + 60).await;
        assert_eq!(later.retry_in, None);

        assert_eq!(
            asked(&seen),
            vec![
                call("watch", NODE_A, TOKEN),
                call("unwatch", NODE_A, TOKEN),
                call("watch", NODE_B, TOKEN),
                call("unwatch", NODE_A, TOKEN),
            ]
        );
    }

    #[tokio::test]
    async fn an_unwatch_still_to_do_survives_a_restart() {
        let (base, seen, _watch, unwatch) = server(200, 503).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;
        watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;
        watcher.reconcile(Some(&db), &on(NODE_B), NOW + 5).await;

        unwatch.store(200, Ordering::SeqCst);
        Watcher::to(&base)
            .reconcile(Some(&db), &on(NODE_B), NOW + 60)
            .await;

        assert_eq!(asked(&seen).last(), Some(&call("unwatch", NODE_A, TOKEN)));
    }

    #[tokio::test]
    async fn switching_back_keeps_the_watch_instead_of_dropping_it_afterwards() {
        let (base, seen, _watch, unwatch) = server(200, 500).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;
        watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;
        watcher.reconcile(Some(&db), &on(NODE_B), NOW + 5).await;

        // Back to A while its unwatch is still to do: A is wanted, so that
        // unwatch is forgotten, and B's is the one to do.
        unwatch.store(200, Ordering::SeqCst);
        let back = watcher.reconcile(Some(&db), &on(NODE_A), NOW + 10).await;

        assert_eq!(back.status, Status::Registered);
        assert_eq!(
            asked(&seen)[3..],
            [call("unwatch", NODE_B, TOKEN), call("watch", NODE_A, TOKEN)]
        );
    }

    #[tokio::test]
    async fn a_new_token_drops_the_watch_of_the_old_one() {
        let (base, seen) = serve(200).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;
        watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;

        watcher
            .set_token(Some(&db), Some(OTHER_TOKEN.to_string()))
            .await
            .unwrap();
        let outcome = watcher.reconcile(Some(&db), &on(NODE_A), NOW + 5).await;

        assert_eq!(outcome.status, Status::Registered);
        assert_eq!(
            asked(&seen)[1..],
            [
                call("unwatch", NODE_A, TOKEN),
                call("watch", NODE_A, OTHER_TOKEN)
            ]
        );
    }

    #[tokio::test]
    async fn turning_notifications_off_drops_the_watch() {
        let (base, seen) = serve(200).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;
        watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;

        // Off, and the token deleted, as Dart does.
        watcher.set_enabled(Some(&db), false).await;
        watcher.set_token(Some(&db), None).await.unwrap();
        let outcome = watcher.reconcile(Some(&db), &on(NODE_A), NOW + 5).await;

        assert_eq!(
            outcome,
            Outcome {
                status: Status::Off,
                retry_in: None
            }
        );
        assert_eq!(asked(&seen)[1..], [call("unwatch", NODE_A, TOKEN)]);
        // And nothing more afterwards.
        watcher.reconcile(Some(&db), &on(NODE_A), NOW + 10).await;
        assert_eq!(seen.lock().unwrap().len(), 2);
    }

    #[tokio::test]
    async fn logging_out_drops_the_watch_and_logging_in_asks_for_it_again() {
        let (base, seen) = serve(200).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;
        watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;

        let logged_out = Inputs {
            node: Some(NODE_A.to_string()),
            has_key: false,
        };
        let out = watcher.reconcile(Some(&db), &logged_out, NOW + 5).await;
        assert_eq!(out.status, Status::Waiting);

        let back = watcher.reconcile(Some(&db), &on(NODE_A), NOW + 10).await;
        assert_eq!(back.status, Status::Registered);

        assert_eq!(
            asked(&seen)[1..],
            [call("unwatch", NODE_A, TOKEN), call("watch", NODE_A, TOKEN)]
        );
    }

    #[tokio::test]
    async fn a_node_the_server_does_not_trust_is_not_asked_for_again_until_the_node_changes() {
        let (base, seen, watch, _unwatch) = server(403, 200).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;

        let refused = watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;
        assert_eq!(
            refused,
            Outcome {
                status: Status::NodeNotTrusted,
                retry_in: None
            }
        );
        let again = watcher
            .reconcile(Some(&db), &on(NODE_A), NOW + 7 * 86_400)
            .await;
        assert_eq!(again.status, Status::NodeNotTrusted);
        assert_eq!(seen.lock().unwrap().len(), 1);

        // Another node is another question, and nothing is unwatched: the
        // server never held a watch of the refused one.
        watch.store(200, Ordering::SeqCst);
        let other = watcher.reconcile(Some(&db), &on(NODE_B), NOW + 10).await;
        assert_eq!(other.status, Status::Registered);
        assert_eq!(asked(&seen)[1..], [call("watch", NODE_B, TOKEN)]);
    }

    #[tokio::test]
    async fn a_refused_token_is_not_sent_again_until_the_token_changes() {
        let (base, seen, watch, _unwatch) = server(400, 200).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;

        let refused = watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;
        assert_eq!(
            refused,
            Outcome {
                status: Status::TokenRefused,
                retry_in: None
            }
        );
        watcher.reconcile(Some(&db), &on(NODE_A), NOW + 3_600).await;
        assert_eq!(seen.lock().unwrap().len(), 1);

        watch.store(200, Ordering::SeqCst);
        watcher
            .set_token(Some(&db), Some(OTHER_TOKEN.to_string()))
            .await
            .unwrap();
        let other = watcher.reconcile(Some(&db), &on(NODE_A), NOW + 3_601).await;
        assert_eq!(other.status, Status::Registered);
        assert_eq!(asked(&seen)[1..], [call("watch", NODE_A, OTHER_TOKEN)]);
    }

    #[tokio::test]
    async fn a_rate_limit_waits_what_the_server_says() {
        let limited = Arc::new(AtomicU16::new(429));
        let status = limited.clone();
        let (base, seen) = serve_with(move |_| {
            (
                status.load(Ordering::SeqCst),
                vec![("Retry-After", "90".to_string())],
            )
        })
        .await;
        let db = store().await;
        let watcher = ready(&base, &db).await;

        let first = watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;
        assert_eq!(
            first,
            Outcome {
                status: Status::RateLimited,
                retry_in: Some(90)
            }
        );

        // Before the wait is over nothing is asked.
        limited.store(200, Ordering::SeqCst);
        let early = watcher.reconcile(Some(&db), &on(NODE_A), NOW + 89).await;
        assert_eq!(
            early,
            Outcome {
                status: Status::RateLimited,
                retry_in: Some(1)
            }
        );
        assert_eq!(seen.lock().unwrap().len(), 1);

        let after = watcher.reconcile(Some(&db), &on(NODE_A), NOW + 90).await;
        assert_eq!(after.status, Status::Registered);
        assert_eq!(seen.lock().unwrap().len(), 2);
    }

    #[tokio::test]
    async fn a_rate_limit_that_names_no_wait_or_an_absurd_one_is_bounded() {
        for (header, wait) in [
            (None, RATE_LIMIT_WAIT_SECS),
            (Some("86400"), MAX_RETRY_AFTER_SECS),
            (Some("0"), 1),
            (Some("Wed, 21 Oct 2026 07:28:00 GMT"), RATE_LIMIT_WAIT_SECS),
        ] {
            let (base, _seen) = serve_with(move |_| {
                (
                    429,
                    header
                        .map(|value| vec![("Retry-After", value.to_string())])
                        .unwrap_or_default(),
                )
            })
            .await;
            let db = store().await;
            let outcome = ready(&base, &db)
                .await
                .reconcile(Some(&db), &on(NODE_A), NOW)
                .await;
            assert_eq!(outcome.retry_in, Some(wait), "{header:?}");
        }
    }

    #[tokio::test]
    async fn a_server_failure_is_tried_again_with_a_growing_wait() {
        let (base, seen, watch, _unwatch) = server(503, 200).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;

        let mut now = NOW;
        for wait in [30, 120, 600, 3_600, 3_600] {
            let outcome = watcher.reconcile(Some(&db), &on(NODE_A), now).await;
            assert_eq!(
                outcome,
                Outcome {
                    status: Status::ServerUnavailable,
                    retry_in: Some(wait)
                }
            );
            // Inside the wait nothing is asked.
            let early = watcher.reconcile(Some(&db), &on(NODE_A), now + wait - 1).await;
            assert_eq!(early.retry_in, Some(1));
            now += wait;
        }
        assert_eq!(seen.lock().unwrap().len(), 5);

        // It answers at last, and the next failure starts the waits over.
        watch.store(200, Ordering::SeqCst);
        let taken = watcher.reconcile(Some(&db), &on(NODE_A), now).await;
        assert_eq!(taken.status, Status::Registered);
        watch.store(503, Ordering::SeqCst);
        let failed = watcher
            .reconcile(Some(&db), &on(NODE_A), now + RENEW_AFTER_SECS)
            .await;
        assert_eq!(failed.retry_in, Some(30));
    }

    #[tokio::test]
    async fn a_server_that_cannot_be_reached_is_tried_again() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        drop(listener);
        let db = store().await;

        let outcome = ready(&base, &db)
            .await
            .reconcile(Some(&db), &on(NODE_A), NOW)
            .await;

        assert_eq!(
            outcome,
            Outcome {
                status: Status::ServerUnavailable,
                retry_in: Some(30)
            }
        );
    }

    #[tokio::test]
    async fn a_renewal_that_fails_leaves_the_watch_registered() {
        let (base, _seen, watch, _unwatch) = server(200, 200).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;
        watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;

        // A day later the server is down: it still holds the watch.
        watch.store(500, Ordering::SeqCst);
        let renewal = watcher
            .reconcile(Some(&db), &on(NODE_A), NOW + RENEW_AFTER_SECS)
            .await;

        assert_eq!(
            renewal,
            Outcome {
                status: Status::Registered,
                retry_in: Some(30)
            }
        );
    }

    #[tokio::test]
    async fn a_renewal_the_server_refuses_forgets_the_watch_without_unwatching_it() {
        let (base, seen, watch, _unwatch) = server(200, 200).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;
        watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;

        // The token died (the app's data was cleared, FCM rotated it).
        watch.store(400, Ordering::SeqCst);
        let renewal = watcher
            .reconcile(Some(&db), &on(NODE_A), NOW + RENEW_AFTER_SECS)
            .await;
        assert_eq!(renewal.status, Status::TokenRefused);

        // The node changes: nothing of the refused watch is unwatched.
        watch.store(200, Ordering::SeqCst);
        watcher
            .reconcile(Some(&db), &on(NODE_B), NOW + RENEW_AFTER_SECS + 5)
            .await;
        assert_eq!(asked(&seen)[2..], [call("watch", NODE_B, TOKEN)]);
    }

    #[tokio::test]
    async fn a_redirect_is_not_followed() {
        let (elsewhere, followed) = serve(200).await;
        let (base, _seen) = serve_with(move |_| {
            (
                307,
                vec![("Location", format!("{elsewhere}/api/disputes/watch"))],
            )
        })
        .await;
        let db = store().await;

        let outcome = ready(&base, &db)
            .await
            .reconcile(Some(&db), &on(NODE_A), NOW)
            .await;

        assert_eq!(outcome.status, Status::ServerUnavailable);
        assert!(followed.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_watcher_with_no_server_asks_nobody() {
        let db = store().await;
        let watcher = Watcher::new(None);
        watcher.set_enabled(Some(&db), true).await;
        watcher
            .set_token(Some(&db), Some(TOKEN.to_string()))
            .await
            .unwrap();

        let outcome = watcher.reconcile(Some(&db), &on(NODE_A), NOW).await;

        assert_eq!(
            outcome,
            Outcome {
                status: Status::ServerUnavailable,
                retry_in: None
            }
        );
    }

    #[tokio::test]
    async fn without_storage_the_watch_lasts_the_session() {
        let (base, seen) = serve(200).await;
        let none = None::<&SqliteStorage>;
        let watcher = Watcher::to(&base);
        watcher.set_enabled(none, true).await;
        watcher
            .set_token(none, Some(TOKEN.to_string()))
            .await
            .unwrap();

        let outcome = watcher.reconcile(none, &on(NODE_A), NOW).await;
        watcher.reconcile(none, &on(NODE_A), NOW + 5).await;

        assert_eq!(outcome.status, Status::Registered);
        assert_eq!(seen.lock().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn what_is_stored_and_unreadable_starts_over_with_notifications_off() {
        let db = store().await;
        db.set_setting(settings_keys::PUSH_WATCH, "not json")
            .await
            .unwrap();

        assert!(!Watcher::new(None).enabled(Some(&db)).await);
    }

    #[tokio::test]
    async fn notifications_are_offered_once_and_not_to_who_has_them_on() {
        let db = store().await;
        let watcher = Watcher::new(None);
        assert!(watcher.take_offer(Some(&db)).await);
        assert!(!watcher.take_offer(Some(&db)).await);
        // Not after a restart either.
        assert!(!Watcher::new(None).take_offer(Some(&db)).await);

        // Already on (turned on in Settings before any offer): nothing to
        // offer, now or later.
        let db = store().await;
        let watcher = Watcher::new(None);
        watcher.set_enabled(Some(&db), true).await;
        assert!(!watcher.take_offer(Some(&db)).await);
        watcher.set_enabled(Some(&db), false).await;
        assert!(!watcher.take_offer(Some(&db)).await);
    }

    #[tokio::test]
    async fn only_what_can_be_a_token_is_kept() {
        let db = store().await;
        let watcher = Watcher::new(None);

        for token in ["", "two words", "line\nbreak", "ñ", &"x".repeat(MAX_TOKEN_LEN + 1)] {
            let refused = watcher.set_token(Some(&db), Some(token.to_string())).await;
            assert_eq!(refused.unwrap_err().to_string(), "InvalidToken");
        }
        assert!(watcher
            .set_token(Some(&db), Some("x".repeat(MAX_TOKEN_LEN)))
            .await
            .is_ok());
    }

    #[test]
    fn a_token_is_never_printed() {
        let target = Target {
            node: NODE_A.to_string(),
            token: TOKEN.to_string(),
        };
        let watch = Watch {
            target: target.clone(),
            registered_at: NOW,
        };
        let hold = Hold {
            target: target.clone(),
            status: Status::RateLimited,
            until: None,
        };
        let pending = PendingUnwatch { target, since: NOW };

        for printed in [
            format!("{watch:?}"),
            format!("{hold:?}"),
            format!("{pending:?}"),
        ] {
            assert!(!printed.contains(TOKEN), "{printed}");
            assert!(printed.contains(NODE_A));
        }
    }

    #[test]
    fn a_wait_ends_and_a_refusal_is_told_from_a_failure() {
        assert!(holds(NOW + 10, NOW));
        assert!(!holds(NOW, NOW));
        assert!(
            !holds(NOW + MAX_RETRY_AFTER_SECS + 1, NOW),
            "a clock set back does not hold the watch for ever"
        );
        assert!(is_refusal(400) && is_refusal(404) && is_refusal(403));
        assert!(!is_refusal(429) && !is_refusal(408) && !is_refusal(500) && !is_refusal(200));
    }

    #[tokio::test]
    async fn unwatches_that_never_succeed_are_bounded_in_number_and_in_time() {
        let (base, _seen, _watch, _unwatch) = server(200, 500).await;
        let db = store().await;
        let watcher = ready(&base, &db).await;

        // Twelve switches, each leaving an unwatch that fails.
        for i in 0..12 {
            let node = format!("{i:064x}");
            watcher.reconcile(Some(&db), &on(&node), NOW + i).await;
        }
        let stored: Stored = serde_json::from_str(
            &db.get_setting(settings_keys::PUSH_WATCH)
                .await
                .unwrap()
                .unwrap(),
        )
        .unwrap();
        assert_eq!(stored.unwatch.len(), MAX_PENDING_UNWATCHES);
        assert_eq!(stored.unwatch.last().unwrap().target.node, format!("{:064x}", 10));

        // Thirty days on, the server let them lapse: none is kept.
        let node = format!("{:064x}", 11);
        watcher
            .reconcile(Some(&db), &on(&node), NOW + FORGET_UNWATCH_AFTER_SECS + 60)
            .await;
        let stored: Stored = serde_json::from_str(
            &db.get_setting(settings_keys::PUSH_WATCH)
                .await
                .unwrap()
                .unwrap(),
        )
        .unwrap();
        assert!(stored.unwatch.is_empty());
    }
}
