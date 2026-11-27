import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/features/disputes/screens/disputes_screen.dart';
import 'package:bosstro/features/nodes/models/node_display.dart';
import 'package:bosstro/shared/widgets/mostro_modal.dart';

import '../../support/screen_harness.dart';

const _question = 'Turn on notifications of new disputes?';

/// The fakes behind one pumped app.
class _Push {
  final calls = PushCalls();
  late final core = FakePushCore(calls);
  late final messaging = FakePushMessaging(calls);
}

/// The node selector, as [location] shows it, with [active] as the node.
Future<void> _open(
  WidgetTester tester,
  _Push push, {
  String location = AppRoute.chooseNode,
  String? active,
  bool canPush = true,
  Locale locale = const Locale('en'),
  double textScale = 1,
  Brightness brightness = Brightness.dark,
  double width = 400,
}) async {
  setSurface(tester, width: width, height: 900);
  await pumpApp(
    tester,
    location: location,
    locale: locale,
    textScale: textScale,
    brightness: brightness,
    overrides: fakeCoreOverrides(
      nodes: FakeNodesCore(active: active),
      canPush: canPush,
      push: push.core,
      messaging: push.messaging,
    ),
  );
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the first node of an install offers notifications', (
    tester,
  ) async {
    final push = _Push();
    await _open(tester, push);

    await _tap(tester, 'Mostro Cuba');

    expect(find.text(_question), findsOneWidget);
    expect(find.textContaining('Google delivers'), findsOneWidget);
    expect(find.textContaining('IP address'), findsOneWidget);
    // Nothing was asked of the device yet.
    expect(push.calls.log, ['core.takeOffer']);
  });

  testWidgets('"Not now" leaves them off and asks the device nothing', (
    tester,
  ) async {
    final push = _Push();
    await _open(tester, push);
    await _tap(tester, 'Mostro Cuba');

    await _tap(tester, 'Not now');

    expect(push.calls.log, ['core.takeOffer']);
    expect(push.core.isEnabled, isFalse);
    expect(find.byType(DisputesScreen), findsOneWidget);
  });

  testWidgets('accepting turns them on and goes on to the disputes', (
    tester,
  ) async {
    final push = _Push();
    await _open(tester, push);
    await _tap(tester, 'Mostro Cuba');

    await _tap(tester, 'Turn on notifications');

    expect(push.calls.log, [
      'core.takeOffer',
      'requestPermission',
      'setAutoInit(true)',
      'getToken',
      'core.setToken(token-1)',
      'core.setEnabled(true)',
      'tokenRefreshes',
    ]);
    expect(find.byType(MostroDialog), findsNothing);
    expect(find.byType(DisputesScreen), findsOneWidget);
  });

  testWidgets('accepting and then refusing the permission says so', (
    tester,
  ) async {
    final push = _Push()..messaging.permission = false;
    await _open(tester, push);
    await _tap(tester, 'Mostro Cuba');

    await _tap(tester, 'Turn on notifications');

    expect(find.text('Notifications are blocked'), findsOneWidget);
    await _tap(tester, 'OK');
    expect(push.core.isEnabled, isFalse);
    expect(find.byType(DisputesScreen), findsOneWidget);
  });

  testWidgets('it is offered once: the next first pick asks nothing', (
    tester,
  ) async {
    final push = _Push()..core.offered = true;
    await _open(tester, push);

    await _tap(tester, 'Mostro Cuba');

    expect(find.text(_question), findsNothing);
    expect(find.byType(DisputesScreen), findsOneWidget);
  });

  testWidgets('a solver who has them on already is not asked', (tester) async {
    final push = _Push()..core.isEnabled = true;
    await _open(tester, push);

    await _tap(tester, 'Mostro Cuba');

    expect(find.text(_question), findsNothing);
  });

  testWidgets('switching node later offers nothing', (tester) async {
    // An install that updates has its node already: it never picks a first.
    final push = _Push();
    await _open(
      tester,
      push,
      location: AppRoute.settingsNode,
      active: mostroNodePubkey,
    );

    await _tap(tester, 'Mostro Cuba');

    expect(find.text(_question), findsNothing);
    expect(push.calls.log, isEmpty);
  });

  testWidgets('where no push can be received nothing is offered', (
    tester,
  ) async {
    final push = _Push();
    await _open(tester, push, canPush: false);

    await _tap(tester, 'Mostro Cuba');

    expect(find.text(_question), findsNothing);
    expect(push.calls.log, isEmpty);
    expect(find.byType(DisputesScreen), findsOneWidget);
  });

  /// DS-A11Y-4: the dialog at 2× text, 320 dp wide, in Spanish, in both
  /// themes, without overflow.
  for (final brightness in Brightness.values) {
    testWidgets('the offer fits at 320 dp, 2× text, es (${brightness.name})', (
      tester,
    ) async {
      await _open(
        tester,
        _Push(),
        locale: const Locale('es'),
        textScale: 2,
        brightness: brightness,
        width: 320,
      );

      await tester.scrollUntilVisible(
        find.text('Mostro Cuba'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _tap(tester, 'Mostro Cuba');

      expect(find.byType(MostroDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
