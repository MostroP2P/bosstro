import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/features/nodes/providers/node_providers.dart';
import 'package:bosstro/features/notifications/providers/push_providers.dart';
import 'package:bosstro/features/notifications/widgets/push_lifecycle.dart';
import 'package:bosstro/features/solver_key/providers/solver_key_providers.dart';
import 'package:bosstro/src/rust/api/solver.dart';

import '../../support/fake_push.dart';

const _key = SolverKeyInfo(npub: 'npub1one', publicKeyHex: 'aa');
const _otherKey = SolverKeyInfo(npub: 'npub1two', publicKeyHex: 'bb');

class _Node extends ActiveNodeNotifier {
  _Node(super.initial);

  void set(String? node) => state = node;
}

class _Key extends SolverKeyNotifier {
  _Key(super.initial);

  void set(SolverKeyInfo? key) => state = key;
}

void main() {
  late PushCalls calls;
  late _Node node;
  late _Key key;

  Future<void> pump(WidgetTester tester) async {
    calls = PushCalls();
    node = _Node('node-a');
    key = _Key(_key);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          canPushProvider.overrideWithValue(true),
          pushCoreProvider.overrideWithValue(FakePushCore(calls)),
          pushMessagingProvider.overrideWithValue(FakePushMessaging(calls)),
          activeNodeProvider.overrideWith(() => node),
          solverKeyProvider.overrideWith(() => key),
        ],
        child: const PushLifecycle(child: SizedBox()),
      ),
    );
    await tester.pump();
    expect(calls.log, ['core.enabled', 'core.reconcile'], reason: 'startup');
    calls.log.clear();
  }

  testWidgets('the watch is looked at again when the node changes', (
    tester,
  ) async {
    await pump(tester);

    node.set('node-b');
    await tester.pump();

    expect(calls.log, ['core.reconcile']);
  });

  testWidgets('and when the key is dropped or replaced', (tester) async {
    await pump(tester);

    key.set(null);
    await tester.pump();
    key.set(_otherKey);
    await tester.pump();

    expect(calls.log, ['core.reconcile', 'core.reconcile']);
  });

  testWidgets('and when the app returns from the background', (tester) async {
    await pump(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));

    expect(calls.log, ['core.reconcile']);
  });

  testWidgets('not for the flap of a dialog over the app', (tester) async {
    await pump(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));

    expect(calls.log, isEmpty);
  });
}
