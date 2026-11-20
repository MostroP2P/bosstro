//! The wake a party gets when the solver writes to it, through
//! [mostro-push-server](https://github.com/MostroP2P/mostro-push-server)
//! (`POST /api/notify`).
//!
//! A dispute chat envelope is `p`-tagged to `pub(K_conv)`, which the push
//! server cannot match to any registration: a party whose app is in the
//! background would learn of the solver's message only when they next open
//! it. So after a message reached a relay, the sender asks the server to ring
//! the party's **trade pubkey**, as MostroP2P/app's `wake_peer` and Mostrix's
//! `wake_recipient` do.
//!
//! - **Debounced per party**: a burst of short messages is one wake.
//! - **Fire-and-forget**: spawned, never awaited by the send, never retried.
//!   A wake that fails is logged and changes nothing of the message.
//! - **Nothing identifying**: the body is the party's trade pubkey and
//!   nothing else; no solver key, no signature, no dispute id. The server
//!   still sees the solver's IP address next to that pubkey. The pubkey is
//!   never logged.
//! - **Always on**: there is no setting for it, as in MostroP2P/app. The
//!   server answers `202` whether or not the party registered, so the wake
//!   tells the solver nothing about the party either.
//!
//! On the web build the request is the browser's `fetch`, which the server
//! refuses for an origin it does not list (CORS): the wake fails and is
//! logged like any other.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use nostr_sdk::prelude::PublicKey;

use crate::rt::time::Duration;

/// The instance MostroP2P/app registers its devices with.
const SERVER_URL: &str = "https://mostro-push-server.fly.dev";

/// At most one wake per party per this many seconds (MostroP2P/app's and
/// Mostrix's value), far under the server's own limit per pubkey.
const NOTIFY_DEBOUNCE_SECS: i64 = 10;

/// How long a party's last wake is remembered: past it the entry decides
/// nothing, and dropping it keeps the memory small.
const FORGET_AFTER_SECS: i64 = 3_600;

const NOTIFY_TIMEOUT: Duration = Duration::from_secs(10);

/// How a wake went.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Wake {
    /// The server took the request. It says nothing of whether the party is
    /// registered, by design.
    Sent,
    /// This party was woken a moment ago: nothing was sent.
    Debounced,
    /// The server refused it or could not be reached.
    NotDelivered,
}

/// Whether a party last woken at `last` may be woken at `now` (Unix
/// seconds). A clock set back since then does not silence the party.
fn notify_allowed(last: Option<i64>, now: i64) -> bool {
    last.is_none_or(|at| now < at || now - at >= NOTIFY_DEBOUNCE_SECS)
}

/// Wakes parties through one push server, remembering when each was last
/// woken.
pub(crate) struct Waker {
    server: String,
    /// Trade pubkey (hex) → the Unix time of its last wake.
    last: Mutex<HashMap<String, i64>>,
}

impl Waker {
    /// The one the app uses.
    pub(crate) fn production() -> Arc<Self> {
        Self::to(SERVER_URL)
    }

    /// One that asks the server at `server` (a base URL).
    pub(crate) fn to(server: &str) -> Arc<Self> {
        Arc::new(Self {
            server: server.trim_end_matches('/').to_string(),
            last: Mutex::new(HashMap::new()),
        })
    }

    /// Wake the party whose trade key is `party`, in the background.
    pub(crate) fn wake(self: &Arc<Self>, party: &PublicKey) {
        let (waker, party) = (self.clone(), party.to_hex());
        crate::rt::spawn(async move {
            let wake = waker.notify(&party, crate::rt::unix_now()).await;
            log::debug!("[push] party wake: {wake:?}");
        });
    }

    async fn notify(&self, trade_pubkey: &str, now: i64) -> Wake {
        {
            let Ok(mut last) = self.last.lock() else {
                return Wake::NotDelivered;
            };
            if !notify_allowed(last.get(trade_pubkey).copied(), now) {
                return Wake::Debounced;
            }
            // Before the request, not after: two messages sent while the
            // first request is still in flight must not both ring.
            last.insert(trade_pubkey.to_string(), now);
            last.retain(|_, at| now - *at < FORGET_AFTER_SECS);
        }
        match self.post(trade_pubkey).await {
            Ok(()) => Wake::Sent,
            Err(e) => {
                log::info!("[push] party wake not delivered: {e}");
                Wake::NotDelivered
            }
        }
    }

    async fn post(&self, trade_pubkey: &str) -> anyhow::Result<()> {
        let body = serde_json::json!({ "trade_pubkey": trade_pubkey }).to_string();
        // Per request: the wasm builder has no timeout.
        let response = http_client()?
            .post(format!("{}/api/notify", self.server))
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(body)
            .timeout(NOTIFY_TIMEOUT)
            .send()
            .await
            // The URL an error names is the server's, never the pubkey.
            .map_err(|e| anyhow::anyhow!("request failed: {e}"))?;
        if !response.status().is_success() {
            anyhow::bail!("server returned {}", response.status());
        }
        Ok(())
    }
}

/// Natively no redirect is followed: the body goes to the server named here
/// and nowhere it points to. The browser follows redirects itself.
fn http_client() -> anyhow::Result<reqwest::Client> {
    let builder = reqwest::Client::builder();
    #[cfg(not(target_arch = "wasm32"))]
    let builder = builder.redirect(reqwest::redirect::Policy::none());
    builder
        .build()
        .map_err(|e| anyhow::anyhow!("HTTP client build failed: {e}"))
}

#[cfg(all(test, not(target_arch = "wasm32")))]
pub(crate) mod tests {
    use super::*;
    use nostr_sdk::prelude::Keys;

    const NOW: i64 = 1_800_000_000;

    /// One request a [`serve`]d server received.
    #[derive(Debug, Clone)]
    pub(crate) struct Request {
        pub(crate) line: String,
        pub(crate) head: String,
        pub(crate) body: String,
    }

    pub(crate) type Seen = Arc<Mutex<Vec<Request>>>;

    /// The trade pubkeys the server was asked to wake, in order.
    pub(crate) fn woken(seen: &Seen) -> Vec<String> {
        seen.lock()
            .unwrap()
            .iter()
            .map(|request| {
                let body: serde_json::Value = serde_json::from_str(&request.body).unwrap();
                body["trade_pubkey"].as_str().unwrap().to_string()
            })
            .collect()
    }

    /// A push server answering every request with `status`, recording what
    /// it received. Returns its base URL.
    pub(crate) async fn serve(status: u16) -> (String, Seen) {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let seen = Seen::default();
        let log = seen.clone();
        tokio::spawn(async move {
            while let Ok((mut socket, _)) = listener.accept().await {
                let mut raw = Vec::new();
                let mut buf = [0u8; 4096];
                let complete = |raw: &[u8]| {
                    let end = raw.windows(4).position(|w| w == b"\r\n\r\n")? + 4;
                    let head = String::from_utf8_lossy(&raw[..end]).to_string();
                    let length = head
                        .lines()
                        .filter_map(|line| line.split_once(':'))
                        .find(|(name, _)| name.eq_ignore_ascii_case("content-length"))
                        .and_then(|(_, value)| value.trim().parse::<usize>().ok())
                        .unwrap_or(0);
                    (raw.len() >= end + length).then(|| {
                        let body = String::from_utf8_lossy(&raw[end..end + length]).to_string();
                        (head, body)
                    })
                };
                let request = loop {
                    if let Some(request) = complete(&raw) {
                        break Some(request);
                    }
                    match socket.read(&mut buf).await {
                        Ok(n) if n > 0 => raw.extend_from_slice(&buf[..n]),
                        _ => break None,
                    }
                };
                if let Some((head, body)) = request {
                    log.lock().unwrap().push(Request {
                        line: head.lines().next().unwrap_or_default().to_string(),
                        head,
                        body,
                    });
                }
                let reply = format!(
                    "HTTP/1.1 {status} X\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                );
                let _ = socket.write_all(reply.as_bytes()).await;
                let _ = socket.shutdown().await;
            }
        });
        (base, seen)
    }

    fn party() -> String {
        Keys::generate().public_key().to_hex()
    }

    #[test]
    fn a_party_is_woken_again_only_after_the_debounce() {
        assert!(notify_allowed(None, NOW));
        assert!(!notify_allowed(Some(NOW - 3), NOW));
        assert!(!notify_allowed(Some(NOW), NOW));
        assert!(notify_allowed(Some(NOW - NOTIFY_DEBOUNCE_SECS), NOW));
        assert!(
            notify_allowed(Some(NOW + 5), NOW),
            "a clock set back does not silence the party"
        );
    }

    #[tokio::test]
    async fn the_wake_names_the_trade_pubkey_and_nothing_else() {
        let (base, seen) = serve(202).await;
        let party = party();

        // A trailing slash in the base does not double up in the path.
        let waker = Waker::to(&format!("{base}/"));
        assert_eq!(waker.notify(&party, NOW).await, Wake::Sent);

        let requests = seen.lock().unwrap().clone();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].line, "POST /api/notify HTTP/1.1");
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&requests[0].body).unwrap(),
            serde_json::json!({ "trade_pubkey": party })
        );
        let head = requests[0].head.to_ascii_lowercase();
        assert!(head.contains("content-type: application/json"));
        for header in ["authorization:", "cookie:", "user-agent:", "x-request-id:"] {
            assert!(!head.contains(header), "{header} is sent");
        }
    }

    #[tokio::test]
    async fn a_burst_is_one_wake_and_holds_no_other_party_back() {
        let (base, seen) = serve(202).await;
        let waker = Waker::to(&base);
        let (one, other) = (party(), party());

        assert_eq!(waker.notify(&one, NOW).await, Wake::Sent);
        assert_eq!(waker.notify(&one, NOW + 3).await, Wake::Debounced);
        assert_eq!(waker.notify(&other, NOW + 3).await, Wake::Sent);
        assert_eq!(
            waker.notify(&one, NOW + NOTIFY_DEBOUNCE_SECS).await,
            Wake::Sent
        );

        assert_eq!(woken(&seen), vec![one.clone(), other, one]);
    }

    #[tokio::test]
    async fn a_refusal_is_not_delivered_and_is_not_tried_again() {
        let (base, seen) = serve(500).await;
        let waker = Waker::to(&base);
        let party = party();

        assert_eq!(waker.notify(&party, NOW).await, Wake::NotDelivered);
        assert_eq!(waker.notify(&party, NOW + 1).await, Wake::Debounced);
        assert_eq!(seen.lock().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn a_redirect_is_not_followed() {
        let (elsewhere, followed) = serve(202).await;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        tokio::spawn(async move {
            use tokio::io::{AsyncReadExt, AsyncWriteExt};
            while let Ok((mut socket, _)) = listener.accept().await {
                let mut buf = [0u8; 4096];
                let _ = socket.read(&mut buf).await;
                let reply = format!(
                    "HTTP/1.1 307 X\r\nLocation: {elsewhere}/api/notify\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                );
                let _ = socket.write_all(reply.as_bytes()).await;
                let _ = socket.shutdown().await;
            }
        });

        let wake = Waker::to(&base).notify(&party(), NOW).await;

        assert_eq!(wake, Wake::NotDelivered);
        assert!(followed.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_server_that_cannot_be_reached_is_not_delivered() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        drop(listener);

        let wake = Waker::to(&base).notify(&party(), NOW).await;

        assert_eq!(wake, Wake::NotDelivered);
    }

    #[tokio::test]
    async fn old_wakes_are_forgotten() {
        let (base, _seen) = serve(202).await;
        let waker = Waker::to(&base);

        waker.notify(&party(), NOW).await;
        waker.notify(&party(), NOW + FORGET_AFTER_SECS).await;

        assert_eq!(waker.last.lock().unwrap().len(), 1);
    }
}
