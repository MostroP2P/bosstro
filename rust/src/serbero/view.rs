//! Serbero's stored messages of one dispute, put together as the screen shows
//! them: the newest brief, the newest transcript with its parts in order, the
//! updates oldest first and the final report.

use super::parse::{parse_lines, parse_report, Entry, ReportKind, Speaker};
use super::SerberoRecord;
use crate::api::serbero::{
    SerberoHeadline, SerberoLine, SerberoMediation, SerberoNote, SerberoSpeaker, SerberoUpdateView,
};

/// How far apart the parts of one transcript may have been sent: Serbero
/// sends them in one go, so parts further back belong to an older one.
const PARTS_WINDOW_SECS: i64 = 120;

/// `records` (one dispute's, in any order) as the dispute screen shows them.
pub(crate) fn assemble(dispute_id: &str, records: &[SerberoRecord]) -> SerberoMediation {
    let mut reports: Vec<(&SerberoRecord, super::parse::Report)> = records
        .iter()
        .filter_map(|r| parse_report(dispute_id, &r.content).map(|report| (r, report)))
        .collect();
    // Oldest first; the event id breaks ties so the order never depends on
    // how storage returned the rows.
    reports.sort_by(|(a, _), (b, _)| (a.created_at, &a.event_id).cmp(&(b.created_at, &b.event_id)));

    let note = |(r, report): &(&SerberoRecord, super::parse::Report)| {
        let (headline, detail) = headline(&report.subject);
        SerberoNote {
            subject: report.subject.clone(),
            headline,
            detail,
            body: body_shown(&report.body),
            sent_at: r.created_at,
        }
    };
    let newest = |kind: ReportKind| reports.iter().rev().find(|(_, rep)| rep.kind == kind).map(note);

    let (transcript, transcript_parts, transcript_total, transcript_sent_at) = transcript(&reports);
    SerberoMediation {
        dispute_id: dispute_id.to_owned(),
        brief: newest(ReportKind::Brief),
        transcript,
        transcript_parts,
        transcript_total,
        transcript_sent_at,
        updates: reports
            .iter()
            .filter(|(_, rep)| rep.kind == ReportKind::Update)
            .map(|(r, rep)| SerberoUpdateView {
                sent_at: r.created_at,
                lines: lines(&rep.body, r.created_at),
            })
            .collect(),
        final_report: newest(ReportKind::Final),
    }
}

/// The newest transcript: its parts in order (the newest copy of each), how
/// many arrived and of how many, and when its newest part was sent.
fn transcript(
    reports: &[(&SerberoRecord, super::parse::Report)],
) -> (Vec<SerberoLine>, u32, u32, Option<i64>) {
    let parts: Vec<(i64, u32, u32, &str)> = reports
        .iter()
        .filter_map(|(r, rep)| match rep.kind {
            ReportKind::Transcript { part, total } => Some((r.created_at, part, total, rep.body.as_str())),
            _ => None,
        })
        .collect();
    let Some(&(sent_at, _, total, _)) = parts.last() else {
        return (Vec::new(), 0, 0, None);
    };
    let mut chosen: Vec<Option<(i64, &str)>> = vec![None; total as usize];
    for &(at, part, n, body) in &parts {
        if n == total && at >= sent_at - PARTS_WINDOW_SECS {
            // Oldest first, so a later copy of a part replaces an earlier one.
            chosen[(part - 1) as usize] = Some((at, body));
        }
    }
    let arrived = chosen.iter().filter(|p| p.is_some()).count() as u32;
    let shown = chosen
        .into_iter()
        .flatten()
        .flat_map(|(at, body)| lines(body, at))
        .collect();
    (shown, arrived, total, Some(sent_at))
}

/// A subject's headline and what follows its colon.
fn headline(subject: &str) -> (SerberoHeadline, String) {
    for (prefix, headline) in [
        ("handed off: ", SerberoHeadline::HandedOff),
        ("guidance sent: ", SerberoHeadline::GuidanceSent),
        ("resolved: ", SerberoHeadline::Resolved),
    ] {
        if let Some(detail) = subject.strip_prefix(prefix) {
            return (headline, detail.trim().to_owned());
        }
    }
    (SerberoHeadline::Other, String::new())
}

/// A brief's text without its closing pointer to the transcript.
fn body_shown(body: &str) -> String {
    let trimmed = body.trim_end();
    match trimmed.rsplit_once('\n') {
        Some((head, last))
            if last.starts_with("Transcript (") && last.ends_with("follows in the next message.") =>
        {
            head.trim_end().to_owned()
        }
        _ => body.to_owned(),
    }
}

/// When a line stamped `hh:mm` (UTC) was written, given that the Serbero
/// message carrying it was sent at `sent_at`: that day, or the day before
/// when that time is later than the message.
fn written_at(time: &str, sent_at: i64) -> Option<i64> {
    let (h, m) = time.split_once(':')?;
    if h.len() != 2 || m.len() != 2 {
        return None;
    }
    let (h, m) = (h.parse::<i64>().ok()?, m.parse::<i64>().ok()?);
    if !(0..24).contains(&h) || !(0..60).contains(&m) {
        return None;
    }
    let day = sent_at - sent_at.rem_euclid(86_400);
    let at = day + h * 3600 + m * 60;
    // The line's minute may be the message's own: only a later minute is
    // the day before.
    Some(if at > sent_at { at - 86_400 } else { at })
}

fn lines(body: &str, sent_at: i64) -> Vec<SerberoLine> {
    parse_lines(body)
        .into_iter()
        .map(|entry| match entry {
            Entry::Line(line) => SerberoLine {
                at: written_at(&line.time, sent_at),
                time: line.time,
                speaker: Some(match line.speaker {
                    Speaker::Buyer => SerberoSpeaker::Buyer,
                    Speaker::Seller => SerberoSpeaker::Seller,
                    Speaker::SerberoToBuyer => SerberoSpeaker::SerberoToBuyer,
                    Speaker::SerberoToSeller => SerberoSpeaker::SerberoToSeller,
                }),
                text: line.text,
            },
            Entry::Text(text) => SerberoLine {
                at: None,
                time: String::new(),
                speaker: None,
                text,
            },
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::serbero::SerberoRef;

    const ID: &str = "8a0c1e64-0d3b-4c39-9a3e-3a1f1f0f4b2c";

    fn record(event: &str, sent_at: i64, text: &str) -> SerberoRecord {
        SerberoRecord {
            conversation: SerberoRef {
                mostro_pubkey: "aa".into(),
                dispute_id: ID.into(),
                solver_pubkey: "ss".into(),
            },
            event_id: event.into(),
            serbero_pubkey: "cc".into(),
            content: text.into(),
            created_at: sent_at,
            received_at: sent_at + 5,
        }
    }

    fn line(time: &str, speaker: SerberoSpeaker, text: &str) -> SerberoLine {
        SerberoLine {
            at: None,
            time: time.into(),
            speaker: Some(speaker),
            text: text.into(),
        }
    }

    /// The lines without when they were written, which the tests below on
    /// timing check on their own.
    fn untimed(lines: Vec<SerberoLine>) -> Vec<SerberoLine> {
        lines.into_iter().map(|l| SerberoLine { at: None, ..l }).collect()
    }

    fn is_empty(m: &SerberoMediation) -> bool {
        m.brief.is_none() && m.transcript_total == 0 && m.updates.is_empty() && m.final_report.is_none()
    }

    fn part(event: &str, sent_at: i64, i: u32, n: u32, body: &str) -> SerberoRecord {
        record(
            event,
            sent_at,
            &format!("Dispute {ID} · transcript (9 messages, times UTC, part {i}/{n})\n{body}"),
        )
    }

    #[test]
    fn nothing_stored_is_an_empty_mediation() {
        let mediation = assemble(ID, &[]);
        assert!(is_empty(&mediation));
        assert_eq!(mediation.dispute_id, ID);
    }

    #[test]
    fn the_parts_of_a_transcript_are_shown_in_order_whatever_arrived_first() {
        let records = [
            part("e3", 10, 3, 3, "[10:03] seller: tres"),
            part("e1", 10, 1, 3, "[10:01] buyer: uno"),
            part("e2", 10, 2, 3, "[10:02] serbero → buyer: dos"),
        ];
        let mediation = assemble(ID, &records);
        assert_eq!(
            untimed(mediation.transcript),
            vec![
                line("10:01", SerberoSpeaker::Buyer, "uno"),
                line("10:02", SerberoSpeaker::SerberoToBuyer, "dos"),
                line("10:03", SerberoSpeaker::Seller, "tres"),
            ]
        );
        assert_eq!((mediation.transcript_parts, mediation.transcript_total), (3, 3));
    }

    #[test]
    fn a_missing_part_is_counted_and_the_rest_shown() {
        let records = [
            part("e1", 10, 1, 3, "[10:01] buyer: uno"),
            part("e3", 10, 3, 3, "[10:03] seller: tres"),
        ];
        let mediation = assemble(ID, &records);
        assert_eq!(mediation.transcript.len(), 2);
        assert_eq!((mediation.transcript_parts, mediation.transcript_total), (2, 3));
    }

    #[test]
    fn a_resent_transcript_replaces_the_older_one() {
        let records = [
            part("old1", 10, 1, 2, "[10:01] buyer: viejo"),
            part("old2", 10, 2, 2, "[10:02] buyer: viejo 2"),
            record(
                "new",
                20,
                &format!("Dispute {ID} · transcript (1 messages, times UTC)\n[10:05] seller: nuevo"),
            ),
        ];
        let mediation = assemble(ID, &records);
        assert_eq!(
            untimed(mediation.transcript),
            vec![line("10:05", SerberoSpeaker::Seller, "nuevo")]
        );
        assert_eq!((mediation.transcript_parts, mediation.transcript_total), (1, 1));
    }

    #[test]
    fn the_newest_brief_updates_oldest_first_and_the_final_report() {
        let records = [
            record("u2", 40, &format!("Dispute {ID} · new messages since handoff (1)\n[11:00] seller: b")),
            record("b1", 10, &format!("Dispute {ID} · handed off: a\nTopic: old")),
            record("b2", 30, &format!("Dispute {ID} · guidance sent: b\nTopic: new")),
            record("u1", 35, &format!("Dispute {ID} · new messages since handoff (1)\n[10:59] buyer: a")),
            record("f", 50, &format!("Dispute {ID} · resolved: settled\noutcome: x")),
        ];
        let mediation = assemble(ID, &records);
        assert_eq!(
            mediation.brief,
            Some(SerberoNote {
                subject: "guidance sent: b".into(),
                headline: SerberoHeadline::GuidanceSent,
                detail: "b".into(),
                body: "Topic: new".into(),
                sent_at: 30,
            })
        );
        let updates: Vec<SerberoUpdateView> = mediation
            .updates
            .into_iter()
            .map(|u| SerberoUpdateView { lines: untimed(u.lines), ..u })
            .collect();
        assert_eq!(
            updates,
            vec![
                SerberoUpdateView {
                    sent_at: 35,
                    lines: vec![line("10:59", SerberoSpeaker::Buyer, "a")],
                },
                SerberoUpdateView {
                    sent_at: 40,
                    lines: vec![line("11:00", SerberoSpeaker::Seller, "b")],
                },
            ]
        );
        assert_eq!(
            mediation.final_report.map(|n| n.subject),
            Some("resolved: settled".to_string())
        );
        assert!(mediation.transcript.is_empty());
    }

    #[test]
    fn a_stored_row_of_another_dispute_or_unreadable_is_skipped() {
        let records = [
            record("x", 10, "Dispute 11111111-2222-3333-4444-555555555555 · handed off: a\nb"),
            record("y", 10, "garbage"),
        ];
        assert!(is_empty(&assemble(ID, &records)));
    }

    #[test]
    fn a_headline_names_what_follows_its_colon() {
        for (subject, kind, detail) in [
            ("handed off: human_requested", SerberoHeadline::HandedOff, "human_requested"),
            ("guidance sent: payment_arrived", SerberoHeadline::GuidanceSent, "payment_arrived"),
            ("resolved: seller-refunded", SerberoHeadline::Resolved, "seller-refunded"),
            ("something new: x", SerberoHeadline::Other, ""),
        ] {
            assert_eq!(headline(subject), (kind, detail.to_string()), "{subject}");
        }
    }

    #[test]
    fn the_brief_loses_its_pointer_to_the_transcript_and_nothing_else() {
        let body = "Topic: x\n\nSignals: y\n\nTranscript (8 messages) follows in the next message.";
        assert_eq!(body_shown(body), "Topic: x\n\nSignals: y");
        // A brief that changed its closing line keeps it.
        assert_eq!(body_shown("Topic: x\nTranscript below."), "Topic: x\nTranscript below.");
        let records = [record(
            "b",
            10,
            &format!("Dispute {ID} · handed off: human_requested\n{body}"),
        )];
        let brief = assemble(ID, &records).brief.unwrap();
        assert_eq!(brief.body, "Topic: x\n\nSignals: y");
        assert_eq!(brief.headline, SerberoHeadline::HandedOff);
        assert_eq!(brief.detail, "human_requested");
    }

    #[test]
    fn a_line_is_dated_by_the_message_that_carried_it() {
        // 2026-11-20 22:26:47 UTC.
        let sent: i64 = 1_795_213_607;
        let day = sent - sent.rem_euclid(86_400);
        assert_eq!(written_at("22:25", sent), Some(day + 22 * 3600 + 25 * 60));
        // Later than the message: written the day before (a dispute that
        // crossed midnight UTC).
        assert_eq!(written_at("23:50", sent), Some(day - 86_400 + 23 * 3600 + 50 * 60));
        for bad in ["", "24:00", "12:60", "1:05", "ab:cd"] {
            assert_eq!(written_at(bad, sent), None, "{bad}");
        }
        let records = [record(
            "t",
            sent,
            &format!("Dispute {ID} · transcript (1 messages, times UTC)\n[22:25] seller: no"),
        )];
        assert_eq!(
            assemble(ID, &records).transcript[0].at,
            Some(day + 22 * 3600 + 25 * 60)
        );
    }

    #[test]
    fn a_transcript_whose_brief_never_arrived_still_dates_the_mediation() {
        let records = [
            part("e1", 10, 1, 2, "[10:01] buyer: uno"),
            part("e2", 12, 2, 2, "[10:02] seller: dos"),
        ];
        let mediation = assemble(ID, &records);
        assert!(mediation.brief.is_none());
        assert_eq!(mediation.transcript_sent_at, Some(12));
        assert_eq!(assemble(ID, &[]).transcript_sent_at, None);
    }
}
