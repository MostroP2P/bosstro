//! Serbero, the assistant Read solver (D13): which pubkey the solver trusts
//! as Serbero on each node.
//!
//! Serbero mediates with its own key, so Bosstro cannot open its chat with
//! the parties. At handoff it sends the brief and the transcript to the
//! solver key as `send-dm` messages; those are read only from the pubkey
//! kept here, one per node (D6), and never treated as protocol actions.

use anyhow::{bail, Result};

use crate::api::nodes::parse_node_pubkey;
use crate::db::{settings_keys, Storage};

/// The Serbero pubkey trusted on `node`, as an npub to show, or `None` when
/// none is set.
pub async fn get_serbero_npub(node: String) -> Result<Option<String>> {
    match crate::db::app_db::db() {
        Some(db) => read_serbero(db, &node)
            .await?
            .map(|hex| npub(&hex))
            .transpose(),
        None => Ok(None),
    }
}

/// Trust `pubkey` (hex or `npub1…`) as Serbero on `node`, or stop trusting
/// any with `None`. Returns it as an npub to show.
///
/// **Errors**: `PrivateKeyNotAllowed`, `InvalidPubkey`, `SerberoIsNode` (the
/// node's own key), `NotInitialized`, or a storage failure.
pub async fn set_serbero_pubkey(node: String, pubkey: Option<String>) -> Result<Option<String>> {
    let Some(db) = crate::db::app_db::db() else {
        bail!("NotInitialized: storage is not ready");
    };
    let trusted = write_serbero(db, &node, pubkey.as_deref()).await?;
    // Serbero's reports are followed from the new key, or no more.
    crate::serbero::router::follow().await;
    trusted.map(|hex| npub(&hex)).transpose()
}

/// The hex Serbero pubkey trusted on `node`, for the core's own readers.
pub(crate) async fn trusted_serbero(db: &impl Storage, node: &str) -> Result<Option<String>> {
    read_serbero(db, node).await
}

fn npub(hex: &str) -> Result<String> {
    use nostr_sdk::prelude::{PublicKey, ToBech32};
    Ok(PublicKey::from_hex(hex)?.to_bech32()?)
}

async fn read_serbero(db: &impl Storage, node: &str) -> Result<Option<String>> {
    Ok(db
        .get_setting(&settings_keys::serbero_pubkey(node))
        .await?
        .and_then(|stored| match parse_node_pubkey(&stored) {
            Ok(hex) => Some(hex),
            Err(e) => {
                log::warn!("[serbero] the stored Serbero key does not parse; none is trusted: {e}");
                None
            }
        }))
}

async fn write_serbero(
    db: &impl Storage,
    node: &str,
    pubkey: Option<&str>,
) -> Result<Option<String>> {
    let key = settings_keys::serbero_pubkey(node);
    let Some(input) = pubkey.filter(|p| !p.trim().is_empty()) else {
        db.delete_setting(&key).await?;
        return Ok(None);
    };
    let hex = parse_node_pubkey(input)?;
    if hex == node {
        bail!("SerberoIsNode: the node's own key cannot be Serbero");
    }
    db.set_setting(&key, &hex).await?;
    Ok(Some(hex))
}

// ── Serbero's mediation, as the dispute screen shows it ──────────────────────

/// Who wrote one message of Serbero's transcript.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SerberoSpeaker {
    Buyer,
    Seller,
    /// Serbero, writing to the buyer.
    SerberoToBuyer,
    /// Serbero, writing to the seller.
    SerberoToSeller,
}

/// One line of the conversation Serbero had with the parties: a message, or
/// text that reads as none (kept, never dropped).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SerberoLine {
    /// `hh:mm`, UTC, as Serbero wrote it; empty for text that is no message.
    pub time: String,
    /// When it was written (unix seconds), from that `hh:mm` and the day of
    /// the Serbero message that carried it; `None` for text that is no
    /// message.
    pub at: Option<i64>,
    /// Who wrote it; `None` for text that is no message.
    pub speaker: Option<SerberoSpeaker>,
    /// As Serbero wrote it. Serbero forwards no files, only a
    /// `[n attachments]` note at the end, which a party could also type.
    pub text: String,
}

/// What a brief or a final report says in its first line, for Dart to put in
/// words (Rust does not translate).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SerberoHeadline {
    /// `handed off: <reason>` (Serbero's handoff reasons).
    HandedOff,
    /// `guidance sent: <path>`.
    GuidanceSent,
    /// `resolved: <dispute status>`.
    Resolved,
    /// Anything else: show the subject as it came.
    Other,
}

/// A Serbero message shown as Serbero wrote it: the brief, an update, the
/// final report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SerberoNote {
    /// The subject of its first line (`handed off: …`, `resolved: …`).
    pub subject: String,
    pub headline: SerberoHeadline,
    /// What follows the headline's colon: a handoff reason, a guidance path
    /// or a dispute status, as Serbero names it (`human_requested`).
    pub detail: String,
    /// The text after the first line. A brief's closing line, "Transcript
    /// (N messages) follows in the next message.", is left out: the screen
    /// shows the transcript under it.
    pub body: String,
    /// When Serbero sent it (unix seconds).
    pub sent_at: i64,
}

/// The messages that arrived after the handoff, in one Serbero message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SerberoUpdateView {
    pub sent_at: i64,
    pub lines: Vec<SerberoLine>,
}

/// What Serbero sent this solver key about one dispute.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SerberoMediation {
    pub dispute_id: String,
    /// The newest brief (a handoff or a guidance).
    pub brief: Option<SerberoNote>,
    /// The newest transcript, its parts in order.
    pub transcript: Vec<SerberoLine>,
    /// How many parts of that transcript arrived, of how many.
    pub transcript_parts: u32,
    pub transcript_total: u32,
    /// When the newest part of that transcript was sent (unix seconds), so
    /// a transcript whose brief never arrived still dates the mediation.
    pub transcript_sent_at: Option<i64>,
    /// The messages after the handoff, oldest first.
    pub updates: Vec<SerberoUpdateView>,
    /// The final report, once the dispute was resolved.
    pub final_report: Option<SerberoNote>,
}

/// What Serbero sent the loaded key about `dispute_id` on the active node, as
/// stored. `None` without an active node, a loaded key or storage.
pub async fn serbero_mediation(dispute_id: String) -> Result<Option<SerberoMediation>> {
    let Ok((node, keys)) = crate::chat::router::node_and_keys().await else {
        return Ok(None);
    };
    let Some(db) = crate::db::app_db::db() else {
        return Ok(None);
    };
    Ok(Some(
        mediation_for(db, &node, &keys.public_key().to_hex(), &dispute_id).await?,
    ))
}

/// What the Serbero trusted on `node` now sent `solver` about `dispute_id`.
/// Reports of a key no longer trusted are not shown, and nothing is without
/// a trusted key (D13).
async fn mediation_for(
    db: &impl Storage,
    node: &str,
    solver: &str,
    dispute_id: &str,
) -> Result<SerberoMediation> {
    let Some(trusted) = read_serbero(db, node).await? else {
        return Ok(crate::serbero::view::assemble(dispute_id, &[]));
    };
    let records: Vec<_> = db
        .list_serbero_messages(&crate::serbero::SerberoRef {
            mostro_pubkey: node.to_owned(),
            dispute_id: dispute_id.to_owned(),
            solver_pubkey: solver.to_owned(),
        })
        .await?
        .into_iter()
        .filter(|r| r.serbero_pubkey == trusted)
        .collect();
    Ok(crate::serbero::view::assemble(dispute_id, &records))
}

/// Stream of the disputes whose Serbero reports changed on the active node.
pub fn on_serbero_updates() -> SerberoUpdateStream {
    SerberoUpdateStream {
        rx: crate::serbero::router::subscribe_updates(),
    }
}

/// Wrapper so flutter_rust_bridge can hand Dart a pull-based stream.
pub struct SerberoUpdateStream {
    rx: tokio::sync::broadcast::Receiver<crate::serbero::router::SerberoUpdate>,
}

impl SerberoUpdateStream {
    /// The next dispute id whose reports changed on the active node, `""`
    /// when this reader fell behind (read again whatever is shown), or
    /// `None` once the router is gone.
    pub async fn next(&mut self) -> Option<String> {
        use tokio::sync::broadcast::error::RecvError;
        loop {
            match self.rx.recv().await {
                Ok(update) => {
                    if crate::config::active_mostro_pubkey().as_deref()
                        == Some(update.mostro_pubkey.as_str())
                    {
                        return Some(update.dispute_id);
                    }
                }
                Err(RecvError::Lagged(_)) => {
                    self.rx = self.rx.resubscribe();
                    return Some(String::new());
                }
                Err(RecvError::Closed) => return None,
            }
        }
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use nostr_sdk::prelude::{Keys, ToBech32};

    #[tokio::test]
    async fn none_is_trusted_until_one_is_set() {
        let db = crate::db::sqlite::tests::store().await;
        let node = Keys::generate().public_key().to_hex();
        assert_eq!(read_serbero(&db, &node).await.unwrap(), None);
    }

    #[tokio::test]
    async fn an_npub_is_kept_as_hex_per_node_and_cleared() {
        let db = crate::db::sqlite::tests::store().await;
        let node = Keys::generate().public_key().to_hex();
        let other = Keys::generate().public_key().to_hex();
        let serbero = Keys::generate().public_key();
        let stored = write_serbero(&db, &node, Some(&serbero.to_bech32().unwrap()))
            .await
            .unwrap();
        assert_eq!(stored, Some(serbero.to_hex()));
        assert_eq!(
            read_serbero(&db, &node).await.unwrap(),
            Some(serbero.to_hex())
        );
        assert_eq!(
            read_serbero(&db, &other).await.unwrap(),
            None,
            "per node (D6)"
        );
        assert_eq!(write_serbero(&db, &node, None).await.unwrap(), None);
        assert_eq!(read_serbero(&db, &node).await.unwrap(), None);
    }

    #[tokio::test]
    async fn a_blank_input_clears() {
        let db = crate::db::sqlite::tests::store().await;
        let node = Keys::generate().public_key().to_hex();
        let serbero = Keys::generate().public_key().to_hex();
        write_serbero(&db, &node, Some(&serbero)).await.unwrap();
        assert_eq!(write_serbero(&db, &node, Some("  ")).await.unwrap(), None);
        assert_eq!(read_serbero(&db, &node).await.unwrap(), None);
    }

    #[tokio::test]
    async fn bad_inputs_are_refused_and_change_nothing() {
        let db = crate::db::sqlite::tests::store().await;
        let node = Keys::generate().public_key().to_hex();
        let serbero = Keys::generate().public_key().to_hex();
        write_serbero(&db, &node, Some(&serbero)).await.unwrap();
        let nsec = Keys::generate().secret_key().to_bech32().unwrap();
        for (input, marker) in [
            ("not a key", "InvalidPubkey"),
            (nsec.as_str(), "PrivateKeyNotAllowed"),
            (node.as_str(), "SerberoIsNode"),
        ] {
            let error = write_serbero(&db, &node, Some(input)).await.unwrap_err();
            assert!(error.to_string().starts_with(marker), "{input}: {error}");
        }
        assert_eq!(read_serbero(&db, &node).await.unwrap(), Some(serbero));
    }

    fn report(node: &str, solver: &str, serbero: &str, event: &str) -> crate::serbero::SerberoRecord {
        crate::serbero::SerberoRecord {
            conversation: crate::serbero::SerberoRef {
                mostro_pubkey: node.into(),
                dispute_id: DISPUTE.into(),
                solver_pubkey: solver.into(),
            },
            event_id: event.into(),
            serbero_pubkey: serbero.into(),
            content: format!("Dispute {DISPUTE} · handed off: human_requested\nTopic: {event}"),
            created_at: 10,
            received_at: 11,
        }
    }

    const DISPUTE: &str = "8a0c1e64-0d3b-4c39-9a3e-3a1f1f0f4b2c";

    #[tokio::test]
    async fn only_the_serbero_trusted_now_is_shown() {
        let db = crate::db::sqlite::tests::store().await;
        let node = Keys::generate().public_key().to_hex();
        let solver = Keys::generate().public_key().to_hex();
        let (old, new) = (Keys::generate().public_key().to_hex(), Keys::generate().public_key().to_hex());
        db.insert_serbero_message(&report(&node, &solver, &old, "from-old")).await.unwrap();
        let topic = |m: &SerberoMediation| m.brief.as_ref().map(|b| b.body.clone());

        let none = mediation_for(&db, &node, &solver, DISPUTE).await.unwrap();
        assert_eq!(topic(&none), None, "nothing without a trusted key");

        write_serbero(&db, &node, Some(&old)).await.unwrap();
        let shown = mediation_for(&db, &node, &solver, DISPUTE).await.unwrap();
        assert_eq!(topic(&shown).as_deref(), Some("Topic: from-old"));

        write_serbero(&db, &node, Some(&new)).await.unwrap();
        let replaced = mediation_for(&db, &node, &solver, DISPUTE).await.unwrap();
        assert_eq!(topic(&replaced), None, "a key no longer trusted is not shown");

        db.insert_serbero_message(&report(&node, &solver, &new, "from-new")).await.unwrap();
        let current = mediation_for(&db, &node, &solver, DISPUTE).await.unwrap();
        assert_eq!(topic(&current).as_deref(), Some("Topic: from-new"));
    }
}
