import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/features/nodes/models/node_display.dart';

import '../../support/screen_harness.dart';

const _npub =
    'npub1serbero000000000000000000000000000000000000000000000000000x';

Future<FakeSettingsCore> _settings(
  WidgetTester tester, {
  FakeSettingsCore? settings,
  FakeNodesCore? nodes,
}) async {
  final core = settings ?? FakeSettingsCore();
  setSurface(tester, width: 400, height: 1600);
  await pumpApp(
    tester,
    location: AppRoute.settings,
    locale: const Locale('en'),
    textScale: 1,
    overrides: fakeCoreOverrides(settings: core, nodes: nodes),
  );
  return core;
}

void main() {
  testWidgets('the Serbero row reads "Not set" until a key is trusted', (
    tester,
  ) async {
    await _settings(tester);
    expect(find.text('Serbero'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('there is no Serbero row without an active node', (tester) async {
    await _settings(tester, nodes: FakeNodesCore());
    expect(find.text('Serbero'), findsNothing);
  });

  testWidgets('a pasted key is saved for the active node and shown', (
    tester,
  ) async {
    // Arrange
    final core = await _settings(tester);

    // Act
    await tester.tap(find.text('Serbero'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _npub);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Assert
    expect(core.serbero, {mostroNodePubkey: _npub});
    expect(find.text('Trust Serbero'), findsNothing, reason: 'closed');
    expect(find.text('Not set'), findsNothing);
  });

  testWidgets("the node's own key is refused under the field", (tester) async {
    // Arrange
    final core = await _settings(tester);
    core.serberoError = Exception('SerberoIsNode: the node');

    // Act
    await tester.tap(find.text('Serbero'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), mostroNodePubkey);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Assert
    expect(
      find.text("That is the node's own key, not Serbero's."),
      findsOneWidget,
    );
    expect(core.serbero, isEmpty);
  });

  testWidgets('a trusted key can be forgotten', (tester) async {
    // Arrange
    final core = await _settings(
      tester,
      settings: FakeSettingsCore(serbero: {mostroNodePubkey: _npub}),
    );
    expect(find.text('Not set'), findsNothing);

    // Act
    await tester.tap(find.text('Serbero'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop trusting'));
    await tester.pumpAndSettle();

    // Assert
    expect(core.serbero, isEmpty);
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('a save that ends after the dialog closed still refreshes', (
    tester,
  ) async {
    // Arrange
    final core = await _settings(tester);
    final write = Completer<void>();
    core.holdSerberoWrite = write;
    await tester.tap(find.text('Serbero'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _npub);
    await tester.tap(find.text('Save'));
    await tester.pump();

    // Act: dismissed while the write is pending, then the write ends.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Trust Serbero'), findsNothing, reason: 'dismissed');
    write.complete();
    await tester.pumpAndSettle();

    // Assert
    expect(core.serbero, {mostroNodePubkey: _npub});
    expect(find.text('Not set'), findsNothing, reason: 'the row refreshed');
  });
}
