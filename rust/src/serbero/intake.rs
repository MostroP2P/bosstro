//! The trust boundary for Serbero's messages: which kind 14 events are
//! Serbero's reports to this solver key, and which are dropped.

use mostro_core::message::{Action, Message, Payload};
use nostr_sdk::prelude::{Event, Filter, Keys, Kind, PublicKey, Timestamp};

use super::parse::{parse_report, Report};

/// How far back the subscription reaches: a handoff the solver missed while
/// the app was closed still arrives. Serbero's own reader keeps a week.
pub(crate) const BACKLOG_SECS: u64 = 30 * 24 * 60 * 60;

/// A Serbero report this app keeps.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Accepted {
    /// The outer event's id (hex): one row per event, whatever relay sent it.
    pub event_id: String,
    /// When Serbero sent it (the outer event's `created_at`).
    pub created_at: i64,
    pub report: Report,
}

/// Every kind 14 the trusted Serbero sends to `solver`, from `since` on.
pub(crate) fn reports_filter(serbero: &PublicKey, solver: &PublicKey, since: Timestamp) -> Filter {
    Filter::new()
        .kind(Kind::PrivateDirectMessage)
        .author(*serbero)
        .pubkey(*solver)
        .since(since)
}

/// `event` as a report of the trusted `serbero` to `solver`, or `None`.
pub(crate) async fn accept(solver: &Keys, serbero: &PublicKey, event: &Event) -> Option<Accepted> {
    if event.pubkey != *serbero || event.kind != Kind::PrivateDirectMessage {
        return None;
    }
    let opened = match crate::nostr::transport::unwrap_mostro_message(solver, event).await {
        Ok(Some(opened)) => opened,
        Ok(None) => return None,
        Err(e) => {
            log::debug!("[serbero] unreadable message dropped: {e}");
            return None;
        }
    };
    // Serbero signs with its identity key, with no trade key in between.
    if opened.sender != *serbero || opened.identity != *serbero {
        return None;
    }
    // Serbero writes `send-dm` as a direct message, never inside an order or
    // a dispute message.
    if !matches!(opened.message, Message::Dm(_)) {
        return None;
    }
    let inner = opened.message.get_inner_message_kind();
    if inner.action != Action::SendDm {
        return None;
    }
    let Some(Payload::TextMessage(text)) = &inner.payload else {
        return None;
    };
    let dispute_id = inner.id?.to_string();
    let report = parse_report(&dispute_id, text)?;
    Some(Accepted {
        event_id: event.id.to_hex(),
        created_at: event.created_at.as_secs() as i64,
        report,
    })
}

#[cfg(all(test, not(target_arch = "wasm32")))]
pub(crate) mod tests {
    use super::*;
    use crate::serbero::parse::ReportKind;
    use mostro_core::transport::{wrap_message_nip44, WrapOptions};
    use uuid::Uuid;

    pub(crate) const DISPUTE: &str = "8a0c1e64-0d3b-4c39-9a3e-3a1f1f0f4b2c";

    pub(crate) fn transcript_text() -> String {
        format!("Dispute {DISPUTE} · transcript (1 messages, times UTC)\n[14:10] buyer: hola")
    }

    /// A message built as Serbero builds it (`src/nostr/dm.rs`, `solver_dm`).
    pub(crate) fn serbero_dm(serbero: &Keys, solver: &PublicKey, text: &str) -> Event {
        let message = Message::new_dm(
            Some(Uuid::parse_str(DISPUTE).unwrap()),
            None,
            Action::SendDm,
            Some(Payload::TextMessage(text.to_owned())),
        );
        wrap_message_nip44(&message, serbero, serbero, *solver, WrapOptions::default()).unwrap()
    }

    fn wrap(author: &Keys, solver: &PublicKey, message: &Message) -> Event {
        wrap_message_nip44(message, author, author, *solver, WrapOptions::default()).unwrap()
    }

    #[tokio::test]
    async fn a_report_from_the_trusted_serbero_is_taken() {
        let (solver, serbero) = (Keys::generate(), Keys::generate());
        let event = serbero_dm(&serbero, &solver.public_key(), &transcript_text());
        let accepted = accept(&solver, &serbero.public_key(), &event).await.unwrap();
        assert_eq!(accepted.event_id, event.id.to_hex());
        assert_eq!(accepted.created_at, event.created_at.as_secs() as i64);
        assert_eq!(accepted.report.dispute_id, DISPUTE);
        assert_eq!(
            accepted.report.kind,
            ReportKind::Transcript { part: 1, total: 1 }
        );
    }

    #[tokio::test]
    async fn the_same_text_from_another_key_is_dropped() {
        let (solver, serbero, stranger) = (Keys::generate(), Keys::generate(), Keys::generate());
        let event = serbero_dm(&stranger, &solver.public_key(), &transcript_text());
        assert_eq!(accept(&solver, &serbero.public_key(), &event).await, None);
    }

    #[tokio::test]
    async fn a_report_to_another_solver_is_dropped() {
        let (solver, other, serbero) = (Keys::generate(), Keys::generate(), Keys::generate());
        let event = serbero_dm(&serbero, &other.public_key(), &transcript_text());
        assert_eq!(accept(&solver, &serbero.public_key(), &event).await, None);
    }

    #[tokio::test]
    async fn a_protocol_action_from_serbero_is_never_taken() {
        let (solver, serbero) = (Keys::generate(), Keys::generate());
        let id = Some(Uuid::parse_str(DISPUTE).unwrap());
        for message in [
            Message::new_dispute(id, None, None, Action::AdminSettled, None),
            Message::new_dispute(
                id,
                None,
                None,
                Action::AdminTookDispute,
                Some(Payload::TextMessage(transcript_text())),
            ),
            Message::new_dm(id, None, Action::SendDm, None),
            // Found by the independent verifier: send-dm outside a Dm.
            Message::new_dispute(
                id,
                None,
                None,
                Action::SendDm,
                Some(Payload::TextMessage(transcript_text())),
            ),
            Message::new_order(
                id,
                None,
                None,
                Action::SendDm,
                Some(Payload::TextMessage(transcript_text())),
            ),
        ] {
            let event = wrap(&serbero, &solver.public_key(), &message);
            assert_eq!(
                accept(&solver, &serbero.public_key(), &event).await,
                None,
                "{message:?}"
            );
        }
    }

    #[tokio::test]
    async fn a_text_about_another_dispute_than_the_message_id_is_dropped() {
        let (solver, serbero) = (Keys::generate(), Keys::generate());
        let text = "Dispute 11111111-2222-3333-4444-555555555555 · transcript (1 messages, times UTC)\n[14:10] buyer: x";
        let event = serbero_dm(&serbero, &solver.public_key(), text);
        assert_eq!(accept(&solver, &serbero.public_key(), &event).await, None);
    }

    #[tokio::test]
    async fn a_message_without_a_dispute_id_is_dropped() {
        let (solver, serbero) = (Keys::generate(), Keys::generate());
        let message = Message::new_dm(
            None,
            None,
            Action::SendDm,
            Some(Payload::TextMessage(transcript_text())),
        );
        let event = wrap(&serbero, &solver.public_key(), &message);
        assert_eq!(accept(&solver, &serbero.public_key(), &event).await, None);
    }

    #[test]
    fn the_filter_pins_serbero_and_the_solver() {
        let (solver, serbero) = (Keys::generate(), Keys::generate());
        let filter = reports_filter(
            &serbero.public_key(),
            &solver.public_key(),
            Timestamp::from_secs(7),
        );
        let json = serde_json::to_value(&filter).unwrap();
        assert_eq!(json["kinds"], serde_json::json!([14]));
        assert_eq!(json["authors"], serde_json::json!([serbero.public_key().to_hex()]));
        assert_eq!(json["#p"], serde_json::json!([solver.public_key().to_hex()]));
        assert_eq!(json["since"], serde_json::json!(7));
    }
}
