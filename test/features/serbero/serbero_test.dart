import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/features/chat/services/chat_core.dart';
import 'package:bosstro/features/chat/widgets/chat_bubble.dart';
import 'package:bosstro/features/nodes/models/node_display.dart';
import 'package:bosstro/features/serbero/screens/serbero_screen.dart';
import 'package:bosstro/features/serbero/services/serbero_core.dart';
import 'package:bosstro/features/serbero/widgets/serbero_card.dart';
import 'package:bosstro/features/settings/providers/serbero_provider.dart';

import '../../support/screen_harness.dart';

const _a = '8a0c1e64-0d3b-4c39-9a3e-3a1f1f0f4b2c';
const _sent = 1700000000;
const _npub = 'npub1serbero';

SerberoNote _note(String subject, String body, {int sentAt = _sent}) =>
    serberoNote(subject, body, sentAt: sentAt);

/// A handoff as Serbero sends it: the brief and a transcript in two parts,
/// one of them received.
SerberoMediation _handedOff({
  List<SerberoLine>? transcript,
  int parts = 2,
  int total = 2,
  List<SerberoUpdateView> updates = const [],
  SerberoNote? finalReport,
}) => SerberoMediation(
  disputeId: _a,
  brief: _note(
    'handed off: conflicting_claims',
    'Topic: payment_not_confirmed (0.91) · rounds: 2 · duration: 14 min',
  ),
  transcript:
      transcript ??
      [
        serberoLine(SerberoSpeaker.buyer, 'Ya envié el pago desde mi banco.'),
        serberoLine(
          SerberoSpeaker.serberoToSeller,
          '¿Puedes revisar si recibiste el pago?',
          time: '14:11',
        ),
        serberoLine(
          SerberoSpeaker.seller,
          'No me ha llegado nada.',
          time: '14:20',
        ),
      ],
  transcriptParts: parts,
  transcriptTotal: total,
  updates: updates,
  finalReport: finalReport,
);

Future<void> _pumpDetail(
  WidgetTester tester, {
  required FakeSerberoCore serbero,
  FakeSettingsCore? settings,
  Brightness brightness = Brightness.dark,
}) async {
  setSurface(tester);
  final disputes =
      FakeDisputesCore()
        ..held = [sampleTaken(id: _a)]
        ..details[_a] = sampleDetail(id: _a);
  final chat =
      FakeChatCore()
        ..set(_a, ChatParty.buyer)
        ..set(_a, ChatParty.seller);
  await pumpApp(
    tester,
    location: AppRoute.disputeDetail(_a),
    brightness: brightness,
    overrides: fakeCoreOverrides(
      disputes: disputes,
      chat: chat,
      serbero: serbero,
      settings:
          settings ?? FakeSettingsCore(serbero: {mostroNodePubkey: _npub}),
    ),
  );
}

Future<void> _scrollInfoTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable:
        find
            .descendant(
              of: find.byType(IndexedStack),
              matching: find.byType(Scrollable),
            )
            .first,
  );
  await tester.pumpAndSettle();
}

/// Scroll Serbero's screen until [finder] is on screen.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable:
        find
            .descendant(
              of: find.byType(SerberoScreen),
              matching: find.byType(Scrollable),
            )
            .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openMediation(WidgetTester tester) async {
  final read = find.text('Leer la mediación de Serbero');
  await _scrollInfoTo(tester, read);
  await tester.tap(read);
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    final theme = brightness.name;

    testWidgets('$theme: the card leads to the brief and the conversation, '
        'at 2x text and 320 dp, in Spanish', (tester) async {
      // Arrange
      final serbero = FakeSerberoCore()..mediations[_a] = _handedOff();

      // Act
      await _pumpDetail(tester, serbero: serbero, brightness: brightness);
      await _scrollInfoTo(tester, find.byType(SerberoCard));
      expect(find.text('Mediación de Serbero'), findsOneWidget);
      await _openMediation(tester);

      // Assert
      expect(find.byType(SerberoScreen), findsOneWidget);
      expect(find.text('Resumen'), findsOneWidget);
      expect(
        find.text(
          'Topic: payment_not_confirmed (0.91) · rounds: 2 · duration: 14 min',
        ),
        findsOneWidget,
      );
      await _scrollTo(tester, find.text('Ya envié el pago desde mi banco.'));
      expect(find.text('Comprador'), findsWidgets);
      await _scrollTo(tester, find.text('No me ha llegado nada.'));
      expect(find.text('Serbero → vendedor'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow');
    });
  }

  testWidgets('a missing part is said under the conversation', (tester) async {
    final serbero =
        FakeSerberoCore()..mediations[_a] = _handedOff(parts: 1, total: 2);
    await _pumpDetail(tester, serbero: serbero);
    await _openMediation(tester);
    await _scrollTo(tester, find.text('1 de 2 partes recibidas'));
    expect(find.text('1 de 2 partes recibidas'), findsOneWidget);
  });

  testWidgets('no warning when every part arrived', (tester) async {
    final serbero = FakeSerberoCore()..mediations[_a] = _handedOff();
    await _pumpDetail(tester, serbero: serbero);
    await _openMediation(tester);
    await _scrollTo(tester, find.text('No me ha llegado nada.'));
    expect(find.textContaining('partes recibidas'), findsNothing);
  });

  testWidgets('updates after the handoff and the final report are shown', (
    tester,
  ) async {
    final serbero =
        FakeSerberoCore()
          ..mediations[_a] = _handedOff(
            updates: [
              SerberoUpdateView(
                sentAt: _sent + 600,
                lines: [
                  serberoLine(
                    SerberoSpeaker.seller,
                    'Ahora sí me llegó.',
                    time: '14:40',
                  ),
                ],
              ),
            ],
            finalReport: _note(
              'resolved: settled',
              'outcome: released to buyer',
              sentAt: _sent + 1200,
            ),
          );
    await _pumpDetail(tester, serbero: serbero);
    await _openMediation(tester);
    await _scrollTo(tester, find.text('Tras la cesión'));
    await _scrollTo(tester, find.text('Ahora sí me llegó.'));
    expect(find.text('Ahora sí me llegó.'), findsOneWidget);
    await _scrollTo(tester, find.text('outcome: released to buyer'));
    expect(find.text('Informe final'), findsOneWidget);
  });

  testWidgets('a report that arrives while the screen is open shows', (
    tester,
  ) async {
    // Arrange
    final serbero = FakeSerberoCore()..mediations[_a] = _handedOff();
    await _pumpDetail(tester, serbero: serbero);
    await _openMediation(tester);
    expect(find.text('Tras la cesión'), findsNothing);

    // Act
    serbero.mediations[_a] = _handedOff(
      updates: [
        SerberoUpdateView(
          sentAt: _sent + 600,
          lines: [serberoLine(SerberoSpeaker.buyer, 'Sigo esperando.')],
        ),
      ],
    );
    serbero.push(_a);
    await tester.pumpAndSettle();

    // Assert
    await _scrollTo(tester, find.text('Sigo esperando.'));
    expect(find.text('Sigo esperando.'), findsOneWidget);
  });

  testWidgets('without a report the card says when one arrives, and has no '
      'action', (tester) async {
    await _pumpDetail(tester, serbero: FakeSerberoCore());
    await _scrollInfoTo(tester, find.byType(SerberoCard));
    expect(
      find.textContaining('Serbero no ha enviado nada sobre esta disputa.'),
      findsOneWidget,
    );
    expect(find.text('Leer la mediación de Serbero'), findsNothing);
  });

  testWidgets('without a trusted Serbero the card points to Settings', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      serbero: FakeSerberoCore(),
      settings: FakeSettingsCore(),
    );
    await _scrollInfoTo(tester, find.byType(SerberoCard));
    expect(
      find.text(
        'Configura la clave de Serbero en Ajustes para leer sus informes de '
        'mediación.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no card when the dispute is not this key\'s', (tester) async {
    await _pumpDetail(tester, serbero: FakeSerberoCore()..active = false);
    await _scrollInfoTo(tester, find.byType(SerberoCard));
    expect(find.text('Mediación de Serbero'), findsNothing);
  });

  testWidgets('the window is secure while the mediation is open', (
    tester,
  ) async {
    final serbero = FakeSerberoCore()..mediations[_a] = _handedOff();
    await _pumpDetail(tester, serbero: serbero);
    await _openMediation(tester);
    expect(find.byType(SerberoScreen), findsOneWidget);
    // SecureWindow wraps the screen, as the observer's.
    expect(
      find.ancestor(
        of: find.text('Resumen'),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'SecureWindow',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the handoff reason and the outcome read in words', (
    tester,
  ) async {
    final serbero =
        FakeSerberoCore()
          ..mediations[_a] = SerberoMediation(
            disputeId: _a,
            brief: _note('handed off: human_requested', 'Topic: x'),
            transcript: const [],
            transcriptParts: 0,
            transcriptTotal: 0,
            updates: const [],
            finalReport: _note('resolved: settled', 'mediation: yes'),
          );
    await _pumpDetail(tester, serbero: serbero);
    await _openMediation(tester);
    expect(
      find.textContaining('Cedida: una parte pidió hablar con una persona'),
      findsOneWidget,
    );
    expect(find.textContaining('human_requested'), findsNothing);
    await _scrollTo(tester, find.text('mediation: yes'));
    expect(find.textContaining('Resuelta: '), findsOneWidget);
    expect(find.textContaining('resolved: settled'), findsNothing);
  });

  testWidgets('a reason this app does not know is shown as Serbero wrote it', (
    tester,
  ) async {
    final serbero =
        FakeSerberoCore()
          ..mediations[_a] = SerberoMediation(
            disputeId: _a,
            brief: _note('handed off: new_reason', 'Topic: x'),
            transcript: const [],
            transcriptParts: 0,
            transcriptTotal: 0,
            updates: const [],
          );
    await _pumpDetail(tester, serbero: serbero);
    await _openMediation(tester);
    expect(find.textContaining('Cedida: new_reason'), findsOneWidget);
  });

  testWidgets('a message shows when it was written in local time', (
    tester,
  ) async {
    const at = _sent - 120;
    final serbero =
        FakeSerberoCore()
          ..mediations[_a] = _handedOff(
            transcript: [
              serberoLine(
                SerberoSpeaker.buyer,
                'Ya pagué.',
                time: '99:99',
                at: at,
              ),
            ],
            parts: 1,
            total: 1,
          );
    await _pumpDetail(tester, serbero: serbero);
    await _openMediation(tester);
    await _scrollTo(tester, find.text('Ya pagué.'));
    expect(find.text('99:99'), findsNothing, reason: 'not the UTC stamp');
    expect(find.text(chatTimeLabel(at, DateTime.now(), 'es')), findsOneWidget);
  });

  testWidgets('a transcript whose brief never arrived can still be read', (
    tester,
  ) async {
    final serbero =
        FakeSerberoCore()
          ..mediations[_a] = SerberoMediation(
            disputeId: _a,
            transcript: [serberoLine(SerberoSpeaker.buyer, 'Ya pagué.')],
            transcriptParts: 1,
            transcriptTotal: 1,
            transcriptSentAt: _sent,
            updates: const [],
          );
    await _pumpDetail(tester, serbero: serbero);
    await _openMediation(tester);
    await _scrollTo(tester, find.text('Ya pagué.'));
    expect(find.text('Ya pagué.'), findsOneWidget);
  });

  testWidgets('the mediation is read again when the trusted Serbero changes', (
    tester,
  ) async {
    final serbero = FakeSerberoCore()..mediations[_a] = _handedOff();
    await _pumpDetail(tester, serbero: serbero);
    await _scrollInfoTo(tester, find.byType(SerberoCard));
    final before = serbero.reads;

    ProviderScope.containerOf(
      tester.element(find.byType(SerberoCard)),
    ).invalidate(serberoNpubProvider);
    await tester.pumpAndSettle();

    expect(serbero.reads, greaterThan(before));
  });

  testWidgets('a reload that ends after a newer read does not replace it', (
    tester,
  ) async {
    // Arrange: a report update starts a reload that is held.
    final serbero = FakeSerberoCore()..mediations[_a] = _handedOff();
    await _pumpDetail(tester, serbero: serbero);
    final old = Completer<SerberoMediation?>();
    serbero.holdNext = old;
    serbero.push(_a);
    await tester.pump();

    // Act: a newer read (the trusted key changed), then the held reload
    // ends with what it read before.
    serbero.mediations[_a] = _handedOff(
      transcript: [serberoLine(SerberoSpeaker.seller, 'Lo nuevo.')],
      parts: 1,
      total: 1,
    );
    ProviderScope.containerOf(
      tester.element(find.byType(SerberoCard)),
    ).invalidate(serberoNpubProvider);
    await tester.pumpAndSettle();
    old.complete(_handedOff());
    await tester.pumpAndSettle();
    await _openMediation(tester);

    // Assert
    await _scrollTo(tester, find.text('Lo nuevo.'));
    expect(find.text('Lo nuevo.'), findsOneWidget);
  });

  testWidgets('a first read that ends after a newer reload does not replace '
      'it', (tester) async {
    // Arrange: the first read is held.
    final serbero = FakeSerberoCore();
    final first = Completer<SerberoMediation?>();
    serbero.holdNext = first;
    serbero.mediations[_a] = _handedOff(
      transcript: [serberoLine(SerberoSpeaker.seller, 'Lo nuevo.')],
      parts: 1,
      total: 1,
    );
    await _pumpDetail(tester, serbero: serbero);

    // Act: a report arrives and is read; then the first read ends with an
    // older mediation.
    serbero.push(_a);
    await tester.pump();
    first.complete(_handedOff());
    await tester.pumpAndSettle();
    await _openMediation(tester);

    // Assert
    await _scrollTo(tester, find.text('Lo nuevo.'));
    expect(find.text('Lo nuevo.'), findsOneWidget);
  });

  testWidgets('while the trusted Serbero changes, the card offers no report', (
    tester,
  ) async {
    // Arrange
    final serbero = FakeSerberoCore()..mediations[_a] = _handedOff();
    await _pumpDetail(tester, serbero: serbero);
    await _scrollInfoTo(tester, find.byType(SerberoCard));
    expect(find.text('Leer la mediación de Serbero'), findsOneWidget);

    // Act: the trust changes and the new read is held, then fails.
    final held = Completer<SerberoMediation?>();
    serbero.holdNext = held;
    ProviderScope.containerOf(
      tester.element(find.byType(SerberoCard)),
    ).invalidate(serberoNpubProvider);
    await tester.pump();
    await tester.pump();

    // Assert
    expect(find.text('Leer la mediación de Serbero'), findsNothing);
    held.completeError(Exception('storage'));
    await tester.pumpAndSettle();
    expect(find.text('Leer la mediación de Serbero'), findsNothing);
  });
}
