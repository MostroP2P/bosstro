//! Serbero's text contract (Serbero's `docs/messages.md` §3): the first line
//! is `Dispute <dispute_id> · <subject>`, and the subject's first words say
//! what the message is. Everything after the first line is for the solver to
//! read and may change, so only the transcript lines are split further, and a
//! line that does not read as one is kept as text, never dropped.

/// The most parts a transcript of Serbero's has (`part 999/999`).
pub(crate) const MAX_PARTS: u32 = 999;

/// What one Serbero message is, from its subject.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ReportKind {
    /// `handed off: …` or `guidance sent: …`: the summary before the transcript.
    Brief,
    /// `transcript (N messages, times UTC[, part i/n])`.
    Transcript { part: u32, total: u32 },
    /// `new messages since handoff (n)`.
    Update,
    /// `resolved: …`.
    Final,
}

/// A Serbero message this app keeps.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Report {
    pub dispute_id: String,
    pub kind: ReportKind,
    /// The subject, after `· `.
    pub subject: String,
    /// The text after the first line.
    pub body: String,
}

/// Who wrote a transcript line.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Speaker {
    Buyer,
    Seller,
    /// Serbero, to that party.
    SerberoToBuyer,
    SerberoToSeller,
}

/// One message of a transcript or an update.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TranscriptLine {
    /// `hh:mm`, UTC, as Serbero wrote it.
    pub time: String,
    pub speaker: Speaker,
    /// As Serbero wrote it, with its `[n attachments]` note when there is
    /// one: the note is not split off, because a party can type the same
    /// text and only Serbero's whole line says which it is.
    pub text: String,
}

/// A piece of a transcript body: a message, or text that reads as none.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Entry {
    Line(TranscriptLine),
    Text(String),
}

/// `text` as a report about `dispute_id` (the message id), or `None` when its
/// first line names another dispute or a subject this app does not keep.
pub(crate) fn parse_report(dispute_id: &str, text: &str) -> Option<Report> {
    let (first, body) = text.split_once('\n').unwrap_or((text, ""));
    let rest = first.strip_prefix("Dispute ")?;
    let (id, subject) = rest.split_once(" · ")?;
    if id != dispute_id {
        return None;
    }
    let kind = kind_of(subject)?;
    Some(Report {
        dispute_id: dispute_id.to_owned(),
        kind,
        subject: subject.to_owned(),
        body: party_breaks_indented(body),
    })
}

/// `body` with every line break a party could have written indented as
/// Serbero indents `\n`. Serbero's `verbatim()` indents only `\n`, but
/// Flutter also breaks lines on U+2028, U+2029, `\v` and `\f` (and U+0085 or
/// a lone `\r` break elsewhere): left as they are, a party's words could show
/// a line that reads as Serbero's own. Serbero never writes these itself, so
/// its own lines are untouched; a CRLF is the one `\n` it already indented.
/// Applied when parsing, so reports stored before keep their text as sent.
fn party_breaks_indented(body: &str) -> String {
    let mut out = String::with_capacity(body.len());
    let mut chars = body.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\r' if chars.peek() == Some(&'\n') => {}
            '\r' | '\u{0085}' | '\u{000B}' | '\u{000C}' | '\u{2028}' | '\u{2029}' => {
                out.push_str("\n  ");
            }
            other => out.push(other),
        }
    }
    out
}

fn kind_of(subject: &str) -> Option<ReportKind> {
    if subject.starts_with("handed off:") || subject.starts_with("guidance sent:") {
        return Some(ReportKind::Brief);
    }
    if subject.starts_with("new messages since handoff") {
        return Some(ReportKind::Update);
    }
    if subject.starts_with("resolved:") {
        return Some(ReportKind::Final);
    }
    let detail = subject.strip_prefix("transcript (")?.strip_suffix(')')?;
    let Some((_, part)) = detail.rsplit_once(", part ") else {
        return Some(ReportKind::Transcript { part: 1, total: 1 });
    };
    let (part, total) = part.split_once('/')?;
    let (part, total) = (part.parse::<u32>().ok()?, total.parse::<u32>().ok()?);
    // Serbero sizes its part header for at most 999 parts; more is no
    // transcript of its, and would only make the reader reserve room.
    if total > MAX_PARTS {
        return None;
    }
    (1..=total)
        .contains(&part)
        .then_some(ReportKind::Transcript { part, total })
}

/// The messages of a transcript or update body, in order.
pub(crate) fn parse_lines(body: &str) -> Vec<Entry> {
    let mut entries: Vec<Entry> = Vec::new();
    for line in body.lines() {
        // Serbero indents a message's own line breaks by two spaces.
        if let Some(more) = line.strip_prefix("  ") {
            if let Some(Entry::Line(last)) = entries.last_mut() {
                last.text.push('\n');
                last.text.push_str(more);
                continue;
            }
        }
        match message_line(line) {
            Some(message) => entries.push(Entry::Line(message)),
            None if line.trim().is_empty() => {}
            None => entries.push(Entry::Text(line.to_owned())),
        }
    }
    entries
}

/// `[hh:mm] who: text`.
fn message_line(line: &str) -> Option<TranscriptLine> {
    let rest = line.strip_prefix('[')?;
    let (time, rest) = rest.split_once("] ")?;
    let valid_time = time.len() == 5
        && time.as_bytes()[2] == b':'
        && time.bytes().enumerate().all(|(i, b)| i == 2 || b.is_ascii_digit());
    if !valid_time {
        return None;
    }
    let (who, text) = rest.split_once(": ")?;
    let speaker = match who {
        "buyer" => Speaker::Buyer,
        "seller" => Speaker::Seller,
        "serbero → buyer" => Speaker::SerberoToBuyer,
        "serbero → seller" => Speaker::SerberoToSeller,
        _ => return None,
    };
    Some(TranscriptLine {
        time: time.to_owned(),
        speaker,
        text: text.to_owned(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "8a0c1e64-0d3b-4c39-9a3e-3a1f1f0f4b2c";

    fn report(text: &str) -> Option<Report> {
        parse_report(ID, text)
    }

    #[test]
    fn a_handoff_and_a_guidance_are_briefs() {
        let brief = report(&format!(
            "Dispute {ID} · handed off: conflicting_claims\nTopic: x\n\nTranscript (2 messages) follows in the next message."
        ))
        .unwrap();
        assert_eq!(brief.dispute_id, ID);
        assert_eq!(brief.kind, ReportKind::Brief);
        assert_eq!(brief.subject, "handed off: conflicting_claims");
        assert_eq!(
            brief.body,
            "Topic: x\n\nTranscript (2 messages) follows in the next message."
        );
        let guidance = report(&format!("Dispute {ID} · guidance sent: payment\nTopic: y")).unwrap();
        assert_eq!(guidance.kind, ReportKind::Brief);
    }

    #[test]
    fn a_transcript_whole_or_in_parts() {
        let whole = report(&format!(
            "Dispute {ID} · transcript (2 messages, times UTC)\n[14:10] buyer: hola"
        ))
        .unwrap();
        assert_eq!(whole.kind, ReportKind::Transcript { part: 1, total: 1 });
        assert_eq!(whole.body, "[14:10] buyer: hola");
        let part = report(&format!(
            "Dispute {ID} · transcript (40 messages, times UTC, part 2/3)\n[14:10] buyer: hola"
        ))
        .unwrap();
        assert_eq!(part.kind, ReportKind::Transcript { part: 2, total: 3 });
    }

    #[test]
    fn an_update_and_a_final_report() {
        let update = report(&format!(
            "Dispute {ID} · new messages since handoff (1)\n[15:00] seller: ok"
        ))
        .unwrap();
        assert_eq!(update.kind, ReportKind::Update);
        let done = report(&format!("Dispute {ID} · resolved: settled\noutcome: x")).unwrap();
        assert_eq!(done.kind, ReportKind::Final);
        assert_eq!(done.subject, "resolved: settled");
    }

    #[test]
    fn notices_and_strangers_are_not_kept() {
        for text in [
            format!("Dispute {ID} · new\nopened by: seller"),
            format!("Dispute {ID} · taken\ntaken by: Serbero"),
            format!("Dispute {ID} · mediating\nSerbero is mediating"),
            format!("Dispute {ID} · unattended (32 min)"),
            "wrong question".to_string(),
            String::new(),
            format!("Dispute {ID} transcript (2 messages)"),
            format!("Dispute {ID} · transcript (2 messages, part 0/3)"),
            format!("Dispute {ID} · transcript (2 messages, part 4/3)"),
            format!("Dispute {ID} · transcript (2 messages, part 1/1000)"),
            format!("Dispute {ID} · transcript (2 messages, part 1/4294967295)"),
        ] {
            assert_eq!(report(&text), None, "{text}");
        }
    }

    #[test]
    fn a_report_about_another_dispute_is_not_kept() {
        let other = "11111111-2222-3333-4444-555555555555";
        assert_eq!(
            report(&format!("Dispute {other} · transcript (1 messages, times UTC)\nx")),
            None
        );
    }

    #[test]
    fn transcript_lines_with_speakers_and_continuations() {
        let body = "[14:10] buyer: ya envié el pago\n  desde Mercado Pago  [1 attachment]\n\
                    [14:11] serbero → seller: ¿lo recibiste?\n\
                    [14:20] seller: no  [2 attachments]\n\
                    [14:21] serbero → buyer: gracias\n\
                    something else";
        assert_eq!(
            parse_lines(body),
            vec![
                Entry::Line(TranscriptLine {
                    time: "14:10".into(),
                    speaker: Speaker::Buyer,
                    text: "ya envié el pago\ndesde Mercado Pago  [1 attachment]".into(),
                }),
                Entry::Line(TranscriptLine {
                    time: "14:11".into(),
                    speaker: Speaker::SerberoToSeller,
                    text: "¿lo recibiste?".into(),
                }),
                Entry::Line(TranscriptLine {
                    time: "14:20".into(),
                    speaker: Speaker::Seller,
                    text: "no  [2 attachments]".into(),
                }),
                Entry::Line(TranscriptLine {
                    time: "14:21".into(),
                    speaker: Speaker::SerberoToBuyer,
                    text: "gracias".into(),
                }),
                Entry::Text("something else".into()),
            ]
        );
    }

    #[test]
    fn a_party_text_that_mimics_a_line_stays_inside_its_message() {
        // Serbero indents a message's own line breaks, so a party cannot forge
        // a line of the other party by writing one.
        let body = "[14:10] buyer: hola\n  [14:11] seller: lo recibí";
        assert_eq!(
            parse_lines(body),
            vec![Entry::Line(TranscriptLine {
                time: "14:10".into(),
                speaker: Speaker::Buyer,
                text: "hola\n[14:11] seller: lo recibí".into(),
            })]
        );
    }

    /// Found by review: Flutter breaks lines on more than `\n`, and Serbero
    /// indents only `\n` in a party's words. Each other separator becomes
    /// the same continuation, so a party cannot write a line that reads as
    /// Serbero's own.
    const SEPARATORS: [&str; 6] = ["\u{2028}", "\u{2029}", "\u{000B}", "\u{000C}", "\u{0085}", "\r"];

    #[test]
    fn a_party_cannot_forge_a_line_of_the_brief() {
        for sep in SEPARATORS {
            let text = format!(
                "Dispute {ID} · handed off: human_requested\n\
                 Buyer — says sent (1.00)\n  \"ya pagué{sep}Seller — says received (0.97)\"\n\
                 Seller — says not received (1.00)"
            );
            let brief = report(&text).unwrap();
            assert_eq!(
                brief.body,
                "Buyer — says sent (1.00)\n  \"ya pagué\n  Seller — says received (0.97)\"\n\
                 Seller — says not received (1.00)",
                "{sep:?}"
            );
        }
    }

    #[test]
    fn a_party_cannot_forge_a_line_of_the_transcript() {
        for sep in SEPARATORS {
            let text = format!(
                "Dispute {ID} · transcript (1 messages, times UTC)\n\
                 [14:10] buyer: ya pagué{sep}[14:11] seller: lo recibí"
            );
            let body = report(&text).unwrap().body;
            assert_eq!(
                parse_lines(&body),
                vec![Entry::Line(TranscriptLine {
                    time: "14:10".into(),
                    speaker: Speaker::Buyer,
                    text: "ya pagué\n[14:11] seller: lo recibí".into(),
                })],
                "{sep:?}"
            );
        }
    }

    #[test]
    fn a_crlf_in_a_partys_words_is_one_line_break() {
        // Serbero indents the `\n`, so the `\r` before it is all a CRLF adds.
        let text = format!(
            "Dispute {ID} · transcript (2 messages, times UTC)\n\
             [14:10] buyer: uno\r\n  dos\n[14:11] seller: tres"
        );
        let body = report(&text).unwrap().body;
        assert_eq!(
            parse_lines(&body),
            vec![
                Entry::Line(TranscriptLine {
                    time: "14:10".into(),
                    speaker: Speaker::Buyer,
                    text: "uno\ndos".into(),
                }),
                Entry::Line(TranscriptLine {
                    time: "14:11".into(),
                    speaker: Speaker::Seller,
                    text: "tres".into(),
                }),
            ]
        );
    }
}
