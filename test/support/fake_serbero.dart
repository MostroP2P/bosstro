import 'dart:async';

import 'package:bosstro/features/serbero/services/serbero_core.dart';

/// Serbero's reports in Dart: what the test stores per dispute, and a
/// stream the test pushes updates into.
class FakeSerberoCore implements SerberoCore {
  /// Null: no active node or key, so nothing is this key's.
  bool active = true;

  /// The stored mediations, by dispute id (absent: Serbero sent nothing).
  final Map<String, SerberoMediation> mediations = {};

  final _updates = StreamController<String>.broadcast();

  /// How many times the stored mediation was read.
  int reads = 0;

  /// Holds the next read until the test completes it, then answers with
  /// what the completer is completed with.
  Completer<SerberoMediation?>? holdNext;

  /// Announce that [disputeId]'s reports changed.
  void push(String disputeId) => _updates.add(disputeId);

  @override
  Future<SerberoMediation?> mediation(String disputeId) async {
    reads++;
    final held = holdNext;
    if (held != null) {
      holdNext = null;
      return held.future;
    }
    if (!active) return null;
    return mediations[disputeId] ?? blankMediation(disputeId);
  }

  @override
  Stream<String> updates() => _updates.stream;
}

SerberoMediation blankMediation(String disputeId) => SerberoMediation(
  disputeId: disputeId,
  transcript: const [],
  transcriptParts: 0,
  transcriptTotal: 0,
  updates: const [],
);

SerberoLine serberoLine(
  SerberoSpeaker? speaker,
  String text, {
  String time = '14:10',
  int? at,
}) => SerberoLine(
  time: speaker == null ? '' : time,
  at: at,
  speaker: speaker,
  text: text,
);

/// A brief or a final report as the core hands it over: [subject] split into
/// its headline and what follows the colon, as `rust/src/serbero/view.rs`.
SerberoNote serberoNote(String subject, String body, {required int sentAt}) {
  final (headline, detail) = switch (subject.split(': ')) {
    ['handed off', final d] => (SerberoHeadline.handedOff, d),
    ['guidance sent', final d] => (SerberoHeadline.guidanceSent, d),
    ['resolved', final d] => (SerberoHeadline.resolved, d),
    _ => (SerberoHeadline.other, ''),
  };
  return SerberoNote(
    subject: subject,
    headline: headline,
    detail: detail,
    body: body,
    sentAt: sentAt,
  );
}
