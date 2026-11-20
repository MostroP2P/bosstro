//! The real state of an order of the active node, across the bridge
//! (issue #51): mostrod's `admin-order-info`, a read-only query the node
//! answers for its admin key and for any of its solvers, `read` or
//! `read-write`, about any order, disputed or not.
//!
//! The public order event only says `pending`, `in-progress`, `success` or
//! `canceled`, and a dispute's 38386 carries no order data. This answers with
//! one snapshot: the order as the node's database holds it and, next to it,
//! what its Lightning node reports for the seller's hold invoice and for the
//! payment to the buyer. The two are reported side by side and never merged:
//! the point is to see when they disagree.
//!
//! The types here are Bosstro's own. mostro-core's `OrderInfo` is mapped in
//! this file and nowhere else ([`snapshot_of`]), so a change to it upstream
//! is a change here only.
//!
//! **Nothing is stored.** A snapshot is of the moment it was asked, and it
//! carries the parties' trade pubkeys and the amounts; the database is not
//! encrypted (A4). The reply never carries a preimage, an invoice, a payment
//! hash, a Cashu token or a master (identity) pubkey: `OrderInfo` has no
//! field for any of them.
//!
//! Rust does not translate: every status, state and refusal is a marker, and
//! Dart words it. An `Unknown` marker is a value this build does not know
//! (a newer node); `Unavailable` is another thing, a Lightning node that
//! could not be asked.

use std::str::FromStr;

use mostro_core::order::{Kind, Status};
use mostro_core::order_info as core;

use crate::mostro::order_info::Lookup;

/// Whether the order buys or sells sats.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrderKind {
    Buy,
    Sell,
    /// A kind this build does not know; [`OrderSnapshot::kind_raw`] has it.
    Unknown,
}

/// The order's status in the node's database: the real one, not the four the
/// public order event shows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrderStatus {
    Pending,
    WaitingMakerBond,
    WaitingTakerBond,
    WaitingBuyerInvoice,
    WaitingPayment,
    InProgress,
    Active,
    FiatSent,
    SettledHoldInvoice,
    Success,
    Dispute,
    Canceled,
    CooperativelyCanceled,
    CanceledByAdmin,
    SettledByAdmin,
    CompletedByAdmin,
    Expired,
    /// A status this build does not know; [`OrderSnapshot::status_raw`] has
    /// it.
    Unknown,
}

/// The seller's hold invoice, as the node's Lightning node reports it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HoldInvoiceState {
    /// Created, not paid yet.
    Open,
    /// Paid and held: the sats are locked.
    Accepted,
    /// Settled: the node took the sats.
    Settled,
    /// Canceled: the sats went back to the seller.
    Canceled,
    /// The Lightning node has no record of it.
    NotFound,
    /// The Lightning node could not be asked (an error, or no answer in
    /// time).
    Unavailable,
    /// A state this build does not know.
    Unknown,
}

/// The payment to the buyer, as the node's Lightning node reports it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PayoutState {
    InFlight,
    Succeeded,
    Failed,
    /// The Lightning node has no record of it (the marker is stored before
    /// the payment is sent).
    NotFound,
    /// The Lightning node could not be asked.
    Unavailable,
    /// A state this build does not know.
    Unknown,
}

/// Why a payment to the buyer failed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PayoutFailureReason {
    Timeout,
    NoRoute,
    Error,
    IncorrectPaymentDetails,
    InsufficientBalance,
    Canceled,
    /// A reason this build does not know.
    Unknown,
}

/// Who posted a bond.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BondRole {
    Maker,
    Taker,
    Unknown,
}

/// Where a bond stands.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BondState {
    /// Asked for, not posted yet.
    Requested,
    /// Posted and held.
    Locked,
    /// Given back.
    Released,
    /// Slashed; its payout to the other party is still owed.
    PendingPayout,
    /// Slashed and paid out.
    Slashed,
    /// Slashed, and the other party never claimed it.
    Forfeited,
    /// Its payout failed.
    Failed,
    Unknown,
}

/// Why a bond was slashed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BondSlashReason {
    LostDispute,
    Timeout,
    Unknown,
}

/// What a bond row is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BondKind {
    /// The bond itself.
    Bond,
    /// On a range order: a maker slash recorded against one slice.
    SliceSlash,
    /// On a range order: the unslashed rest, returned to the maker.
    MakerRefund,
    Unknown,
}

/// The seller's hold invoice.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HoldInvoice {
    /// What the Lightning node says now.
    pub state: HoldInvoiceState,
    /// When the database says the sats were locked (Unix seconds).
    pub held_at: Option<i64>,
}

/// The Cashu escrow of an order on a Cashu node. Never the token.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CashuEscrow {
    pub mint_url: String,
    /// When it was locked (Unix seconds).
    pub locked_at: Option<i64>,
}

/// The payment to the buyer. Present only while one is in flight: the node
/// clears its marker when the payment ends, so after a failure this is absent
/// and [`OrderSnapshot::failed_payment`] / `payment_attempts` tell.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Payout {
    pub state: PayoutState,
    pub failure_reason: Option<PayoutFailureReason>,
    /// When it reached its final state (Unix seconds).
    pub resolved_at: Option<i64>,
}

/// One bond row of the order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrderBond {
    pub role: BondRole,
    /// Sats.
    pub amount: i64,
    pub state: BondState,
    pub slash_reason: Option<BondSlashReason>,
    pub kind: BondKind,
    /// On a slice of a range order, the root order whose maker bond this is.
    pub root_order_id: Option<String>,
}

/// One order as the node saw it when it was asked.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrderSnapshot {
    pub order_id: String,
    pub kind: OrderKind,
    /// The kind as the node wrote it.
    pub kind_raw: String,
    pub status: OrderStatus,
    /// The status as the node wrote it (`settled-hold-invoice`).
    pub status_raw: String,
    /// Sats.
    pub amount: i64,
    /// The node's fee, sats.
    pub fee: i64,
    /// What routing the payment to the buyer cost, sats.
    pub routing_fee: i64,
    pub fiat_code: String,
    pub fiat_amount: i64,
    /// The fiat range of a range order.
    pub min_amount: Option<i64>,
    pub max_amount: Option<i64>,
    pub payment_method: String,
    /// Percent over the market price.
    pub premium: i64,
    /// The range order this one is a slice of.
    pub range_parent_id: Option<String>,
    /// Unix seconds, as the times below. `None` is "not yet", or a time the
    /// node does not keep.
    pub created_at: Option<i64>,
    pub taken_at: Option<i64>,
    pub expires_at: Option<i64>,
    /// The parties' trade keys (hex), never their identity keys.
    pub buyer_trade_pubkey: Option<String>,
    pub seller_trade_pubkey: Option<String>,
    /// Who opened a dispute.
    pub buyer_dispute: bool,
    pub seller_dispute: bool,
    /// Who asked for a cooperative cancel.
    pub buyer_cooperative_cancel: bool,
    pub seller_cooperative_cancel: bool,
    /// Whether the last payment to the buyer failed.
    pub failed_payment: bool,
    pub payment_attempts: i64,
    /// When the database says the hold invoice was settled.
    pub hold_settled_at: Option<i64>,
    /// `None`: the order has no hold invoice.
    pub hold_invoice: Option<HoldInvoice>,
    /// `None`: not a Cashu order.
    pub cashu_escrow: Option<CashuEscrow>,
    /// `None`: no payment to the buyer is in flight.
    pub payout: Option<Payout>,
    pub bonds: Vec<OrderBond>,
}

/// How a lookup ended.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrderLookupOutcome {
    /// [`OrderLookupResult::order`] has the snapshot.
    Found,
    /// The node has no order with that id.
    NotFound,
    /// `CantDo(InvalidPubkey)`: this key is neither the node's admin nor one
    /// of its solvers. The node is marked "solver: no".
    NotSolver,
    /// Another refusal, or an answer that is not about that order; its
    /// reason, when the node gave one, is in [`OrderLookupResult::reason`].
    Refused,
    /// The node did not answer in time: the request or the answer was lost,
    /// or the node does not know the action yet (an older mostrod answers
    /// nothing). Asking again is safe.
    NoAnswer,
}

/// The answer to one lookup.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrderLookupResult {
    pub mostro_pubkey: String,
    /// The order asked about, as a canonical UUID.
    pub order_id: String,
    pub outcome: OrderLookupOutcome,
    /// With [`OrderLookupOutcome::Found`].
    pub order: Option<OrderSnapshot>,
    /// With [`OrderLookupOutcome::Refused`]: mostro-core's `CantDoReason` as
    /// the wire writes it, or `None` when the node gave none.
    pub reason: Option<String>,
    /// When the answer was read (Unix seconds, this device's clock).
    pub asked_at: i64,
}

/// Why a lookup was not sent. Dart maps each marker to its own copy.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrderLookupError {
    /// No solver key is loaded.
    NoKey,
    /// No node is chosen.
    NoNode,
    /// The relay pool is not running, or no relay is connected: nothing was
    /// sent.
    NoRelays,
    /// The text is not an order id (a UUID).
    InvalidOrderId,
    /// The node says it speaks another protocol than v2 (its kind 38385).
    ProtocolUnsupported,
    /// The node's kind 38385 was never read and could not be read now, so the
    /// proof of work it asks for is not known; the request is not sent.
    NodeInfoUnavailable,
    /// The request could not be built: nothing was sent. (A request that was
    /// sent and that no relay confirmed is not an error: it may have left,
    /// and reads as no answer.)
    SendFailed,
}

/// Whether `text` is an order id: a UUID, with any space around it. The
/// screen offers the lookup only then, so no proof of work is spent on a
/// request the node would refuse.
#[flutter_rust_bridge::frb(sync)]
pub fn is_order_id(text: String) -> bool {
    crate::mostro::order_info::parse_order_id(&text).is_ok()
}

/// Ask the active node for the state of `order_id` (`admin-order-info`) and
/// wait for the answer (15 s). Read only: nothing is stored, and no dispute
/// changes. What the answer says about this key (a solver here or not) is
/// kept before it returns. Safe to ask again.
pub async fn lookup_order(order_id: String) -> Result<OrderLookupResult, OrderLookupError> {
    let (node, order, lookup) = crate::mostro::order_info::lookup(&order_id).await?;
    Ok(result_of(node, order, lookup, crate::rt::unix_now()))
}

/// The bridge's result of `lookup` about `order_id` on `node`.
fn result_of(node: String, order_id: uuid::Uuid, lookup: Lookup, now: i64) -> OrderLookupResult {
    let (outcome, order, reason) = match lookup {
        Lookup::Found(info) => (OrderLookupOutcome::Found, Some(snapshot_of(&info)), None),
        Lookup::NotFound => (OrderLookupOutcome::NotFound, None, None),
        Lookup::NotSolver => (OrderLookupOutcome::NotSolver, None, None),
        Lookup::Refused(reason) => (OrderLookupOutcome::Refused, None, reason),
        Lookup::NoAnswer => (OrderLookupOutcome::NoAnswer, None, None),
    };
    OrderLookupResult {
        mostro_pubkey: node,
        order_id: order_id.to_string(),
        outcome,
        order,
        reason,
        asked_at: now,
    }
}

/// A time the node may store as `0` for "none".
fn time(seconds: i64) -> Option<i64> {
    (seconds > 0).then_some(seconds)
}

/// mostro-core's `OrderInfo` as the bridge carries it: the only place that
/// reads its fields.
fn snapshot_of(info: &core::OrderInfo) -> OrderSnapshot {
    OrderSnapshot {
        order_id: info.id.to_string(),
        kind: kind_of(&info.kind),
        kind_raw: info.kind.clone(),
        status: status_of(&info.status),
        status_raw: info.status.clone(),
        amount: info.amount,
        fee: info.fee,
        routing_fee: info.routing_fee,
        fiat_code: info.fiat_code.clone(),
        fiat_amount: info.fiat_amount,
        min_amount: info.min_amount,
        max_amount: info.max_amount,
        payment_method: info.payment_method.clone(),
        premium: info.premium,
        range_parent_id: info.range_parent_id.map(|id| id.to_string()),
        created_at: time(info.created_at),
        taken_at: info.taken_at.and_then(time),
        expires_at: time(info.expires_at),
        buyer_trade_pubkey: info.buyer_trade_pubkey.clone(),
        seller_trade_pubkey: info.seller_trade_pubkey.clone(),
        buyer_dispute: info.buyer_dispute,
        seller_dispute: info.seller_dispute,
        buyer_cooperative_cancel: info.buyer_cooperativecancel,
        seller_cooperative_cancel: info.seller_cooperativecancel,
        failed_payment: info.failed_payment,
        payment_attempts: info.payment_attempts,
        hold_settled_at: info.hold_settled_at.and_then(time),
        hold_invoice: info.hold_invoice.as_ref().map(|h| HoldInvoice {
            state: match h.state {
                core::HoldInvoiceState::Open => HoldInvoiceState::Open,
                core::HoldInvoiceState::Accepted => HoldInvoiceState::Accepted,
                core::HoldInvoiceState::Settled => HoldInvoiceState::Settled,
                core::HoldInvoiceState::Canceled => HoldInvoiceState::Canceled,
                core::HoldInvoiceState::NotFound => HoldInvoiceState::NotFound,
                core::HoldInvoiceState::Unavailable => HoldInvoiceState::Unavailable,
                core::HoldInvoiceState::Unknown => HoldInvoiceState::Unknown,
            },
            held_at: h.held_at.and_then(time),
        }),
        cashu_escrow: info.cashu_escrow.as_ref().map(|c| CashuEscrow {
            mint_url: c.mint_url.clone(),
            locked_at: c.locked_at.and_then(time),
        }),
        payout: info.payout.as_ref().map(|p| Payout {
            state: match p.state {
                core::PayoutState::InFlight => PayoutState::InFlight,
                core::PayoutState::Succeeded => PayoutState::Succeeded,
                core::PayoutState::Failed => PayoutState::Failed,
                core::PayoutState::NotFound => PayoutState::NotFound,
                core::PayoutState::Unavailable => PayoutState::Unavailable,
                core::PayoutState::Unknown => PayoutState::Unknown,
            },
            failure_reason: p.failure_reason.map(|r| match r {
                core::PayoutFailureReason::Timeout => PayoutFailureReason::Timeout,
                core::PayoutFailureReason::NoRoute => PayoutFailureReason::NoRoute,
                core::PayoutFailureReason::Error => PayoutFailureReason::Error,
                core::PayoutFailureReason::IncorrectPaymentDetails => {
                    PayoutFailureReason::IncorrectPaymentDetails
                }
                core::PayoutFailureReason::InsufficientBalance => {
                    PayoutFailureReason::InsufficientBalance
                }
                core::PayoutFailureReason::Canceled => PayoutFailureReason::Canceled,
                core::PayoutFailureReason::Unknown => PayoutFailureReason::Unknown,
            }),
            resolved_at: p.resolved_at.and_then(time),
        }),
        bonds: info.bonds.iter().map(bond_of).collect(),
    }
}

fn bond_of(bond: &core::BondInfo) -> OrderBond {
    OrderBond {
        role: match bond.role {
            core::BondRole::Maker => BondRole::Maker,
            core::BondRole::Taker => BondRole::Taker,
            core::BondRole::Unknown => BondRole::Unknown,
        },
        amount: bond.amount,
        state: match bond.state {
            core::BondState::Requested => BondState::Requested,
            core::BondState::Locked => BondState::Locked,
            core::BondState::Released => BondState::Released,
            core::BondState::PendingPayout => BondState::PendingPayout,
            core::BondState::Slashed => BondState::Slashed,
            core::BondState::Forfeited => BondState::Forfeited,
            core::BondState::Failed => BondState::Failed,
            core::BondState::Unknown => BondState::Unknown,
        },
        slash_reason: bond.slash_reason.map(|r| match r {
            core::BondSlashReason::LostDispute => BondSlashReason::LostDispute,
            core::BondSlashReason::Timeout => BondSlashReason::Timeout,
            core::BondSlashReason::Unknown => BondSlashReason::Unknown,
        }),
        kind: match bond.kind {
            core::BondKind::Bond => BondKind::Bond,
            core::BondKind::SliceSlash => BondKind::SliceSlash,
            core::BondKind::MakerRefund => BondKind::MakerRefund,
            core::BondKind::Unknown => BondKind::Unknown,
        },
        root_order_id: bond.root_order_id.map(|id| id.to_string()),
    }
}

fn kind_of(raw: &str) -> OrderKind {
    match Kind::from_str(raw) {
        Ok(Kind::Buy) => OrderKind::Buy,
        Ok(Kind::Sell) => OrderKind::Sell,
        Err(_) => OrderKind::Unknown,
    }
}

/// The status the node wrote, read with mostro-core's own names: a status
/// added to it does not compile here until it has a marker.
fn status_of(raw: &str) -> OrderStatus {
    match Status::from_str(raw) {
        Ok(Status::Pending) => OrderStatus::Pending,
        Ok(Status::WaitingMakerBond) => OrderStatus::WaitingMakerBond,
        Ok(Status::WaitingTakerBond) => OrderStatus::WaitingTakerBond,
        Ok(Status::WaitingBuyerInvoice) => OrderStatus::WaitingBuyerInvoice,
        Ok(Status::WaitingPayment) => OrderStatus::WaitingPayment,
        Ok(Status::InProgress) => OrderStatus::InProgress,
        Ok(Status::Active) => OrderStatus::Active,
        Ok(Status::FiatSent) => OrderStatus::FiatSent,
        Ok(Status::SettledHoldInvoice) => OrderStatus::SettledHoldInvoice,
        Ok(Status::Success) => OrderStatus::Success,
        Ok(Status::Dispute) => OrderStatus::Dispute,
        Ok(Status::Canceled) => OrderStatus::Canceled,
        Ok(Status::CooperativelyCanceled) => OrderStatus::CooperativelyCanceled,
        Ok(Status::CanceledByAdmin) => OrderStatus::CanceledByAdmin,
        Ok(Status::SettledByAdmin) => OrderStatus::SettledByAdmin,
        Ok(Status::CompletedByAdmin) => OrderStatus::CompletedByAdmin,
        Ok(Status::Expired) => OrderStatus::Expired,
        Err(_) => OrderStatus::Unknown,
    }
}

// Native only, as `mostro::order_info::tests`, whose snapshot it reads.
#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::mostro::order_info::tests::snapshot;
    use crate::mostro::take::tests::ORDER;

    fn order() -> uuid::Uuid {
        uuid::Uuid::parse_str(ORDER).unwrap()
    }

    #[test]
    fn a_snapshot_carries_the_order_and_what_lightning_says_side_by_side() {
        let got = snapshot_of(&snapshot(ORDER));

        assert_eq!(got.order_id, ORDER);
        assert_eq!((got.kind, got.kind_raw.as_str()), (OrderKind::Sell, "sell"));
        // The database's status and the Lightning state are both there, each
        // as it was reported.
        assert_eq!(got.status, OrderStatus::SettledHoldInvoice);
        assert_eq!(got.status_raw, "settled-hold-invoice");
        assert_eq!(
            got.hold_invoice,
            Some(HoldInvoice {
                state: HoldInvoiceState::Settled,
                held_at: Some(1_700_000_200),
            })
        );
        assert_eq!((got.amount, got.fee), (100_000, 600));
        assert_eq!((got.fiat_amount, got.fiat_code.as_str()), (50, "EUR"));
        assert_eq!(got.payment_method, "SEPA");
        assert_eq!(got.buyer_trade_pubkey, Some("22".repeat(32)));
        assert_eq!(got.seller_trade_pubkey, Some("11".repeat(32)));
        assert!(got.seller_dispute && !got.buyer_dispute);
        // No payout in flight: the failure is told by these two.
        assert_eq!(got.payout, None);
        assert!(got.failed_payment);
        assert_eq!(got.payment_attempts, 2);
        assert_eq!(got.cashu_escrow, None);
        assert_eq!(
            got.bonds,
            vec![OrderBond {
                role: BondRole::Taker,
                amount: 1_000,
                state: BondState::Locked,
                slash_reason: None,
                kind: BondKind::Bond,
                root_order_id: None,
            }]
        );
    }

    #[test]
    fn every_status_of_mostro_core_has_a_marker() {
        for (raw, status) in [
            ("pending", OrderStatus::Pending),
            ("waiting-maker-bond", OrderStatus::WaitingMakerBond),
            ("waiting-taker-bond", OrderStatus::WaitingTakerBond),
            ("waiting-buyer-invoice", OrderStatus::WaitingBuyerInvoice),
            ("waiting-payment", OrderStatus::WaitingPayment),
            ("in-progress", OrderStatus::InProgress),
            ("active", OrderStatus::Active),
            ("fiat-sent", OrderStatus::FiatSent),
            ("settled-hold-invoice", OrderStatus::SettledHoldInvoice),
            ("success", OrderStatus::Success),
            ("dispute", OrderStatus::Dispute),
            ("canceled", OrderStatus::Canceled),
            ("cooperatively-canceled", OrderStatus::CooperativelyCanceled),
            ("canceled-by-admin", OrderStatus::CanceledByAdmin),
            ("settled-by-admin", OrderStatus::SettledByAdmin),
            ("completed-by-admin", OrderStatus::CompletedByAdmin),
            ("expired", OrderStatus::Expired),
        ] {
            assert_eq!(status_of(raw), status, "{raw}");
        }
    }

    #[test]
    fn a_status_or_kind_this_build_does_not_know_keeps_its_wire_value() {
        let mut info = snapshot(ORDER);
        info.status = "frozen-by-audit".into();
        info.kind = "swap".into();

        let got = snapshot_of(&info);

        assert_eq!(got.status, OrderStatus::Unknown);
        assert_eq!(got.status_raw, "frozen-by-audit");
        assert_eq!(got.kind, OrderKind::Unknown);
        assert_eq!(got.kind_raw, "swap");
    }

    #[test]
    fn unavailable_and_unknown_stay_two_different_things() {
        let mut info = snapshot(ORDER);
        info.hold_invoice = Some(core::HoldInvoiceInfo {
            state: core::HoldInvoiceState::Unavailable,
            held_at: None,
        });
        info.payout = Some(core::PayoutInfo {
            state: core::PayoutState::Unknown,
            failure_reason: Some(core::PayoutFailureReason::NoRoute),
            resolved_at: Some(1_700_000_300),
        });

        let got = snapshot_of(&info);

        assert_eq!(
            got.hold_invoice.unwrap().state,
            HoldInvoiceState::Unavailable
        );
        let payout = got.payout.unwrap();
        assert_eq!(payout.state, PayoutState::Unknown);
        assert_eq!(payout.failure_reason, Some(PayoutFailureReason::NoRoute));
        assert_eq!(payout.resolved_at, Some(1_700_000_300));
    }

    #[test]
    fn a_time_the_node_stores_as_zero_is_none() {
        let mut info = snapshot(ORDER);
        info.created_at = 0;
        info.expires_at = 0;
        info.taken_at = Some(0);
        info.hold_settled_at = Some(0);
        info.hold_invoice = Some(core::HoldInvoiceInfo {
            state: core::HoldInvoiceState::Open,
            held_at: Some(0),
        });

        let got = snapshot_of(&info);

        assert_eq!(got.created_at, None);
        assert_eq!(got.expires_at, None);
        assert_eq!(got.taken_at, None);
        assert_eq!(got.hold_settled_at, None);
        assert_eq!(got.hold_invoice.unwrap().held_at, None);
    }

    #[test]
    fn a_cashu_order_and_a_range_slice_keep_their_parts() {
        let root = uuid::Uuid::parse_str("0d4f6a2b-7c1e-4f3a-8b5d-9e0f1a2b3c4d").unwrap();
        let mut info = snapshot(ORDER);
        info.hold_invoice = None;
        info.cashu_escrow = Some(core::CashuEscrowInfo {
            mint_url: "https://mint.example".into(),
            locked_at: Some(1_700_000_150),
        });
        info.range_parent_id = Some(root);
        info.min_amount = Some(10);
        info.max_amount = Some(100);
        info.bonds = vec![core::BondInfo {
            role: core::BondRole::Maker,
            amount: 5_000,
            state: core::BondState::PendingPayout,
            slash_reason: Some(core::BondSlashReason::LostDispute),
            kind: core::BondKind::SliceSlash,
            root_order_id: Some(root),
        }];

        let got = snapshot_of(&info);

        assert_eq!(got.hold_invoice, None);
        assert_eq!(
            got.cashu_escrow,
            Some(CashuEscrow {
                mint_url: "https://mint.example".into(),
                locked_at: Some(1_700_000_150),
            })
        );
        assert_eq!(got.range_parent_id, Some(root.to_string()));
        assert_eq!((got.min_amount, got.max_amount), (Some(10), Some(100)));
        assert_eq!(
            got.bonds,
            vec![OrderBond {
                role: BondRole::Maker,
                amount: 5_000,
                state: BondState::PendingPayout,
                slash_reason: Some(BondSlashReason::LostDispute),
                kind: BondKind::SliceSlash,
                root_order_id: Some(root.to_string()),
            }]
        );
    }

    #[test]
    fn each_lookup_reads_as_its_outcome() {
        let result = |lookup| result_of("node".into(), order(), lookup, 1_700_000_500);

        let found = result(Lookup::Found(Box::new(snapshot(ORDER))));
        assert_eq!(found.outcome, OrderLookupOutcome::Found);
        assert_eq!(found.order.unwrap().order_id, ORDER);
        assert_eq!(found.mostro_pubkey, "node");
        assert_eq!(found.order_id, ORDER);
        assert_eq!(found.asked_at, 1_700_000_500);

        for (lookup, outcome, reason) in [
            (Lookup::NotFound, OrderLookupOutcome::NotFound, None),
            (Lookup::NotSolver, OrderLookupOutcome::NotSolver, None),
            (
                Lookup::Refused(Some("invalid_action".into())),
                OrderLookupOutcome::Refused,
                Some("invalid_action".to_string()),
            ),
            (Lookup::Refused(None), OrderLookupOutcome::Refused, None),
            (Lookup::NoAnswer, OrderLookupOutcome::NoAnswer, None),
        ] {
            let got = result(lookup);
            assert_eq!(got.outcome, outcome);
            assert_eq!(got.reason, reason);
            assert_eq!(got.order, None, "only a found order carries a snapshot");
        }
    }

    #[test]
    fn only_a_uuid_is_an_order_id() {
        assert!(is_order_id(ORDER.into()));
        assert!(is_order_id(format!(" {ORDER}\n")));
        assert!(!is_order_id(String::new()));
        assert!(!is_order_id("308e1272…9c23".into()));
        assert!(!is_order_id("11".repeat(32)));
    }
}
