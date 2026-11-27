import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/features/notifications/providers/push_providers.dart';
import 'package:bosstro/features/notifications/services/push_core.dart';
import 'package:bosstro/features/notifications/services/push_messaging.dart';

/// Everything asked of the device and of the core, in order, in one list:
/// the order between the two is what the tests check.
class Calls {
  final log = <String>[];
}

class FakeMessaging implements PushMessaging {
  FakeMessaging(this.calls);

  final Calls calls;
  bool permission = true;
  String? token = 'token-1';
  Object? tokenError;
  bool tokenNeverAnswers = false;
  final refreshes = StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async {
    calls.log.add('requestPermission');
    return permission;
  }

  @override
  Future<String?> getToken() {
    calls.log.add('getToken');
    if (tokenNeverAnswers) return Completer<String?>().future;
    if (tokenError != null) return Future.error(tokenError!);
    return Future.value(token);
  }

  @override
  Future<void> deleteToken() async => calls.log.add('deleteToken');

  @override
  Future<void> setAutoInit(bool enabled) async =>
      calls.log.add('setAutoInit($enabled)');

  @override
  Stream<String> tokenRefreshes() {
    calls.log.add('tokenRefreshes');
    return refreshes.stream;
  }
}

class FakeCore implements PushCore {
  FakeCore(this.calls, {this.isEnabled = false});

  final Calls calls;
  bool isEnabled;
  PushWatchStatus registered = PushWatchStatus.registered;

  PushWatchStatus get _status => isEnabled ? registered : PushWatchStatus.off;

  @override
  Future<bool> enabled() async {
    calls.log.add('core.enabled');
    return isEnabled;
  }

  @override
  Future<PushWatchStatus> setEnabled(bool enabled) async {
    calls.log.add('core.setEnabled($enabled)');
    isEnabled = enabled;
    return _status;
  }

  @override
  Future<PushWatchStatus> setToken(String? token) async {
    calls.log.add('core.setToken($token)');
    return _status;
  }

  @override
  Future<PushWatchStatus> reconcile() async {
    calls.log.add('core.reconcile');
    return _status;
  }
}

void main() {
  late Calls calls;
  late FakeMessaging messaging;
  late FakeCore core;

  ProviderContainer container({bool canPush = true}) {
    final container = ProviderContainer(
      overrides: [
        canPushProvider.overrideWithValue(canPush),
        pushCoreProvider.overrideWithValue(core),
        pushMessagingProvider.overrideWithValue(messaging),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    calls = Calls();
    messaging = FakeMessaging(calls);
    core = FakeCore(calls);
  });

  test('with notifications off, startup asks nothing of the device', () async {
    final c = container();

    await c.read(pushControllerProvider.notifier).start();

    // No Firebase call at all: nothing reaches Google before the solver
    // accepts. The core is still asked, for an unwatch it may owe.
    expect(calls.log, ['core.enabled', 'core.reconcile']);
    expect(
      c.read(pushControllerProvider),
      const PushState(status: PushWatchStatus.off),
    );
  });

  test(
    'turning them on asks the permission, then the token, then the core',
    () async {
      final c = container();

      final result = await c.read(pushControllerProvider.notifier).enable();

      expect(result, PushEnableResult.enabled);
      expect(calls.log, [
        'requestPermission',
        'setAutoInit(true)',
        'getToken',
        'core.setToken(token-1)',
        'core.setEnabled(true)',
        'tokenRefreshes',
      ]);
      expect(
        c.read(pushControllerProvider),
        const PushState(enabled: true, status: PushWatchStatus.registered),
      );
    },
  );

  test('a refused permission asks Google for nothing and stays off', () async {
    messaging.permission = false;
    final c = container();

    final result = await c.read(pushControllerProvider.notifier).enable();

    expect(result, PushEnableResult.permissionDenied);
    expect(calls.log, ['requestPermission']);
    expect(c.read(pushControllerProvider).enabled, isFalse);
  });

  for (final (name, arrange) in [
    ('gives none', (FakeMessaging m) => m.token = null),
    ('gives an empty one', (FakeMessaging m) => m.token = ''),
    ('fails', (FakeMessaging m) => m.tokenError = StateError('no services')),
  ]) {
    test('a device whose token request $name stays off, as it was', () async {
      arrange(messaging);
      final c = container();

      final result = await c.read(pushControllerProvider.notifier).enable();

      expect(result, PushEnableResult.unavailable);
      expect(calls.log, [
        'requestPermission',
        'setAutoInit(true)',
        'getToken',
        'setAutoInit(false)',
      ]);
      expect(c.read(pushControllerProvider).enabled, isFalse);
    });
  }

  testWidgets('a device that never answers with a token stays off', (
    tester,
  ) async {
    // Without Google Play Services the request may never end.
    messaging.tokenNeverAnswers = true;
    final c = container();

    final pending = c.read(pushControllerProvider.notifier).enable();
    await tester.pump(PushController.tokenTimeout);

    expect(await pending, PushEnableResult.unavailable);
    expect(calls.log.last, 'setAutoInit(false)');
    expect(core.isEnabled, isFalse);
  });

  test(
    'turning them off tells the server before the token is deleted',
    () async {
      final c = container();
      final controller = c.read(pushControllerProvider.notifier);
      await controller.enable();
      calls.log.clear();

      await controller.disable();

      expect(calls.log, [
        'core.setEnabled(false)',
        'deleteToken',
        'setAutoInit(false)',
        'core.setToken(null)',
      ]);
      expect(
        c.read(pushControllerProvider),
        const PushState(status: PushWatchStatus.off),
      );
    },
  );

  test('with notifications on, startup hands the core the token', () async {
    core.isEnabled = true;
    final c = container();

    await c.read(pushControllerProvider.notifier).start();

    expect(calls.log, [
      'core.enabled',
      'tokenRefreshes',
      'getToken',
      'core.setToken(token-1)',
    ]);
    expect(
      c.read(pushControllerProvider),
      const PushState(enabled: true, status: PushWatchStatus.registered),
    );
  });

  test('a startup with no token works with the one the core kept', () async {
    core.isEnabled = true;
    messaging.tokenError = StateError('offline');
    final c = container();

    await c.read(pushControllerProvider.notifier).start();

    expect(calls.log.last, 'core.reconcile');
    expect(c.read(pushControllerProvider).enabled, isTrue);
  });

  test('a token that replaces the device\'s goes to the core', () async {
    final c = container();
    await c.read(pushControllerProvider.notifier).enable();
    calls.log.clear();

    messaging.refreshes.add('token-2');
    await pumpEventQueue();

    expect(calls.log, ['core.setToken(token-2)']);
  });

  test('once off, a token change is not followed any more', () async {
    final c = container();
    final controller = c.read(pushControllerProvider.notifier);
    await controller.enable();
    await controller.disable();
    calls.log.clear();

    messaging.refreshes.add('token-2');
    await pumpEventQueue();

    expect(calls.log, isEmpty);
  });

  test('a reconcile keeps the switch and reads the status again', () async {
    final c = container();
    final controller = c.read(pushControllerProvider.notifier);
    await controller.enable();
    core.registered = PushWatchStatus.nodeNotTrusted;

    await controller.reconcile();

    expect(
      c.read(pushControllerProvider),
      const PushState(enabled: true, status: PushWatchStatus.nodeNotTrusted),
    );
  });

  test('two operations asked at once run one after the other', () async {
    final c = container();
    final controller = c.read(pushControllerProvider.notifier);

    await Future.wait([controller.enable(), controller.disable()]);

    expect(
      calls.log.indexOf('core.setEnabled(true)'),
      lessThan(calls.log.indexOf('core.setEnabled(false)')),
    );
    expect(calls.log.last, 'core.setToken(null)');
    expect(c.read(pushControllerProvider).enabled, isFalse);
  });

  test('where pushes cannot be received nothing is touched', () async {
    final c = container(canPush: false);
    final controller = c.read(pushControllerProvider.notifier);

    await controller.start();
    expect(await controller.enable(), PushEnableResult.unavailable);
    await controller.disable();
    await controller.reconcile();

    expect(calls.log, isEmpty);
  });

  test('nothing the controller logs or shows holds the token', () async {
    final printed = <String>[];
    final c = container();
    await runZoned(
      () => c.read(pushControllerProvider.notifier).enable(),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed.join('\n'), isNot(contains('token-1')));
    expect(
      c.read(pushControllerProvider).toString(),
      isNot(contains('token-1')),
    );
  });
}
