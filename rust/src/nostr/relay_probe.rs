//! Asking a `Connected` relay whether it is still there. From MostroP2P/app's
//! `nostr/relay_probe.rs`, with its resume nudge
//! ([`reconnect_disconnected_now`], used by [`super::resync`]). The issue and
//! PR numbers below are MostroP2P/app's.
//!
//! Every recovery path in this client is keyed on an **observed** change:
//! a relay transitioning to `Disconnected`, the pool going `Online`, a relay
//! sending `CLOSED`, or the app resuming. A connection that keeps answering
//! the protocol while delivering nothing produces none of those, so nothing
//! wakes [`crate::nostr::live_subs`] — and `repair_relay` would report zero
//! anyway, since the SDK's registry still lists the subscription as present.
//!
//! Measured against a live daemon (MostroP2P/app#291): with the relay frozen so it
//! could not answer the WebSocket PONG, the SDK's own ping caught it in 56 s
//! and `live_subs` re-issued every subscription 15 s after it came back. With
//! a proxy answering the pings while swallowing the relay's frames, the app
//! was deaf for **6 minutes without logging a single line**, and the five
//! events it missed were never requested again. That second shape is what
//! this module detects. It is also the shape of a REQ refused over a relay's
//! per-connection cap: the subscription never existed, and the `NOTICE`
//! names none, so nothing can repair it.
//!
//! **Traffic proves life; silence proves nothing.** That asymmetry is the
//! whole design. Recent traffic from a relay is taken as proof it is healthy
//! and skips the probe — but a quiet relay is never *concluded* dead, only
//! asked. MostroP2P/app#324 measured 240 s of silence on a perfectly healthy relay and
//! would have reconnected it, so a silence timer cannot be the signal.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use crate::rt::time::Instant;

use nostr_sdk::prelude::{Client, EventId, Filter, Relay, RelayStatus};

use super::relay_pool::display_relay;

/// How long a relay may stay quiet before it is asked whether it is alive.
pub(crate) const PROBE_INTERVAL: Duration = Duration::from_secs(120);

/// How long the relay has to answer the probe's EOSE. Generous next to the
/// measured round trips (20 ms on a local nostr-rs-relay, 820 ms on nos.lol)
/// so a slow relay is never mistaken for a dead one.
pub(crate) const PROBE_TIMEOUT: Duration = Duration::from_secs(15);

/// Traffic newer than this makes a probe pointless: something arrived, so the
/// socket delivers.
pub(crate) const FRESH_TRAFFIC_WINDOW: Duration = Duration::from_secs(120);

/// How long [`force_reconnect`] leaves between dropping a socket and asking
/// for it back.
///
/// It cannot be keyed on the status: `disconnect_relay` reports `Terminated`
/// immediately while the teardown is still in flight, so waiting for the
/// status to move returns at once and achieves nothing. Measured against a
/// MockRelay — reconnecting with no grace leaves the relay stuck in
/// `Disconnected`/`Connecting` past five seconds; 250 ms of grace has it
/// `Connected` again. (MostroP2P/app#324 carried a 200 ms sleep here for the same reason,
/// undocumented.)
const RECONNECT_GRACE: Duration = Duration::from_millis(250);

/// The probe's filter: one event id of 32 zero bytes, which nothing can match,
/// so a healthy relay answers EOSE with no events at all.
///
/// **Not** `limit(0)`, the obvious candidate: measured, strfry (nos.lol)
/// answers it with EOSE in 0.8 s but nostr-rs-relay never answers it at all,
/// which would have made every such relay look dead. An id filter that cannot
/// match is answered by both — 0.02 s and 0.82 s respectively.
pub(crate) fn probe_filter() -> Filter {
    Filter::new().id(EventId::from_byte_array([0u8; 32]))
}

/// When each relay was last heard from, and last asked.
///
/// Keyed by relay URL so one relay's traffic never vouches for another's
/// socket — the flaw ermeme caught in MostroP2P/app#324's first round, where a pool-wide
/// timestamp meant a live relay masked a dead one.
#[derive(Debug, Default)]
pub(crate) struct RelayLiveness {
    seen: HashMap<String, i64>,
    probed: HashMap<String, i64>,
}

impl RelayLiveness {
    /// Something arrived from `url`: an event, or any relay message.
    pub(crate) fn record_traffic(&mut self, url: &str, at: i64) {
        self.seen.insert(url.to_string(), at);
    }

    /// A probe was issued to `url`, whatever its outcome. Recording it on the
    /// attempt, not on success, is what keeps a still-silent relay from being
    /// probed again on the very next tick.
    pub(crate) fn record_probe(&mut self, url: &str, at: i64) {
        self.probed.insert(url.to_string(), at);
    }

    /// Drop everything known about `url` — it left the pool.
    pub(crate) fn forget(&mut self, url: &str) {
        self.seen.remove(url);
        self.probed.remove(url);
    }

    pub(crate) fn last_seen(&self, url: &str) -> Option<i64> {
        self.seen.get(url).copied()
    }

    pub(crate) fn last_probe(&self, url: &str) -> Option<i64> {
        self.probed.get(url).copied()
    }
}

/// Whether `url` should be asked, now.
///
/// A relay with no traffic on record is a candidate rather than an exemption:
/// the one thing a connection that has never delivered anything deserves is a
/// question. MostroP2P/app#324 took the opposite reading — a missing baseline disabled its
/// recovery for good — and needed a review round to seed one at connect time.
/// Asking costs a REQ and an EOSE, and a healthy relay answers, so the
/// pessimistic default is the safe one here.
pub(crate) fn should_probe(
    status: RelayStatus,
    last_seen: Option<i64>,
    last_probe: Option<i64>,
    now: i64,
) -> bool {
    // A relay the SDK already knows is down is the SDK's to reconnect; only
    // one that still claims to be Connected can be silently dead.
    if status != RelayStatus::Connected {
        return false;
    }
    if within(last_seen, now, FRESH_TRAFFIC_WINDOW) {
        return false;
    }
    !within(last_probe, now, PROBE_INTERVAL)
}

/// Whether `stamp` is set and newer than `window` ago.
fn within(stamp: Option<i64>, now: i64, window: Duration) -> bool {
    stamp.is_some_and(|at| now.saturating_sub(at) < window.as_secs() as i64)
}

/// Ask `relay` whether it is still delivering, and wait [`PROBE_TIMEOUT`]
/// for the answer. `true` means it answered.
///
/// A one-shot fetch, not a long-lived subscription: it opens its own REQ,
/// exits on EOSE and is gone, so it stays out of [`crate::nostr::live_subs`]
/// and costs a relay's per-connection cap only for as long as it runs.
pub(crate) async fn probe_once(relay: &Relay) -> bool {
    probe_within(relay, PROBE_TIMEOUT).await
}

/// [`probe_once`] with the deadline spelled out, so a test can use one short
/// enough to wait for.
///
/// Two layers have to be `Ok`, and each one is a way to read this wrong:
///
/// - The deadline is **ours**, not `FetchEvents::timeout`: measured, the SDK's
///   own timeout is not a failure but the end of collection, so a fetch against
///   a relay that answered nothing at all still returns `Ok` with an empty set.
/// - The fetch itself returns a `Result` too, and an `Err` from it — a
///   transport failure, a relay gone from the pool — is evidence of trouble,
///   not of an answer. Only the outer layer completing *with* an inner `Ok`
///   means the relay replied.
///
/// Either misreading leaves the probe unable to detect the thing it exists to
/// detect. The first one is the shape the live runs exercise: a half-dead
/// socket does not error, it simply never answers.
async fn probe_within(relay: &Relay, limit: Duration) -> bool {
    crate::rt::time::timeout(
        limit,
        std::future::IntoFuture::into_future(relay.fetch_events(probe_filter())),
    )
    .await
    .is_ok_and(|fetched| fetched.is_ok())
}

/// Bounce `url`'s connection so the reconnect re-issues its subscriptions.
///
/// The recovery is deliberately indirect: dropping and restoring the socket
/// is what produces the `→Connected` transition that `live_subs::repair_relay`
/// already listens for, and that repair is what re-REQs — which is what
/// actually replays the backlog. Merely noticing would leave the client where
/// the measurement found it: deaf, with the missed events never asked for
/// again. It is the one part of MostroP2P/app#324 that was right.
pub(crate) async fn force_reconnect(client: &Client, url: &str) {
    bounces().lock().unwrap_or_else(|e| e.into_inner()).insert(url.to_string(), Instant::now());
    if let Err(e) = client.disconnect_relay(url).await {
        log::warn!(
            "[relay] liveness probe: disconnect of {} failed: {e}",
            display_relay(url)
        );
    }
    crate::rt::time::sleep(RECONNECT_GRACE).await;
    if let Err(e) = client.connect_relay(url).await {
        log::warn!(
            "[relay] liveness probe: reconnect of {} not started: {e}",
            display_relay(url)
        );
    }
}

/// When each relay was last bounced, by [`force_reconnect`].
fn bounces() -> &'static Mutex<HashMap<String, Instant>> {
    static BOUNCES: OnceLock<Mutex<HashMap<String, Instant>>> = OnceLock::new();
    BOUNCES.get_or_init(Mutex::default)
}

/// Whether `url` was bounced at or after `since`.
fn bounced_since(url: &str, since: Instant) -> bool {
    bounces()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .get(url)
        .is_some_and(|at| *at >= since)
}

/// [`force_reconnect`] for a relay whose probe, sent at `asked`, went
/// unanswered — unless the relay was bounced since. Returns whether it
/// bounced.
///
/// Two things probe: the liveness monitor, with a long deadline, and the
/// resume, with a short one. Both may be asking the same dead socket; the
/// first to give up reconnects the relay, and the other's question, which
/// left on the old socket, then says nothing about the new one. Bouncing
/// again would cut a healthy connection under whatever is being sent.
pub(crate) async fn reconnect_unanswered(client: &Client, url: &str, asked: Instant) -> bool {
    if bounced_since(url, asked) {
        log::info!(
            "[relay] {} was reconnected while it was asked; left alone",
            display_relay(url)
        );
        return false;
    }
    force_reconnect(client, url).await;
    true
}

/// How long a relay marked `Connected` has to answer when the app resumes.
/// Shorter than [`PROBE_TIMEOUT`]: here a wrong "dead" costs one reconnect of
/// a relay that was only slow, and a long wait costs the solver stale lists.
const RESUME_PROBE_TIMEOUT: Duration = Duration::from_secs(3);

/// Reconnect now every relay that is `Disconnected`, and return how many
/// there were.
///
/// For the resume path. While the app is in the background the OS cuts every
/// socket, and each relay's connection task then sleeps its retry interval
/// (10 s, growing to 60 s after repeated failures) before it tries again.
/// `Client::connect` cannot shorten that: it only starts relays that have no
/// connection task. Bouncing the relay ([`force_reconnect`]) replaces the
/// sleeping task with one that connects now; relays connected or already
/// connecting are left alone. All at once: each bounce waits its own grace,
/// and one slow relay must not hold the others.
pub(crate) async fn reconnect_disconnected_now(client: &Client) -> usize {
    let relays = client.relays().await;
    let bounced = futures_util::future::join_all(relays.iter().map(|(url, relay)| async move {
        // Read here, right before the bounce, not from a list made earlier:
        // a relay whose retry woke meanwhile is connecting and is left to it.
        if relay.status() != RelayStatus::Disconnected {
            return false;
        }
        force_reconnect(client, url.as_str()).await;
        true
    }))
    .await;
    bounced.into_iter().filter(|bounced| *bounced).count()
}

/// Ask every relay that is `Connected` whether it still answers, reconnect
/// now those that do not, and return how many there were.
///
/// For the resume path too. A socket the network dropped without a word (a
/// NAT that forgot it, Wi-Fi left for mobile data) is still `Connected` to
/// the SDK when the app returns, so [`reconnect_disconnected_now`] passes it
/// over, and nothing arrives through it until the liveness probe's next
/// round. All at once, each relay with its own deadline.
pub(crate) async fn reconnect_unresponsive_now(client: &Client) -> usize {
    reconnect_unresponsive_within(client, RESUME_PROBE_TIMEOUT).await
}

async fn reconnect_unresponsive_within(client: &Client, limit: Duration) -> usize {
    let relays = client.relays().await;
    let bounced = futures_util::future::join_all(relays.iter().map(|(url, relay)| async move {
        if relay.status() != RelayStatus::Connected {
            return false;
        }
        let asked = Instant::now();
        let answered = probe_within(relay, limit).await;
        // Using the socket may be what shows it dead, and the relay is then
        // `Disconnected`, asleep in its retry. The probe does not say so:
        // measured, a fetch whose relay drops under it ends `Ok` and empty,
        // which reads as an answer. And [`reconnect_disconnected_now`],
        // which runs beside this, saw the relay `Connected` and passed it
        // over. So the status decides, after the probe: still connected and
        // answered is healthy; connected and silent, or disconnected, is
        // reconnected now; already connecting again is left to it.
        match relay.status() {
            RelayStatus::Connected if answered => return false,
            RelayStatus::Connected | RelayStatus::Disconnected => {}
            _ => return false,
        }
        log::info!(
            "[relay] resume: {} answers nothing, reconnecting",
            display_relay(url.as_str())
        );
        reconnect_unanswered(client, url.as_str(), asked).await
    }))
    .await;
    bounced.into_iter().filter(|bounced| *bounced).count()
}

#[cfg(all(test, not(target_arch = "wasm32")))]
pub(crate) mod tests {
    use super::*;
    use nostr_sdk::prelude::MockRelay;

    /// What the proxy does with the first connection it gets, half a second
    /// after it is made. Later connections are passed on untouched.
    #[derive(Clone, Copy)]
    enum First {
        /// Cut, as the OS cuts a background app's sockets.
        Dropped,
        /// Kept open and passed on no more, as a socket the network forgot.
        Silenced,
        /// Silenced, and cut half a second later: a socket that shows itself
        /// dead only when it is used.
        SilencedThenDropped,
    }

    /// A relay whose first connection is cut half a second after it is made.
    pub(crate) async fn relay_that_drops_the_first_connection() -> String {
        proxied_relay(First::Dropped).await
    }

    /// A relay whose first connection stays open and goes silent half a
    /// second after it is made.
    pub(crate) async fn relay_that_silences_the_first_connection() -> String {
        proxied_relay(First::Silenced).await
    }

    /// A proxy in front of a mock relay, which lives as long as the proxy.
    async fn proxied_relay(first: First) -> String {
        let relay = MockRelay::run().await.expect("mock relay");
        let upstream = relay
            .url()
            .await
            .to_string()
            .trim_start_matches("ws://")
            .trim_end_matches('/')
            .to_string();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        tokio::spawn(async move {
            let _relay = relay;
            let mut is_first = true;
            while let Ok((mut inbound, _)) = listener.accept().await {
                let fate = std::mem::replace(&mut is_first, false).then_some(first);
                let upstream = upstream.clone();
                tokio::spawn(async move {
                    let Ok(mut outbound) = tokio::net::TcpStream::connect(&upstream).await else {
                        return;
                    };
                    let copy = tokio::io::copy_bidirectional(&mut inbound, &mut outbound);
                    match fate {
                        None => {
                            let _ = copy.await;
                        }
                        Some(fate) => {
                            let _ = tokio::time::timeout(Duration::from_millis(500), copy).await;
                            match fate {
                                First::Dropped => {}
                                // Both sockets stay open; nothing crosses.
                                First::Silenced => std::future::pending::<()>().await,
                                First::SilencedThenDropped => {
                                    tokio::time::sleep(Duration::from_millis(500)).await;
                                }
                            }
                        }
                    }
                });
            }
        });
        url
    }

    /// A client whose only relay was connected and then dropped.
    pub(crate) async fn dropped_relay(url: &str) -> Client {
        let client = Client::new();
        client.add_relay(url).await.expect("add relay");
        client
            .try_connect_relay(url, Duration::from_secs(5))
            .await
            .expect("connect");
        let relay = client
            .relay(url)
            .await
            .expect("relay")
            .expect("known relay");
        for _ in 0..50 {
            if relay.status() == RelayStatus::Disconnected {
                return client;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        panic!("the relay never dropped: {}", relay.status());
    }

    async fn connected_within(client: &Client, url: &str, limit: Duration) -> bool {
        let relay = client
            .relay(url)
            .await
            .expect("relay")
            .expect("known relay");
        let deadline = tokio::time::Instant::now() + limit;
        while tokio::time::Instant::now() < deadline {
            if relay.status() == RelayStatus::Connected {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        false
    }

    /// Pins the SDK behaviour the nudge works around: `Client::connect` does
    /// nothing for a relay whose connection task is asleep in its retry
    /// interval (10 s and up), which is every relay the OS cut while the app
    /// was in the background.
    #[tokio::test]
    async fn connect_does_not_wake_a_relay_asleep_in_its_retry() {
        // Arrange
        let url = relay_that_drops_the_first_connection().await;
        let client = dropped_relay(&url).await;

        // Act
        client.connect().await;

        // Assert
        assert!(!connected_within(&client, &url, Duration::from_secs(3)).await);
    }

    #[tokio::test]
    async fn a_dropped_relay_reconnects_at_once_on_resume() {
        // Arrange
        let url = relay_that_drops_the_first_connection().await;
        let client = dropped_relay(&url).await;

        // Act
        let woken = reconnect_disconnected_now(&client).await;

        // Assert
        assert_eq!(woken, 1);
        assert!(connected_within(&client, &url, Duration::from_secs(3)).await);
    }

    const NOW: i64 = 1_800_000_000;

    /// The socket the network forgot: the SDK still calls it connected, so
    /// only asking it finds out.
    #[tokio::test]
    async fn a_connected_relay_that_answers_nothing_is_reconnected_on_resume() {
        // Arrange
        let url = relay_that_silences_the_first_connection().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");
        tokio::time::sleep(Duration::from_millis(700)).await;
        let relay = client
            .relay(&url)
            .await
            .expect("relay")
            .expect("known relay");
        assert_eq!(relay.status(), RelayStatus::Connected, "silent, not dropped");
        assert_eq!(reconnect_disconnected_now(&client).await, 0);

        // Act
        let woken = reconnect_unresponsive_within(&client, Duration::from_millis(800)).await;

        // Assert: it is connected again, on a connection that answers.
        assert_eq!(woken, 1);
        assert!(connected_within(&client, &url, Duration::from_secs(3)).await);
        assert!(probe_within(&relay, Duration::from_secs(3)).await);
    }

    /// The socket turns out dead while it is asked: the relay is
    /// `Disconnected` by the time the probe gives up, and the half of the
    /// resume that reconnects such relays has already passed it over.
    #[tokio::test]
    async fn a_relay_that_drops_while_it_is_asked_is_reconnected_on_resume() {
        // Arrange: silent from 500 ms, cut at 1000 ms.
        let url = proxied_relay(First::SilencedThenDropped).await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");
        tokio::time::sleep(Duration::from_millis(650)).await;
        let relay = client.relay(&url).await.expect("relay").expect("known");
        assert_eq!(relay.status(), RelayStatus::Connected, "silent, not cut yet");

        // Act: asked while still connected; cut before the probe gives up.
        let woken = reconnect_unresponsive_within(&client, Duration::from_millis(1200)).await;

        // Assert: back at once, not after the ten seconds of its retry.
        assert_eq!(woken, 1);
        assert!(connected_within(&client, &url, Duration::from_secs(3)).await);
    }

    /// The monitor and the resume asked the same dead socket: whoever gives
    /// up second must not cut the connection the first one restored.
    #[tokio::test]
    async fn a_relay_reconnected_while_it_was_asked_is_not_bounced_again() {
        // Arrange
        let mock = MockRelay::run().await.expect("mock relay");
        let url = mock.url().await.to_string();
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");
        let asked = Instant::now();
        force_reconnect(&client, &url).await;
        assert!(connected_within(&client, &url, Duration::from_secs(3)).await);

        // Act: the slower probe, sent at `asked`, gives up now.
        let bounced = reconnect_unanswered(&client, &url, asked).await;

        // Assert
        assert!(!bounced);
        let relay = client.relay(&url).await.expect("relay").expect("known");
        assert_eq!(relay.status(), RelayStatus::Connected);
        // A probe sent after that bounce is another matter.
        assert!(reconnect_unanswered(&client, &url, Instant::now()).await);
    }

    #[tokio::test]
    async fn a_connected_relay_that_answers_is_left_alone_on_resume() {
        // Arrange
        let mock = MockRelay::run().await.expect("mock relay");
        let url = mock.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");

        // Act
        let woken = reconnect_unresponsive_now(&client).await;

        // Assert
        assert_eq!(woken, 0);
        let relay = client.relay(&url).await.expect("relay").expect("known");
        assert_eq!(relay.status(), RelayStatus::Connected);
    }

    #[tokio::test]
    async fn a_healthy_relay_answers_the_probe() {
        // Arrange: a relay with no traffic at all, which under a silence
        // timer is exactly the false positive that sank the previous attempt.
        let relay = MockRelay::run().await.expect("mock relay");
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");
        let sdk_relay = client
            .relay(&url)
            .await
            .expect("relay")
            .expect("known relay");

        // Act
        let answered = probe_once(&sdk_relay).await;

        // Assert
        assert!(answered, "a silent but healthy relay still answers EOSE");
    }

    /// The probe must not leave its REQ behind: it is a one-shot fetch, and a
    /// subscription that outlived it would consume the per-connection cap the
    /// app already fights over (`req_census`).
    #[tokio::test]
    async fn the_probe_leaves_no_subscription_behind() {
        // Arrange
        let relay = MockRelay::run().await.expect("mock relay");
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");
        let sdk_relay = client
            .relay(&url)
            .await
            .expect("relay")
            .expect("known relay");

        // Act
        assert!(probe_once(&sdk_relay).await);

        // Assert
        assert!(
            sdk_relay.subscriptions().await.is_empty(),
            "the probe's REQ must be closed by the time it returns"
        );
    }

    /// The detection path, which nothing covered until a measurement showed
    /// the first implementation could not detect anything: a relay that
    /// answers nothing must read as unanswered.
    #[tokio::test]
    async fn a_relay_that_answers_nothing_fails_the_probe() {
        // Arrange: connect, then drop the socket so nothing can reply.
        let relay = MockRelay::run().await.expect("mock relay");
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");
        let sdk_relay = client
            .relay(&url)
            .await
            .expect("relay")
            .expect("known relay");
        client.disconnect_relay(&url).await.expect("disconnect");
        tokio::time::sleep(Duration::from_millis(300)).await;

        // Act
        let answered = probe_within(&sdk_relay, Duration::from_millis(800)).await;

        // Assert
        assert!(
            !answered,
            "an unanswered probe must not read as a healthy relay"
        );
    }

    /// The recovery itself: the connection is dropped and restored, which is
    /// the transition `live_subs::repair_relay` re-issues subscriptions on.
    #[tokio::test]
    async fn forcing_a_reconnect_brings_the_relay_back_connected() {
        // Arrange
        let relay = MockRelay::run().await.expect("mock relay");
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");
        let sdk_relay = client
            .relay(&url)
            .await
            .expect("relay")
            .expect("known relay");
        assert_eq!(sdk_relay.status(), RelayStatus::Connected);

        // Act
        force_reconnect(&client, url.as_str()).await;

        // Assert: `connect_relay` only starts the attempt, so the transition
        // the repair listens for lands shortly after, not inline.
        assert!(
            settles_connected(&sdk_relay, Duration::from_secs(5)).await,
            "the bounce must end with the relay connected again, got {:?}",
            sdk_relay.status()
        );
    }

    /// Wait up to `limit` for the relay to report `Connected`.
    async fn settles_connected(relay: &Relay, limit: Duration) -> bool {
        let deadline = tokio::time::Instant::now() + limit;
        while tokio::time::Instant::now() < deadline {
            if relay.status() == RelayStatus::Connected {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        false
    }

    #[test]
    fn a_quiet_connected_relay_is_asked() {
        assert!(should_probe(
            RelayStatus::Connected,
            Some(NOW - 300),
            Some(NOW - 300),
            NOW
        ));
    }

    /// The measurement that sank MostroP2P/app#324: 240 s of silence on a healthy relay.
    /// It is long enough to be asked — and asking is all that happens. Nothing
    /// here concludes the relay is dead, which is why a quiet node no longer
    /// means a reconnect every four minutes.
    #[test]
    fn four_minutes_of_silence_asks_rather_than_concludes() {
        assert!(should_probe(
            RelayStatus::Connected,
            Some(NOW - 240),
            None,
            NOW
        ));
    }

    #[test]
    fn recent_traffic_skips_the_probe() {
        assert!(!should_probe(
            RelayStatus::Connected,
            Some(NOW - 5),
            None,
            NOW
        ));
    }

    #[test]
    fn a_relay_that_is_not_connected_is_never_probed() {
        for status in [
            RelayStatus::Disconnected,
            RelayStatus::Connecting,
            RelayStatus::Terminated,
        ] {
            assert!(
                !should_probe(status, None, None, NOW),
                "{status:?} is the SDK's own reconnect to handle"
            );
        }
    }

    /// Without this the timeout path would re-probe on every tick of a relay
    /// that stays silent — the 30-second reconnect loop CodeRabbit found in
    /// MostroP2P/app#324, one layer up.
    #[test]
    fn a_relay_asked_recently_is_not_asked_again() {
        assert!(!should_probe(
            RelayStatus::Connected,
            Some(NOW - 600),
            Some(NOW - 10),
            NOW
        ));
    }

    #[test]
    fn a_relay_that_never_delivered_anything_is_asked() {
        assert!(should_probe(RelayStatus::Connected, None, None, NOW));
    }

    #[test]
    fn the_probe_filter_can_match_nothing_and_is_not_a_zero_limit() {
        let filter = probe_filter();
        assert_eq!(
            filter.ids.as_ref().map(|ids| ids.len()),
            Some(1),
            "the probe asks for one impossible id"
        );
        assert!(
            filter.limit.is_none(),
            "limit(0) is unanswered by nostr-rs-relay — see probe_filter"
        );
    }

    #[test]
    fn liveness_is_recorded_per_relay() {
        let mut liveness = RelayLiveness::default();
        liveness.record_traffic("wss://a", NOW);
        liveness.record_traffic("wss://b", NOW - 600);

        // One relay's traffic must not vouch for the other's socket.
        assert!(!should_probe(
            RelayStatus::Connected,
            liveness.last_seen("wss://a"),
            None,
            NOW
        ));
        assert!(should_probe(
            RelayStatus::Connected,
            liveness.last_seen("wss://b"),
            None,
            NOW
        ));
    }

    #[test]
    fn forgetting_a_relay_drops_both_stamps() {
        let mut liveness = RelayLiveness::default();
        liveness.record_traffic("wss://a", NOW);
        liveness.record_probe("wss://a", NOW);

        liveness.forget("wss://a");

        assert_eq!(liveness.last_seen("wss://a"), None);
        assert_eq!(liveness.last_probe("wss://a"), None);
    }
}
