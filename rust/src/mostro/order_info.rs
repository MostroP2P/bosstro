//! `AdminOrderInfo`: asking the node for the real state of one of its orders,
//! and reading its answer (issue #51; mostrod's `admin_order_info.rs`).
//!
//! **The request** travels in the `order` wrapper with the order id in `id`
//! and no payload: mostrod drops, unanswered, one that carries a payload.
//! Same transport, router and proof of work as a take. The request is
//! published as every one is (`nostr::publish`: sent when the first relay
//! takes it), and the answer is shown as soon as it arrives, even before any
//! relay acknowledged the request (`replies::answer_or_send`).
//!
//! **Read only.** Nothing is stored and no dispute row changes: the answer is
//! a snapshot of that moment, it carries the parties' trade pubkeys and the
//! amounts, and the database is not encrypted (A4). So, unlike a take or a
//! resolution, a lookup is never *busy*: it does not wait for a request of a
//! dispute, and none waits for it. It is also idempotent, so the solver may
//! ask again; a lookup that got no answer in time is forgotten rather than
//! kept for a late one.
//!
//! **Answers** (mostrod checks the key before it looks the order up, so a
//! stranger cannot probe which orders exist):
//!
//! | Answer | Outcome | Effect |
//! |---|---|---|
//! | `AdminOrderInfo` with an `order_info` of that order | `Found` | solver: yes |
//! | `CantDo(NotFound)` | `NotFound` | solver: yes (the key was accepted) |
//! | `CantDo(InvalidPubkey)` | `NotSolver` | solver: no |
//! | another `CantDo`, anything else | `Refused` | none |
//! | nothing in time | `NoAnswer` | none |
//!
//! Unlike a take's, `InvalidPubkey` here is not ambiguous: the admin key and
//! every registered solver, `read` or `read-write`, may ask about any order.
//! An answer says nothing about the permission, which is left as it was.
//!
//! **No answer** also reads a node that does not know the action: a mostrod
//! older than the one that added it answers nothing.
//!
//! **Timings.** Each step logs how long after the lookup began it ended
//! (`[order-info] +120 ms: …`): the subscription, the node's PoW, the request
//! built, the answer read off the relay, and the answer handed to the caller;
//! and, when no answer came before it, a relay taking the request. They tell
//! where a slow lookup spends its time. Only times are logged, never the
//! order nor its id.

use mostro_core::error::CantDoReason;
use mostro_core::message::{Action, Message, Payload};
use mostro_core::order_info::OrderInfo;
use nostr_sdk::prelude::*;

use super::replies::{self, Purpose, Reply, Request};
use super::take::{new_request_id, reason_marker, take_pow_on, wrap_mined, ANSWER_WAIT};
use crate::api::order_info::OrderLookupError;
use crate::api::take::{SolverStatus, TakeError};
use crate::nostr::publish::{publish, Published};
use crate::rt::time::Instant;

/// What the node said about one lookup.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Lookup {
    /// The order as the node sees it now.
    Found(Box<OrderInfo>),
    /// The node has no order with that id.
    NotFound,
    /// This key is neither the node's admin nor one of its solvers.
    NotSolver,
    /// Refused for another reason (the wire's marker, when it gave one), or
    /// answered with something that is not about that order.
    Refused(Option<String>),
    /// Nothing in time: the request or the answer was lost, or the node does
    /// not know the action.
    NoAnswer,
}

/// The request: the `order` wrapper, the order's id, no payload.
pub(crate) fn request_message(order_id: uuid::Uuid, request_id: u64) -> Message {
    Message::new_order(
        Some(order_id),
        Some(request_id),
        None,
        Action::AdminOrderInfo,
        None,
    )
}

/// An order id as the solver gave it: a UUID in the hyphenated form Mostro
/// writes, with any space around it dropped. The other spellings of a UUID
/// (no hyphens, braces, `urn:uuid:`) are not ids here, so an order has one
/// spelling and the screen can tell the same order asked about again.
pub(crate) fn parse_order_id(text: &str) -> Result<uuid::Uuid, OrderLookupError> {
    let text = text.trim();
    if text.len() != uuid::fmt::Hyphenated::LENGTH {
        return Err(OrderLookupError::InvalidOrderId);
    }
    uuid::Uuid::parse_str(text).map_err(|_| OrderLookupError::InvalidOrderId)
}

/// Read `message` as the answer to a lookup of `order_id`. A snapshot counts
/// only in the `order` wrapper, when both the message and the snapshot name
/// that order.
pub(crate) fn read_answer(order_id: &str, message: &Message) -> Lookup {
    let kind = message.get_inner_message_kind();
    let about_order = kind.id.is_some_and(|id| id.to_string() == order_id);
    match (&kind.action, &kind.payload) {
        (Action::AdminOrderInfo, Some(Payload::OrderInfo(info)))
            if matches!(message, Message::Order(_))
                && about_order
                && info.id.to_string() == order_id =>
        {
            Lookup::Found(Box::new(info.clone()))
        }
        (Action::CantDo, Some(Payload::CantDo(Some(CantDoReason::NotFound)))) => Lookup::NotFound,
        (Action::CantDo, Some(Payload::CantDo(Some(CantDoReason::InvalidPubkey)))) => {
            Lookup::NotSolver
        }
        (Action::CantDo, Some(Payload::CantDo(Some(reason)))) => {
            Lookup::Refused(Some(reason_marker(reason)))
        }
        _ => Lookup::Refused(None),
    }
}

/// Apply the node's answer to `request`, a lookup of `order_id`: what it says
/// about this key on the node, and the result the caller sees. Nothing of the
/// order is stored, and its content is never logged.
pub(crate) async fn apply(
    request: &Request,
    order_id: &str,
    started: Instant,
    message: &Message,
) -> Lookup {
    // Before anything is stored: when the answer came off the relay.
    let arrived = started.elapsed().as_millis();
    let lookup = read_answer(order_id, message);
    match &lookup {
        // The node looked the order up: it took the key for a solver's.
        Lookup::Found(_) | Lookup::NotFound => {
            super::standing::set_status(&request.node, &request.solver, SolverStatus::Yes).await;
        }
        Lookup::NotSolver => {
            super::standing::set_status(&request.node, &request.solver, SolverStatus::No).await;
        }
        Lookup::Refused(_) | Lookup::NoAnswer => {}
    }
    log::info!(
        "[order-info] +{arrived} ms: answer read off the relay: {}",
        match &lookup {
            Lookup::Found(_) => "found",
            Lookup::NotFound => "not found",
            Lookup::NotSolver => "not a solver",
            Lookup::Refused(_) => "refused",
            Lookup::NoAnswer => "no answer",
        }
    );
    lookup
}

/// Ask the active node for the state of `order_id` and wait for the answer
/// (`api::order_info::lookup_order`): the node asked, the order as a UUID,
/// and what the node said.
pub(crate) async fn lookup(
    order_id: &str,
) -> Result<(String, uuid::Uuid, Lookup), OrderLookupError> {
    let order_id = parse_order_id(order_id)?;
    let started = Instant::now();
    let keys = crate::solver_slot::SOLVER_SLOT
        .keys()
        .await
        .ok_or(OrderLookupError::NoKey)?;
    let node = crate::config::active_mostro_pubkey().ok_or(OrderLookupError::NoNode)?;
    let pool = crate::api::relays::pool().map_err(|_| OrderLookupError::NoRelays)?;
    let router = replies::router().ok_or(OrderLookupError::NoRelays)?;
    // The answer must have a subscription to land on before the request
    // leaves (a no-op when the router already follows this node and key).
    router
        .retarget(Some(node.clone()), Some(keys.clone()))
        .await;
    log::info!(
        "[order-info] +{} ms: lookup begun, subscription ready",
        started.elapsed().as_millis()
    );
    let lookup = lookup_on(
        &router,
        &pool.client(),
        &keys,
        &node,
        order_id,
        ANSWER_WAIT,
        started,
    )
    .await?;
    Ok((node, order_id, lookup))
}

/// The lookup on explicit parts: the node's PoW first, then the request.
pub(crate) async fn lookup_on(
    router: &replies::Router,
    client: &Client,
    keys: &Keys,
    node: &str,
    order_id: uuid::Uuid,
    wait: std::time::Duration,
    started: Instant,
) -> Result<Lookup, OrderLookupError> {
    // A solver key is inside mostrod's spam gate only while it holds an
    // active dispute, so this pays what a take pays.
    let pow = take_pow_on(client, node).await.map_err(|e| match e {
        TakeError::ProtocolUnsupported => OrderLookupError::ProtocolUnsupported,
        _ => OrderLookupError::NodeInfoUnavailable,
    })?;
    log::info!(
        "[order-info] +{} ms: the node asks for a proof of work of {pow} bits",
        started.elapsed().as_millis()
    );
    send_lookup(router, client, keys, node, order_id, pow, wait, started).await
}

/// The request itself, on explicit parts so tests drive it against a relay.
#[allow(clippy::too_many_arguments)]
pub(crate) async fn send_lookup(
    router: &replies::Router,
    client: &Client,
    keys: &Keys,
    node: &str,
    order_id: uuid::Uuid,
    pow: u8,
    wait: std::time::Duration,
    started: Instant,
) -> Result<Lookup, OrderLookupError> {
    let ms = move || started.elapsed().as_millis();
    let node_key = PublicKey::from_hex(node).map_err(|_| OrderLookupError::NoNode)?;
    let request_id = new_request_id();
    let request = Request {
        node: node.to_string(),
        solver: keys.public_key().to_hex(),
        // About an order, not a dispute.
        dispute_id: String::new(),
        purpose: Purpose::OrderInfo {
            order_id: order_id.to_string(),
            started,
        },
    };
    // A lookup is never busy (`Router::register`), so this cannot fail; if it
    // ever did, nothing was sent.
    let answer = router
        .register(request_id, request)
        .map_err(|_| OrderLookupError::SendFailed)?;
    let message = request_message(order_id, request_id);
    let send = async {
        let event = wrap_mined(keys, &node_key, &message, pow)
            .await
            .map_err(|e| {
                log::warn!("[order-info] request not built: {e}");
                OrderLookupError::SendFailed
            })?;
        log::info!("[order-info] +{} ms: request built and mined", ms());
        match publish(client, &event).await {
            // Not reached when the answer came first.
            Published::Taken => {
                log::info!("[order-info] +{} ms: a relay took the request", ms());
                Ok(())
            }
            // Sent, and no relay confirmed it: it may have left all the
            // same, so the answer is waited for as after any send.
            Published::Unconfirmed => {
                log::warn!("[order-info] no relay confirmed the request");
                Ok(())
            }
            Published::NoRelay => Err(OrderLookupError::NoRelays),
        }
    };

    // The node may answer before any relay acknowledges the request: the
    // answer is shown as soon as it is there, not when the send ends.
    match replies::answer_or_send(send, answer, wait).await {
        Ok(Some(Reply::OrderInfo(lookup))) => {
            log::info!("[order-info] +{} ms: answer handed to the screen", ms());
            Ok(lookup)
        }
        // Nothing in time, or the router dropped the request (the node or
        // the key changed). A late snapshot would be shown to nobody: forget
        // it.
        Ok(_) => {
            log::info!("[order-info] +{} ms: no answer, given up", ms());
            router.forget(request_id);
            Ok(Lookup::NoAnswer)
        }
        Err(e) => {
            router.forget(request_id);
            Err(e)
        }
    }
}

// Native only, as the `mostro::replies` test rig it drives: on wasm that rig
// does not exist, and `scripts/test-web-storage.sh` builds every test module.
#[cfg(all(test, not(target_arch = "wasm32")))]
pub(crate) mod tests {
    use super::*;
    use crate::api::disputes::DisputeStatus;
    use crate::api::resolve::{BondSlash, Resolution};
    use crate::mostro::replies::tests::{answer_with, silent, Rig, Script, WAIT};
    use crate::mostro::take::tests::{DISPUTE, ORDER};
    use mostro_core::order_info::{
        BondInfo, BondKind, BondRole, BondState, HoldInvoiceInfo, HoldInvoiceState,
    };
    use std::sync::{Arc, Mutex};
    use std::time::Duration;

    const OTHER_ORDER: &str = "0d4f6a2b-7c1e-4f3a-8b5d-9e0f1a2b3c4d";

    fn order() -> uuid::Uuid {
        uuid::Uuid::parse_str(ORDER).unwrap()
    }

    /// A snapshot as mostrod builds one, of the order `id`.
    pub(crate) fn snapshot(id: &str) -> OrderInfo {
        OrderInfo {
            id: uuid::Uuid::parse_str(id).unwrap(),
            kind: "sell".into(),
            status: "settled-hold-invoice".into(),
            amount: 100_000,
            fee: 600,
            fiat_code: "EUR".into(),
            fiat_amount: 50,
            payment_method: "SEPA".into(),
            created_at: 1_700_000_000,
            taken_at: Some(1_700_000_100),
            expires_at: 1_700_086_400,
            buyer_trade_pubkey: Some("22".repeat(32)),
            seller_trade_pubkey: Some("11".repeat(32)),
            seller_dispute: true,
            failed_payment: true,
            payment_attempts: 2,
            hold_invoice: Some(HoldInvoiceInfo {
                state: HoldInvoiceState::Settled,
                held_at: Some(1_700_000_200),
            }),
            bonds: vec![BondInfo {
                role: BondRole::Taker,
                amount: 1_000,
                state: BondState::Locked,
                slash_reason: None,
                kind: BondKind::Bond,
                root_order_id: None,
            }],
            ..OrderInfo::default()
        }
    }

    /// The node's reply about `about`, carrying the snapshot of `of`.
    fn found(request_id: u64, about: &str, of: &str) -> Message {
        Message::new_order(
            Some(uuid::Uuid::parse_str(about).unwrap()),
            Some(request_id),
            None,
            Action::AdminOrderInfo,
            Some(Payload::OrderInfo(snapshot(of))),
        )
    }

    fn refused(request_id: u64, reason: Option<CantDoReason>) -> Message {
        Message::cant_do(Some(order()), Some(request_id), Some(Payload::CantDo(reason)))
    }

    async fn ask(rig: &Rig, wait: Duration) -> Result<Lookup, OrderLookupError> {
        send_lookup(
            &rig.router,
            &rig.client,
            &rig.solver,
            &rig.node_hex(),
            order(),
            0,
            wait,
            Instant::now(),
        )
        .await
    }

    // ── The request ──────────────────────────────────────────────────────

    #[test]
    fn the_request_is_the_order_wrapper_with_the_id_and_no_payload() {
        let message = request_message(order(), 7);
        assert!(matches!(message, Message::Order(_)));
        let kind = message.get_inner_message_kind();
        assert_eq!(kind.action, Action::AdminOrderInfo);
        assert_eq!(kind.id, Some(order()));
        assert_eq!(kind.request_id, Some(7));
        // mostrod drops a request that carries one.
        assert!(kind.payload.is_none());
        assert!(message.verify());
        let json = message.as_json().unwrap();
        assert!(json.contains("\"admin-order-info\""), "{json}");
    }

    #[test]
    fn an_order_id_is_a_uuid_with_the_space_around_it_dropped() {
        assert_eq!(parse_order_id(&format!("  {ORDER}\n")), Ok(order()));
        assert_eq!(parse_order_id(""), Err(OrderLookupError::InvalidOrderId));
        assert_eq!(parse_order_id("308e1272"), Err(OrderLookupError::InvalidOrderId));
        assert_eq!(
            parse_order_id(&"a".repeat(64)),
            Err(OrderLookupError::InvalidOrderId)
        );
    }

    #[test]
    fn an_order_id_has_one_spelling() {
        assert_eq!(parse_order_id(&ORDER.to_uppercase()), Ok(order()));
        for other in [
            ORDER.replace('-', ""),
            format!("{{{ORDER}}}"),
            format!("urn:uuid:{ORDER}"),
        ] {
            assert_eq!(
                parse_order_id(&other),
                Err(OrderLookupError::InvalidOrderId),
                "{other}"
            );
        }
    }

    // ── The answers table, row by row ────────────────────────────────────

    #[test]
    fn a_snapshot_of_that_order_is_found() {
        let lookup = read_answer(ORDER, &found(1, ORDER, ORDER));
        assert_eq!(lookup, Lookup::Found(Box::new(snapshot(ORDER))));
    }

    #[test]
    fn a_snapshot_about_another_order_is_not_taken() {
        // The message names another order.
        assert_eq!(
            read_answer(ORDER, &found(1, OTHER_ORDER, OTHER_ORDER)),
            Lookup::Refused(None)
        );
        // The message names this order, the snapshot another.
        assert_eq!(
            read_answer(ORDER, &found(1, ORDER, OTHER_ORDER)),
            Lookup::Refused(None)
        );
    }

    #[test]
    fn a_snapshot_outside_the_order_wrapper_is_not_taken() {
        let message = Message::new_dispute(
            Some(order()),
            Some(1),
            None,
            Action::AdminOrderInfo,
            Some(Payload::OrderInfo(snapshot(ORDER))),
        );
        assert_eq!(read_answer(ORDER, &message), Lookup::Refused(None));
    }

    #[test]
    fn the_refusals_read_as_the_table_says() {
        let read = |reason| read_answer(ORDER, &refused(1, reason));
        assert_eq!(read(Some(CantDoReason::NotFound)), Lookup::NotFound);
        assert_eq!(read(Some(CantDoReason::InvalidPubkey)), Lookup::NotSolver);
        assert_eq!(
            read(Some(CantDoReason::InvalidAction)),
            Lookup::Refused(Some("invalid_action".into()))
        );
        assert_eq!(read(None), Lookup::Refused(None));
    }

    #[test]
    fn another_action_with_the_request_id_is_refused() {
        let message = Message::new_order(
            Some(order()),
            Some(1),
            None,
            Action::AdminSettled,
            None,
        );
        assert_eq!(read_answer(ORDER, &message), Lookup::Refused(None));
    }

    // ── End to end, against a relay and a simulated daemon ───────────────

    #[tokio::test]
    async fn the_daemon_gets_the_request_and_its_snapshot_comes_back() {
        let seen: Arc<Mutex<Vec<Message>>> = Arc::default();
        let log = seen.clone();
        let script: Script = Arc::new(move |rid, message| {
            log.lock().unwrap().push(message.clone());
            vec![found(rid, ORDER, ORDER)]
        });
        let rig = Rig::new("initiated", script).await;

        let lookup = ask(&rig, WAIT).await.unwrap();

        assert_eq!(lookup, Lookup::Found(Box::new(snapshot(ORDER))));
        let seen = seen.lock().unwrap().clone();
        assert_eq!(seen.len(), 1);
        assert!(matches!(seen[0], Message::Order(_)));
        let kind = seen[0].get_inner_message_kind();
        assert_eq!(kind.action, Action::AdminOrderInfo);
        assert_eq!(kind.id, Some(order()));
        assert!(kind.payload.is_none());
        // The node answered a lookup: this key is a solver there.
        assert_eq!(rig.standing().await, SolverStatus::Yes);
        assert_eq!(rig.router.waiting_len(), 0);
    }

    #[tokio::test]
    async fn nothing_of_a_lookup_is_stored() {
        let rig = Rig::new("in-progress", answer_with(|rid| found(rid, ORDER, ORDER))).await;
        let before = rig.row().await;

        ask(&rig, WAIT).await.unwrap();

        // The dispute row is as it was: no take, no status, no order data.
        let after = rig.row().await;
        assert_eq!(after.status, DisputeStatus::InProgress);
        assert_eq!(after.taken, before.taken);
        assert!(after.taken.is_none());
    }

    #[tokio::test]
    async fn an_unknown_order_is_not_found_and_the_key_is_still_a_solver() {
        let rig = Rig::new(
            "initiated",
            answer_with(|rid| refused(rid, Some(CantDoReason::NotFound))),
        )
        .await;

        assert_eq!(ask(&rig, WAIT).await, Ok(Lookup::NotFound));
        assert_eq!(rig.standing().await, SolverStatus::Yes);
    }

    #[tokio::test]
    async fn invalid_pubkey_marks_the_key_no_solver() {
        let rig = Rig::new(
            "initiated",
            answer_with(|rid| refused(rid, Some(CantDoReason::InvalidPubkey))),
        )
        .await;

        assert_eq!(ask(&rig, WAIT).await, Ok(Lookup::NotSolver));
        assert_eq!(rig.standing().await, SolverStatus::No);
    }

    #[tokio::test]
    async fn another_refusal_changes_nothing() {
        let rig = Rig::new(
            "initiated",
            answer_with(|rid| refused(rid, Some(CantDoReason::InvalidAction))),
        )
        .await;

        assert_eq!(
            ask(&rig, WAIT).await,
            Ok(Lookup::Refused(Some("invalid_action".into())))
        );
        assert_eq!(rig.standing().await, SolverStatus::Unknown);
    }

    #[tokio::test]
    async fn a_snapshot_of_another_order_is_refused_end_to_end() {
        let rig = Rig::new(
            "initiated",
            answer_with(|rid| found(rid, OTHER_ORDER, OTHER_ORDER)),
        )
        .await;

        assert_eq!(ask(&rig, WAIT).await, Ok(Lookup::Refused(None)));
        assert_eq!(rig.standing().await, SolverStatus::Unknown);
    }

    #[tokio::test]
    async fn a_silent_node_is_no_answer_and_the_request_is_forgotten() {
        let rig = Rig::new("initiated", silent()).await;

        let lookup = ask(&rig, Duration::from_millis(300)).await;

        assert_eq!(lookup, Ok(Lookup::NoAnswer));
        // Not kept for a late answer: a snapshot nobody waits for is dropped.
        assert_eq!(rig.router.waiting_len(), 0);
        assert_eq!(rig.standing().await, SolverStatus::Unknown);
    }

    #[tokio::test]
    async fn a_request_with_no_relay_connected_is_not_sent_and_not_waited_for() {
        let rig = Rig::new("initiated", silent()).await;
        rig.client.disconnect().await;

        assert_eq!(ask(&rig, WAIT).await, Err(OrderLookupError::NoRelays));
        assert_eq!(rig.router.waiting_len(), 0);
    }

    #[tokio::test]
    async fn a_request_no_relay_confirmed_reads_no_answer() {
        let rig = Rig::new("initiated", silent()).await;
        let _refusing = rig.leave_only_a_refusing_relay().await;

        let lookup = ask(&rig, Duration::from_millis(300)).await;

        assert_eq!(lookup, Ok(Lookup::NoAnswer));
        // A lookup is never kept for a late answer.
        assert_eq!(rig.router.waiting_len(), 0);
    }

    // ── A slow relay ─────────────────────────────────────────────────────

    use crate::mostro::replies::answer_or_send;
    use tokio::sync::oneshot;

    fn found_reply() -> Reply {
        Reply::OrderInfo(Lookup::Found(Box::new(snapshot(ORDER))))
    }

    #[tokio::test]
    async fn the_answer_is_not_kept_behind_a_send_that_has_not_ended() {
        // A relay that never acknowledges: the send would end in ten seconds.
        let send = std::future::pending::<Result<(), OrderLookupError>>();
        let (tx, rx) = oneshot::channel();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(50)).await;
            let _ = tx.send(found_reply());
        });
        let started = std::time::Instant::now();

        let got = answer_or_send(send, rx, WAIT).await;

        assert_eq!(got, Ok(Some(found_reply())));
        assert!(
            started.elapsed() < Duration::from_secs(2),
            "shown when the answer arrived, not when the send ended"
        );
    }

    #[tokio::test]
    async fn an_answer_that_follows_the_send_is_waited_for() {
        let send = async { Ok::<(), OrderLookupError>(()) };
        let (tx, rx) = oneshot::channel();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(50)).await;
            let _ = tx.send(found_reply());
        });

        assert_eq!(
            answer_or_send(send, rx, WAIT).await,
            Ok(Some(found_reply()))
        );
    }

    #[tokio::test]
    async fn a_send_that_failed_before_any_answer_is_an_error_at_once() {
        let send = async { Err::<(), _>(OrderLookupError::SendFailed) };
        // The caller of the answer is alive and silent.
        let (_tx, rx) = oneshot::channel::<Reply>();
        let started = std::time::Instant::now();

        let got = answer_or_send(send, rx, WAIT).await;

        assert_eq!(got, Err(OrderLookupError::SendFailed));
        assert!(started.elapsed() < Duration::from_secs(2), "not waited for");
    }

    #[tokio::test]
    async fn an_answer_that_arrived_wins_over_a_send_that_failed() {
        // Both are ready at once: the answer is already in its channel when
        // the send reports that no relay confirmed the request.
        let (tx, rx) = oneshot::channel();
        tx.send(found_reply()).unwrap();
        let send = async { Err::<(), _>(OrderLookupError::SendFailed) };

        assert_eq!(
            answer_or_send(send, rx, WAIT).await,
            Ok(Some(found_reply()))
        );
    }

    #[tokio::test]
    async fn a_request_that_left_and_got_no_answer_is_none_after_the_wait() {
        let send = async { Ok::<(), OrderLookupError>(()) };
        let (_tx, rx) = oneshot::channel::<Reply>();

        let got = answer_or_send(send, rx, Duration::from_millis(100)).await;

        assert_eq!(got, Ok(None));
    }

    #[tokio::test]
    async fn a_request_the_router_dropped_is_none_whenever_it_happens() {
        // While the send is still waiting for a relay.
        let send = std::future::pending::<Result<(), OrderLookupError>>();
        let (tx, rx) = oneshot::channel::<Reply>();
        drop(tx);
        assert_eq!(answer_or_send(send, rx, WAIT).await, Ok(None));

        // After the send ended.
        let send = async { Ok::<(), OrderLookupError>(()) };
        let (tx, rx) = oneshot::channel::<Reply>();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(50)).await;
            drop(tx);
        });
        assert_eq!(answer_or_send(send, rx, WAIT).await, Ok(None));
    }

    // ── Never busy ───────────────────────────────────────────────────────

    fn lookup_request(rig: &Rig) -> Request {
        Request {
            node: rig.node_hex(),
            solver: rig.solver_hex(),
            dispute_id: String::new(),
            purpose: Purpose::OrderInfo {
                order_id: ORDER.into(),
                started: Instant::now(),
            },
        }
    }

    fn resolve_request(rig: &Rig) -> Request {
        Request {
            node: rig.node_hex(),
            solver: rig.solver_hex(),
            dispute_id: DISPUTE.into(),
            purpose: Purpose::Resolve {
                resolution: Resolution::PayBuyer,
                order_id: ORDER.into(),
                bond: BondSlash::NoSlash,
            },
        }
    }

    #[tokio::test]
    async fn a_lookup_neither_waits_for_a_resolution_nor_makes_one_wait() {
        let rig = Rig::new("in-progress", silent()).await;

        // A resolution is waited for: lookups still go, any number of them.
        let _resolving = rig.router.register(1, resolve_request(&rig)).unwrap();
        let _first = rig.router.register(2, lookup_request(&rig)).unwrap();
        let _second = rig.router.register(3, lookup_request(&rig)).unwrap();
        // And a second resolution of that dispute is still refused.
        assert!(rig.router.register(4, resolve_request(&rig)).is_err());

        // Lookups are waited for: a resolution of another dispute still goes.
        let mut other = resolve_request(&rig);
        other.dispute_id = "1f2e3d4c-5b6a-4978-8695-a4b3c2d1e0f9".into();
        assert!(rig.router.register(5, other).is_ok());
    }

    #[tokio::test]
    async fn a_lookup_alone_does_not_make_a_resolution_busy() {
        let rig = Rig::new("in-progress", silent()).await;

        let _looking = rig.router.register(1, lookup_request(&rig)).unwrap();

        assert!(rig.router.register(2, resolve_request(&rig)).is_ok());
    }

    #[tokio::test]
    async fn a_lookup_is_never_an_unanswered_resolution() {
        let rig = Rig::new("in-progress", silent()).await;

        // Its caller stopped waiting, as a resolution's would after its wait.
        drop(rig.router.register(1, lookup_request(&rig)).unwrap());

        assert_eq!(
            rig.router
                .unanswered_resolution(&rig.node_hex(), &rig.solver_hex(), ""),
            None
        );
        assert_eq!(
            rig.router
                .unanswered_resolution(&rig.node_hex(), &rig.solver_hex(), DISPUTE),
            None
        );
    }
}
