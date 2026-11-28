import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/features/notifications/providers/push_providers.dart';
import 'package:bosstro/features/notifications/services/push_core.dart';
import '../../support/fake_push.dart';

void main() {
  late PushCalls calls;
  late FakePushMessaging messaging;
  late FakePushCore core;

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
    calls = PushCalls();
    messaging = FakePushMessaging(calls);
    core = FakePushCore(calls);
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
    ('gives none', (FakePushMessaging m) => m.token = null),
    ('gives an empty one', (FakePushMessaging m) => m.token = ''),
    (
      'fails',
      (FakePushMessaging m) => m.tokenError = StateError('no services'),
    ),
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
      // With the token the core kept, before Google is asked.
      'core.reconcile',
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

    expect(calls.log, [
      'core.enabled',
      'tokenRefreshes',
      'core.reconcile',
      'getToken',
    ]);
    expect(
      c.read(pushControllerProvider),
      const PushState(enabled: true, status: PushWatchStatus.registered),
    );
  });

  testWidgets('at startup the switch shows on before Google answers', (
    tester,
  ) async {
    core.isEnabled = true;
    messaging.tokenLater = Completer();
    final c = container();
    final controller = c.read(pushControllerProvider.notifier);

    final starting = controller.start();
    await tester.pump();

    // On, with the status of the token the core kept.
    expect(
      c.read(pushControllerProvider),
      const PushState(enabled: true, status: PushWatchStatus.registered),
    );
    // And the switch answers meanwhile: turning it off does not wait for
    // the token.
    await controller.disable();
    expect(core.isEnabled, isFalse);

    // Google answers the request startup made, with notifications off by
    // now: the token it issued is deleted, not left behind.
    calls.log.clear();
    messaging.tokenLater!.complete('token-1');
    await starting;
    expect(calls.log, ['deleteToken']);
  });

  test('a core that fails to take the token leaves the switch on', () async {
    core.isEnabled = true;
    core.setTokenError = StateError('storage');
    final c = container();

    await c.read(pushControllerProvider.notifier).start();

    // Off here with the core on could not be turned off from the app.
    expect(c.read(pushControllerProvider).enabled, isTrue);
  });

  test('a stored state that was lost has the device token deleted', () async {
    // The core started over: its switch reads off, and Google still holds
    // the token of when it was on.
    core.stateLost = true;
    final c = container();

    await c.read(pushControllerProvider.notifier).start();

    expect(calls.log, [
      'core.enabled',
      'deleteToken',
      'setAutoInit(false)',
      'core.reconcile',
    ]);
    expect(c.read(pushControllerProvider).enabled, isFalse);
    // Said once.
    calls.log.clear();
    await c.read(pushControllerProvider.notifier).reconcile();
    expect(calls.log, ['core.reconcile']);
  });

  test(
    'a switch that could not be read at startup is read at the next look',
    () async {
      core.isEnabled = true;
      core.enabledError = StateError('StorageUnavailable');
      final c = container();
      final controller = c.read(pushControllerProvider.notifier);

      await controller.start();
      // Not taken for off: nothing is known yet.
      expect(c.read(pushControllerProvider), const PushState());

      core.enabledError = null;
      await controller.reconcile();

      expect(
        c.read(pushControllerProvider),
        const PushState(enabled: true, status: PushWatchStatus.registered),
      );
      expect(calls.log, contains('core.setToken(token-1)'));
    },
  );

  test('on, with the permission taken away: it says blocked', () async {
    core.isEnabled = true;
    messaging.permission = false;
    final c = container();
    final controller = c.read(pushControllerProvider.notifier);

    await controller.start();
    expect(c.read(pushControllerProvider).blocked, isTrue);

    // Given back in the system's settings: seen at the next look.
    messaging.permission = true;
    await controller.reconcile();
    expect(c.read(pushControllerProvider).blocked, isFalse);
  });

  test('off is never blocked, and the permission is not even read', () async {
    messaging.permission = false;
    final c = container();
    final controller = c.read(pushControllerProvider.notifier);

    await controller.start();
    await controller.reconcile();

    expect(c.read(pushControllerProvider).blocked, isFalse);
    expect(calls.log, ['core.enabled', 'core.reconcile', 'core.reconcile']);
  });

  testWidgets('a token that comes after "not available" is deleted', (
    tester,
  ) async {
    messaging.tokenLater = Completer();
    final c = container();

    final enabling = c.read(pushControllerProvider.notifier).enable();
    await tester.pump(PushController.tokenTimeout);
    expect(await enabling, PushEnableResult.unavailable);
    expect(calls.log, isNot(contains('deleteToken')));

    // Google answers at last, with notifications off.
    messaging.tokenLater!.complete('token-late');
    await tester.pump();

    expect(calls.log.last, 'deleteToken');
    expect(calls.log, isNot(contains('core.setToken(token-late)')));
    expect(core.isEnabled, isFalse);
  });

  testWidgets(
    'a token that comes late with notifications on goes to the core',
    (tester) async {
      core.isEnabled = true;
      messaging.tokenLater = Completer();
      final c = container();

      final starting = c.read(pushControllerProvider.notifier).start();
      await tester.pump(PushController.tokenTimeout);
      await starting;

      messaging.tokenLater!.complete('token-late');
      await tester.pump();

      expect(calls.log.last, 'core.setToken(token-late)');
      expect(calls.log, isNot(contains('deleteToken')));
    },
  );

  test(
    'a core that refuses the token when turning on leaves none behind',
    () async {
      core.setTokenError = StateError('storage');
      final c = container();

      final result = await c.read(pushControllerProvider.notifier).enable();

      expect(result, PushEnableResult.unavailable);
      expect(
        calls.log,
        containsAllInOrder(['deleteToken', 'setAutoInit(false)']),
      );
      expect(c.read(pushControllerProvider).enabled, isFalse);
    },
  );

  test('a token that replaces the device\'s goes to the core', () async {
    final c = container();
    await c.read(pushControllerProvider.notifier).enable();
    calls.log.clear();

    messaging.refreshes.add('token-2');
    await pumpEventQueue();

    expect(calls.log, ['core.setToken(token-2)']);
  });

  test('a tap on a notification is passed on while they are on', () async {
    final c = container();
    await c.read(pushControllerProvider.notifier).enable();

    messaging.taps.add(null);
    messaging.taps.add(null);
    await pumpEventQueue();

    expect(c.read(newDisputeTapsProvider), 2);
  });

  test('with notifications off, taps are not followed', () async {
    final c = container();
    final controller = c.read(pushControllerProvider.notifier);

    await controller.start();
    expect(messaging.tapsFollowed, isFalse, reason: 'it would start Firebase');

    await controller.enable();
    await controller.disable();
    messaging.taps.add(null);
    await pumpEventQueue();
    expect(c.read(newDisputeTapsProvider), 0);
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
