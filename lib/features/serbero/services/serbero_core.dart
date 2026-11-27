import 'package:bosstro/src/rust/api/serbero.dart' as serbero_api;
import 'package:bosstro/src/rust/api/serbero.dart' show SerberoMediation;

export 'package:bosstro/src/rust/api/serbero.dart'
    show
        SerberoHeadline,
        SerberoLine,
        SerberoMediation,
        SerberoNote,
        SerberoSpeaker,
        SerberoUpdateView;

/// The Rust core's Serbero reports (`rust/src/api/serbero.rs`): what
/// Serbero, the assistant Read solver, sent this solver key about a dispute
/// when it handed it off (D13). Read only. An interface so widget tests,
/// which run without the native library, drive a fake.
abstract interface class SerberoCore {
  /// What Serbero sent about [disputeId] on the active node, as stored; null
  /// without an active node or a loaded key.
  Future<SerberoMediation?> mediation(String disputeId);

  /// The dispute ids whose reports changed on the active node; `''` when
  /// every shown one should be read again.
  Stream<String> updates();
}

class RustSerberoCore implements SerberoCore {
  const RustSerberoCore();

  @override
  Future<SerberoMediation?> mediation(String disputeId) =>
      serbero_api.serberoMediation(disputeId: disputeId);

  @override
  Stream<String> updates() async* {
    final stream = await serbero_api.onSerberoUpdates();
    while (true) {
      final next = await stream.next();
      if (next == null) return;
      yield next;
    }
  }
}

extension SerberoMediationShown on SerberoMediation {
  /// Whether Serbero sent anything about this dispute.
  bool get isBlank =>
      brief == null &&
      transcriptTotal == 0 &&
      updates.isEmpty &&
      finalReport == null;

  /// When the newest report was sent (unix seconds); null when blank.
  int? get lastSentAt {
    final times = [
      if (brief case final note?) note.sentAt.toInt(),
      if (transcriptSentAt case final at?) at.toInt(),
      for (final update in updates) update.sentAt.toInt(),
      if (finalReport case final note?) note.sentAt.toInt(),
    ];
    if (times.isEmpty) return null;
    return times.reduce((a, b) => a > b ? a : b);
  }
}
