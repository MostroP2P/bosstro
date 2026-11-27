import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bosstro/features/nodes/providers/node_providers.dart';
import 'package:bosstro/features/serbero/services/serbero_core.dart';
import 'package:bosstro/features/settings/providers/serbero_provider.dart';
import 'package:bosstro/features/solver_key/providers/solver_key_providers.dart';

/// The core behind Serbero's reports. Tests override it with a fake.
final serberoCoreProvider = Provider<SerberoCore>(
  (ref) => const RustSerberoCore(),
);

/// The disputes whose Serbero reports changed on the active node.
final serberoUpdatesProvider = StreamProvider<String>(
  (ref) => ref.watch(serberoCoreProvider).updates(),
);

/// What Serbero sent about one dispute, live: read again when a report of
/// it arrives, or the node, the key or the trusted Serbero changes. Null
/// without an active node or a loaded key.
final serberoMediationProvider = AsyncNotifierProvider.autoDispose
    .family<SerberoMediationNotifier, SerberoMediation?, String>(
      SerberoMediationNotifier.new,
    );

class SerberoMediationNotifier
    extends AutoDisposeFamilyAsyncNotifier<SerberoMediation?, String> {
  SerberoCore get _core => ref.read(serberoCoreProvider);

  /// Advanced by every build and reload: a read that ends after a newer one
  /// started is dropped, so an older node's or key's report never replaces
  /// the current one.
  int _generation = 0;

  @override
  Future<SerberoMediation?> build(String arg) async {
    _generation++;
    ref.onDispose(() => _generation++);
    ref.watch(activeNodeProvider);
    ref.watch(solverKeyProvider);
    // Before any await, so a report that arrives meanwhile is not missed.
    ref.listen(serberoUpdatesProvider, (_, next) {
      final disputeId = next.valueOrNull;
      if (disputeId == arg || disputeId == '') unawaited(_reload());
    });
    // Read once the trusted key is known, so a mediation is never read
    // before the trust it depends on, and the first read is not repeated.
    await ref.watch(serberoNpubProvider.future);
    return _core.mediation(arg);
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      // After the build under way, if any: its older read must not land
      // after this one.
      await future.then((_) {}, onError: (_) {});
      if (generation != _generation) return;
      final mediation = await _core.mediation(arg);
      if (generation == _generation) state = AsyncData(mediation);
    } catch (e) {
      debugPrint('[serbero] not read from storage: $e');
    }
  }
}
