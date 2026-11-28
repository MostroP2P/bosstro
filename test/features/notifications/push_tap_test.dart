import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/core/app.dart';
import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/features/disputes/screens/disputes_screen.dart';
import 'package:bosstro/features/notifications/providers/push_providers.dart';
import 'package:bosstro/features/settings/screens/about_screen.dart';
import 'package:bosstro/features/solver_key/screens/welcome_screen.dart';

import '../../support/screen_harness.dart';

/// The app at [location] with notifications on, as after its startup read
/// of the switch (`PushLifecycle`, which a pumped `BosstroApp` does not
/// have). Returns the fake device.
Future<FakePushMessaging> _open(
  WidgetTester tester,
  String location, {
  bool signedIn = true,
}) async {
  final calls = PushCalls();
  final messaging = FakePushMessaging(calls);
  setSurface(tester, width: 400, height: 800);
  await pumpApp(
    tester,
    location: location,
    locale: const Locale('en'),
    textScale: 1,
    overrides: fakeCoreOverrides(
      signedIn: signedIn,
      push: FakePushCore(calls, isEnabled: true),
      messaging: messaging,
    ),
  );
  await ProviderScope.containerOf(
    tester.element(find.byType(BosstroApp)),
  ).read(pushControllerProvider.notifier).start();
  await tester.pumpAndSettle();
  return messaging;
}

void main() {
  testWidgets('a tap on the notification opens the pending disputes', (
    tester,
  ) async {
    // Arrange: deep in another tab, over the shell.
    final messaging = await _open(tester, AppRoute.about);
    expect(find.byType(AboutScreen), findsOneWidget);

    // Act
    messaging.taps.add(null);
    await tester.pumpAndSettle();

    // Assert
    expect(find.byType(AboutScreen), findsNothing);
    expect(find.byType(DisputesScreen), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);
  });

  testWidgets('from another part of the disputes, it opens Pending', (
    tester,
  ) async {
    final messaging = await _open(tester, AppRoute.closed);

    messaging.taps.add(null);
    await tester.pumpAndSettle();

    final router = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      router.routerConfig!.routeInformationProvider!.value.uri.path,
      AppRoute.pending,
    );
  });

  testWidgets('already on Pending, a tap changes nothing', (tester) async {
    final messaging = await _open(tester, AppRoute.pending);

    messaging.taps.add(null);
    await tester.pumpAndSettle();

    expect(find.byType(DisputesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a key the tap ends at Welcome, as any location', (
    tester,
  ) async {
    final messaging = await _open(tester, AppRoute.welcome, signedIn: false);

    messaging.taps.add(null);
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(DisputesScreen), findsNothing);
  });
}
