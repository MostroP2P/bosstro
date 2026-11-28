import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/core/app.dart';
import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/features/notifications/providers/push_providers.dart';
import 'package:bosstro/features/notifications/services/push_core.dart';
import 'package:bosstro/features/settings/screens/notifications_screen.dart';
import 'package:bosstro/shared/widgets/mostro_modal.dart';
import 'package:bosstro/shared/widgets/warning_note.dart';

import '../../support/screen_harness.dart';

/// The fakes behind one pumped screen.
class _Push {
  _Push({bool enabled = false, PushWatchStatus? status}) {
    core = FakePushCore(calls, isEnabled: enabled);
    if (status != null) core.registered = status;
    messaging = FakePushMessaging(calls);
  }

  final calls = PushCalls();
  late final FakePushCore core;
  late final FakePushMessaging messaging;
}

/// Opens Settings → Notifications as the app does after its startup read of
/// the switch (`PushLifecycle`, which a pumped `BosstroApp` does not have).
Future<void> _open(
  WidgetTester tester,
  _Push push, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  Brightness brightness = Brightness.dark,
  double width = 400,
}) async {
  setSurface(tester, width: width, height: 800);
  await pumpApp(
    tester,
    location: AppRoute.settings,
    locale: locale,
    textScale: textScale,
    brightness: brightness,
    overrides: fakeCoreOverrides(push: push.core, messaging: push.messaging),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(BosstroApp)),
  );
  await container.read(pushControllerProvider.notifier).start();
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(switch (locale.languageCode) {
      'es' => 'Notificaciones',
      _ => 'Notifications',
    }),
  );
  await tester.pumpAndSettle();
  expect(find.byType(NotificationsScreen), findsOneWidget);
  push.calls.log.clear();
}

Switch _switch(WidgetTester tester) => tester.widget(find.byType(Switch));

void main() {
  /// DS-A11Y-4: the new screen at 2× text, 320 dp wide, in Spanish, in both
  /// themes, without overflow, in each of its states and with its dialogs.
  group('fits at 320 dp, 2× text, es', () {
    for (final brightness in Brightness.values) {
      for (final status in [null, ...PushWatchStatus.values]) {
        testWidgets('${status?.name ?? 'off'} (${brightness.name})', (
          tester,
        ) async {
          await _open(
            tester,
            _Push(enabled: status != null, status: status),
            locale: const Locale('es'),
            textScale: 2,
            brightness: brightness,
            width: 320,
          );

          expect(tester.takeException(), isNull);
          await tester.drag(find.byType(ListView), const Offset(0, -600));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('blocked by the OS (${brightness.name})', (tester) async {
        await _open(
          tester,
          _Push(enabled: true)..messaging.permission = false,
          locale: const Locale('es'),
          textScale: 2,
          brightness: brightness,
          width: 320,
        );

        expect(find.byType(WarningNote), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('the dialogs (${brightness.name})', (tester) async {
        for (final arrange in <void Function(_Push)>[
          (push) => push.messaging.permission = false,
          (push) => push.messaging.token = null,
        ]) {
          final push = _Push();
          arrange(push);
          await tester.pumpWidget(const SizedBox.shrink());
          await _open(
            tester,
            push,
            locale: const Locale('es'),
            textScale: 2,
            brightness: brightness,
            width: 320,
          );

          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();

          expect(find.byType(MostroDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    }
  });

  testWidgets('Notifications is a row of the App group that says Off', (
    tester,
  ) async {
    setSurface(tester, width: 400, height: 800);
    await pumpApp(
      tester,
      location: AppRoute.settings,
      locale: const Locale('en'),
      textScale: 1,
    );

    final row = tester.getTopLeft(find.text('Notifications')).dy;
    expect(row, greaterThan(tester.getTopLeft(find.text('Language')).dy));
    expect(row, lessThan(tester.getTopLeft(find.text('NODE')).dy));
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('where no push can be received there is no such row', (
    tester,
  ) async {
    setSurface(tester, width: 400, height: 800);
    await pumpApp(
      tester,
      location: AppRoute.settings,
      locale: const Locale('en'),
      textScale: 1,
      overrides: fakeCoreOverrides(canPush: false),
    );

    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('off: the switch is off, no status, and what it shares is said', (
    tester,
  ) async {
    await _open(tester, _Push());

    expect(_switch(tester).value, isFalse);
    expect(find.text('Active for this node.'), findsNothing);
    expect(find.textContaining('Google delivers'), findsOneWidget);
    expect(find.textContaining('IP address'), findsOneWidget);
    expect(find.textContaining("phone's language"), findsOneWidget);
  });

  testWidgets('turning it on asks the device and shows it active', (
    tester,
  ) async {
    final push = _Push();
    await _open(tester, push);

    await tester.tap(find.text('New disputes on this node'));
    await tester.pumpAndSettle();

    expect(push.calls.log, [
      'requestPermission',
      'setAutoInit(true)',
      'getToken',
      'core.setToken(token-1)',
      'core.setEnabled(true)',
      'tokenRefreshes',
    ]);
    expect(_switch(tester).value, isTrue);
    expect(find.text('Active for this node.'), findsOneWidget);
    expect(find.byType(MostroDialog), findsNothing);
    // And the Settings row follows.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('a refused permission says so and leaves it off', (tester) async {
    final push = _Push()..messaging.permission = false;
    await _open(tester, push);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Notifications are blocked'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_switch(tester).value, isFalse);
    expect(push.core.isEnabled, isFalse);
  });

  testWidgets('a phone that gets no token says so and leaves it off', (
    tester,
  ) async {
    final push = _Push()..messaging.token = null;
    await _open(tester, push);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Notifications are not available'), findsOneWidget);
    expect(find.textContaining('Google Play Services'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_switch(tester).value, isFalse);
  });

  testWidgets('turning it off tells the core and hides the status', (
    tester,
  ) async {
    final push = _Push(enabled: true);
    await _open(tester, push);
    expect(find.text('Active for this node.'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(push.calls.log.first, 'core.setEnabled(false)');
    expect(push.calls.log, contains('deleteToken'));
    expect(_switch(tester).value, isFalse);
    expect(find.text('Active for this node.'), findsNothing);
  });

  testWidgets('opening the screen reads the status again', (tester) async {
    final push = _Push(enabled: true);
    setSurface(tester, width: 400, height: 800);
    await pumpApp(
      tester,
      location: AppRoute.settings,
      locale: const Locale('en'),
      textScale: 1,
      overrides: fakeCoreOverrides(push: push.core, messaging: push.messaging),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BosstroApp)),
    );
    await container.read(pushControllerProvider.notifier).start();
    // The node stopped being covered since the app started.
    push.core.registered = PushWatchStatus.nodeNotTrusted;
    push.calls.log.clear();

    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();

    expect(push.calls.log, ['core.reconcile']);
    expect(find.byType(WarningNote), findsOneWidget);
  });

  testWidgets('on with the permission taken away warns, whatever the server '
      'holds', (tester) async {
    final push = _Push(enabled: true)..messaging.permission = false;
    await _open(tester, push);

    expect(find.byType(WarningNote), findsOneWidget);
    expect(find.textContaining('blocked in your phone'), findsOneWidget);
    expect(find.text('Active for this node.'), findsNothing);
    expect(_switch(tester).value, isTrue);
  });

  testWidgets('a status that settles by itself is read again while on screen', (
    tester,
  ) async {
    final push = _Push(
      enabled: true,
      status: PushWatchStatus.serverUnavailable,
    );
    await _open(tester, push);
    expect(find.textContaining('could not be reached'), findsOneWidget);

    // The core's own retry worked; nobody told the screen.
    push.core.registered = PushWatchStatus.registered;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Active for this node.'), findsOneWidget);
    // And a settled status is not asked for again.
    push.calls.log.clear();
    await tester.pump(const Duration(seconds: 11));
    expect(push.calls.log, isEmpty);
  });

  for (final (status, text, warns) in [
    (PushWatchStatus.registered, 'Active for this node.', false),
    (PushWatchStatus.waiting, 'Not active yet. Choose a node first.', false),
    (PushWatchStatus.rateLimited, 'asked to wait', false),
    (PushWatchStatus.serverUnavailable, 'could not be reached', false),
    (PushWatchStatus.tokenRefused, 'refused this phone', true),
    (PushWatchStatus.nodeNotTrusted, 'does not cover this node', true),
  ]) {
    testWidgets('${status.name} reads "$text"', (tester) async {
      await _open(tester, _Push(enabled: true, status: status));

      expect(find.textContaining(text), findsOneWidget);
      expect(
        find.byType(WarningNote),
        warns ? findsOneWidget : findsNothing,
        reason: 'only what the solver must act on warns',
      );
    });
  }
}
