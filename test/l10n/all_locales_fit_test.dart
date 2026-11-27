import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/features/chat/services/chat_core.dart';
import 'package:bosstro/features/chat/widgets/chat_composer.dart';
import 'package:bosstro/features/disputes/screens/dispute_detail_screen.dart';
import 'package:bosstro/features/disputes/services/disputes_core.dart';
import 'package:bosstro/features/disputes/widgets/in_progress_dispute_row.dart';
import 'package:bosstro/features/disputes/widgets/detail_segments.dart';
import 'package:bosstro/features/nodes/models/node_display.dart';
import 'package:bosstro/features/disputes/widgets/pending_dispute_row.dart';
import 'package:bosstro/features/observer/screens/observer_screen.dart';
import 'package:bosstro/features/observer/services/observer_core.dart';
import 'package:bosstro/features/serbero/screens/serbero_screen.dart';
import 'package:bosstro/features/serbero/services/serbero_core.dart';
import 'package:bosstro/features/orders/services/orders_core.dart';
import 'package:bosstro/features/orders/widgets/order_summary_card.dart';
import 'package:bosstro/features/resolution/screens/resolution_screen.dart';
import 'package:bosstro/features/resolution/widgets/resolution_card.dart';
import 'package:bosstro/features/settings/widgets/language_sheet.dart';
import 'package:bosstro/l10n/app_localizations.dart';
import 'package:bosstro/shared/widgets/mostro_modal.dart';
import 'package:bosstro/shared/widgets/primary_button.dart';

import '../support/screen_harness.dart';

/// DS-A11Y-4 and DS-L10N-2 in every language the app ships: the main
/// screens at 320 dp and 2× text, scrolled to their end, with no overflow.
/// Spanish was the longest locale while the app had two; German or French
/// often is now, so every one is laid out.

const _a = '8a0c1e64-0d3b-4c39-9a3e-3a1f1f0f4b2c';
const _b = '1f2e3d4c-5b6a-4978-8695-a4b3c2d1e0f9';
const _c = '3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e6f';
const _opened = 1700000000;
final _now = DateTime.fromMillisecondsSinceEpoch((_opened + 7200) * 1000);

/// The node has disputes waiting, this key holds one, and another is in
/// progress for someone to recover.
FakeDisputesCore _disputes({bool? bonds = true}) =>
    FakeDisputesCore(
        disputes: [
          sampleDispute(id: _b),
          sampleDispute(id: _a, initiator: DisputeInitiator.buyer),
        ],
      )
      ..held = [sampleTaken(id: _a)]
      ..closed = [
        sampleTaken(
          id: _c,
          status: DisputeStatus.settled,
          resolvedAs: ResolvedAs.paidBuyer,
        ),
      ]
      ..details[_a] = sampleDetail(id: _a, bondsEnabled: bonds)
      ..candidates = [sampleDispute(id: _c, status: DisputeStatus.inProgress)]
      ..status = SolverStatus.yes
      ..permission = SolverPermission.readWrite;

FakeChatCore _chat() =>
    FakeChatCore()
      ..set(
        _a,
        ChatParty.buyer,
        messages: [
          sampleMessage(id: 'm1', content: 'Hola'),
          sampleMessage(
            id: 'm2',
            sender: ChatSender.you,
            content: 'Hola, ¿me envías el comprobante?',
            createdAt: _opened + 5000,
            delivery: ChatDelivery.failed,
          ),
        ],
      )
      ..set(_a, ChatParty.seller);

FakeObserverCore _observer() =>
    FakeObserverCore()
      ..chats[_a] = sampleObserved(
        disclosures: [
          const KeyDisclosure(party: ChatParty.buyer, sharedAt: _opened),
        ],
        messages: [
          observedMessage(id: 'o1', content: 'Ya pagué', createdAt: _opened),
          observedMessage(
            id: 'o2',
            sender: ChatParty.seller,
            content: '{"type":"file_encrypted"}',
            createdAt: _opened + 60,
            attachment: const ChatAttachment(
              kind: ChatAttachmentKind.file,
              fileName: 'comprobante.pdf',
              mimeType: 'application/pdf',
              size: 1468006,
            ),
          ),
        ],
      );

/// A handoff with every section, so each is measured.
FakeSerberoCore _serbero() =>
    FakeSerberoCore()
      ..mediations[_a] = SerberoMediation(
        disputeId: _a,
        brief: serberoNote(
          'handed off: self_resolution_stalled',
          'Topic: payment_not_confirmed (0.91) · rounds: 2',
          sentAt: _opened,
        ),
        transcript: [
          serberoLine(SerberoSpeaker.buyer, 'Ya pagué', at: _opened - 86400),
          serberoLine(SerberoSpeaker.serberoToSeller, '¿Lo recibiste?'),
          serberoLine(null, 'text that reads as no message'),
        ],
        transcriptParts: 1,
        transcriptTotal: 2,
        updates: [
          SerberoUpdateView(
            sentAt: _opened + 600,
            lines: [serberoLine(SerberoSpeaker.seller, 'Ya llegó')],
          ),
        ],
        finalReport: serberoNote(
          'resolved: cooperatively-canceled',
          'outcome: released',
          sentAt: _opened + 1200,
        ),
      );

Future<void> _pump(
  WidgetTester tester,
  Locale locale,
  String location, {
  bool signedIn = true,
  bool? bonds = true,
  FakeOrdersCore? orders,
}) async {
  // A fresh app each time: pumping a new one in its place would keep the
  // previous router and providers.
  await tester.pumpWidget(const SizedBox.shrink());
  setSurface(tester);
  await withClock(
    Clock.fixed(_now),
    () => pumpApp(
      tester,
      location: location,
      locale: locale,
      overrides: fakeCoreOverrides(
        signedIn: signedIn,
        disputes: _disputes(bonds: bonds),
        chat: _chat(),
        observer: _observer(),
        serbero: _serbero(),
        settings: FakeSettingsCore(serbero: {mostroNodePubkey: 'npub1serbero'}),
        orders: orders,
        nodes: FakeNodesCore(active: mostroNodePubkey, info: sampleInfo()),
      ),
    ),
  );
}

/// No overflow on screen, then none while every scrollable in [within]
/// (or on screen) is scrolled to its end, a viewport at a time.
Future<void> _fitsToTheEnd(
  WidgetTester tester,
  String where, {
  Finder? within,
}) async {
  expect(tester.takeException(), isNull, reason: where);
  final scrollables =
      within == null
          ? find.byType(Scrollable)
          : find.descendant(of: within, matching: find.byType(Scrollable));
  for (var i = 0; i < scrollables.evaluate().length; i++) {
    final state = tester.state<ScrollableState>(scrollables.at(i));
    final position = state.position;
    if (position.axis != Axis.vertical) continue;
    var steps = 0;
    while (position.pixels < position.maxScrollExtent && steps++ < 40) {
      position.jumpTo(
        math.min(
          position.pixels + position.viewportDimension,
          position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$where, scrolled');
    }
  }
}

Future<void> _tapText(
  WidgetTester tester,
  String text, {
  Finder? within,
}) async {
  final target =
      within == null
          ? find.text(text).first
          : find.descendant(of: within, matching: find.text(text)).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Bring [target] on screen (a scroll may have left it behind) and tap it.
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder _info() =>
    find
        .descendant(
          of: find.byType(IndexedStack),
          matching: find.byType(Scrollable),
        )
        .first;

Future<void> _scrollInfoTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: _info());
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    final l10n = lookupAppLocalizations(locale);
    final code = locale.languageCode;

    group('$code fits', () {
      testWidgets('Welcome, Log in, Create account', (tester) async {
        await _pump(tester, locale, AppRoute.welcome, signedIn: false);
        await _fitsToTheEnd(tester, 'Welcome');
        await _pump(tester, locale, AppRoute.login, signedIn: false);
        await _fitsToTheEnd(tester, 'Log in');
        await _pump(tester, locale, AppRoute.createAccount, signedIn: false);
        await _fitsToTheEnd(tester, 'Create account');
      });

      testWidgets('Pending and the take confirmation', (tester) async {
        await _pump(tester, locale, AppRoute.pending);
        await _fitsToTheEnd(tester, 'Pending');
        await _tap(tester, find.byType(PendingDisputeRow).first);
        expect(find.byType(MostroDialog), findsOneWidget);
        await _fitsToTheEnd(
          tester,
          'Take dialog',
          within: find.byType(MostroDialog),
        );
      });

      testWidgets('In progress, Recover and its confirmation', (tester) async {
        await _pump(tester, locale, AppRoute.inProgress);
        await _fitsToTheEnd(tester, 'In progress');
        // At this size the segments scrolled away with the list: back up.
        await tester.scrollUntilVisible(
          find.text(l10n.myDisputesClosedSegment),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await _tap(tester, find.text(l10n.myDisputesClosedSegment));
        expect(find.byType(ClosedDisputeRow), findsOneWidget);
        await _fitsToTheEnd(tester, 'Closed');
        await _pump(tester, locale, AppRoute.recover);
        await _fitsToTheEnd(tester, 'Recover');
        await _tap(tester, find.byType(PendingDisputeRow).first);
        expect(find.byType(MostroDialog), findsOneWidget);
        await _fitsToTheEnd(
          tester,
          'Recover dialog',
          within: find.byType(MostroDialog),
        );
      });

      testWidgets('the detail: Info, the chat, the parties\' chat, Serbero', (
        tester,
      ) async {
        await _pump(tester, locale, AppRoute.disputeDetail(_a));
        // Unfolded, so the dispute's and the order's rows are measured too.
        await openDisputeFacts(tester);
        await _fitsToTheEnd(tester, 'Info', within: find.byType(IndexedStack));
        await _tapText(
          tester,
          l10n.detailSegmentBuyer,
          within: find.byType(DetailSegments<DetailSection>),
        );
        expect(find.byType(ChatComposer).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Buyer chat');

        await _pump(tester, locale, AppRoute.disputeDetail(_a));
        final read = find.text(l10n.observerReadAction);
        await _scrollInfoTo(tester, read);
        await _tap(tester, read);
        expect(find.byType(ObserverScreen), findsOneWidget);
        await _fitsToTheEnd(tester, 'Observer');

        await _pump(tester, locale, AppRoute.disputeDetail(_a));
        final mediation = find.text(l10n.serberoReadAction);
        await _scrollInfoTo(tester, mediation);
        await _tap(tester, mediation);
        expect(find.byType(SerberoScreen), findsOneWidget);
        await _fitsToTheEnd(tester, 'Serbero');
      });

      for (final bonds in [true, null]) {
        testWidgets('the resolution confirmation, deposits $bonds', (
          tester,
        ) async {
          await _pump(tester, locale, AppRoute.disputeDetail(_a), bonds: bonds);
          final pay = find.descendant(
            of: find.byType(ResolutionCard),
            matching: find.text(l10n.payBuyerAction),
          );
          await _scrollInfoTo(tester, pay);
          await _tap(tester, pay);
          expect(find.byType(ResolutionScreen), findsOneWidget);
          await _fitsToTheEnd(
            tester,
            'Resolution',
            within: find.byType(ResolutionScreen),
          );
        });
      }

      testWidgets('Orders: the form, an order, and every other answer', (
        tester,
      ) async {
        Future<void> ask() async {
          // The field is the top of the list: back to it after a scroll.
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), sampleOrderId);
          await tester.pump();
          // By its type: in some locales the title reads as the button.
          await _tap(tester, find.byType(PrimaryButton));
        }

        await _pump(tester, locale, AppRoute.orders);
        await _fitsToTheEnd(tester, 'Orders');
        await ask();
        expect(find.byType(OrderSummaryCard), findsOneWidget);
        await _fitsToTheEnd(tester, 'Orders, an order');

        // The whole snapshot, both folded cards open, with the parts an
        // ordinary order lacks: a failed payment, deposits in every state.
        Future<void> wholeSnapshot(OrderSnapshot order, String where) async {
          final core = FakeOrdersCore()..order = order;
          await _pump(tester, locale, AppRoute.orders, orders: core);
          await ask();
          for (final title in [
            l10n.orderPartiesTitle,
            l10n.orderDepositsTitle(order.bonds.length),
          ]) {
            await _tapText(tester, title);
          }
          await _fitsToTheEnd(tester, 'Orders, $where');
        }

        await wholeSnapshot(
          sampleOrder(
            payout: const Payout(
              state: PayoutState.unavailable,
              failureReason: PayoutFailureReason.insufficientBalance,
              resolvedAt: 1700000300,
            ),
            bonds: [
              for (final state in BondState.values)
                OrderBond(
                  role: BondRole.taker,
                  amount: 1000,
                  state: state,
                  slashReason: BondSlashReason.timeout,
                  kind: BondKind.bond,
                ),
              const OrderBond(
                role: BondRole.maker,
                amount: 5000,
                state: BondState.pendingPayout,
                slashReason: BondSlashReason.lostDispute,
                kind: BondKind.sliceSlash,
              ),
              const OrderBond(
                role: BondRole.maker,
                amount: 5000,
                state: BondState.released,
                kind: BondKind.makerRefund,
              ),
              const OrderBond(
                role: BondRole.maker,
                amount: 5000,
                state: BondState.locked,
                kind: BondKind.bond,
                rootOrderId: '0d4f6a2b-7c1e-4f3a-8b5d-9e0f1a2b3c4d',
              ),
            ],
          ),
          'the whole snapshot',
        );
        await wholeSnapshot(
          sampleOrder(
            holdInvoice: const HoldInvoice(state: HoldInvoiceState.unavailable),
            bonds: const [],
          ),
          'Lightning silent, no deposit',
        );
        await wholeSnapshot(
          sampleOrder(
            holdInvoice: null,
            cashuEscrow: const CashuEscrow(
              mintUrl: 'https://mint.example.com/a/long/path',
              lockedAt: 1700000150,
            ),
            minAmount: 10,
            maxAmount: 100000,
            rangeParentId: '0d4f6a2b-7c1e-4f3a-8b5d-9e0f1a2b3c4d',
          ),
          'a Cashu order',
        );

        // The longest status of each locale, whichever it is.
        for (final status in OrderStatus.values) {
          final core =
              FakeOrdersCore()
                ..order = sampleOrder(status: status, statusRaw: 'unknown');
          await _pump(tester, locale, AppRoute.orders, orders: core);
          await ask();
          await _fitsToTheEnd(tester, 'Orders, $status');
        }

        for (final answer in <Object>[
          OrderLookupOutcome.notFound,
          OrderLookupOutcome.notSolver,
          OrderLookupOutcome.noAnswer,
          OrderLookupOutcome.refused,
          OrderLookupError.sendFailed,
          OrderLookupError.nodeInfoUnavailable,
          OrderLookupError.protocolUnsupported,
        ]) {
          final core =
              FakeOrdersCore()
                ..answer = answer
                ..reason = 'invalid_order_status';
          await _pump(tester, locale, AppRoute.orders, orders: core);
          await ask();
          await _fitsToTheEnd(tester, 'Orders, $answer');
        }
      });

      testWidgets('Settings and the language sheet', (tester) async {
        await _pump(tester, locale, AppRoute.settings);
        await _fitsToTheEnd(tester, 'Settings');
        await _tapText(tester, l10n.settingsLanguage);
        expect(find.byType(LanguageSheet), findsOneWidget);
        await _fitsToTheEnd(
          tester,
          'Language sheet',
          within: find.byType(LanguageSheet),
        );
      });

      testWidgets('Backup, Node, Relays, Node info', (tester) async {
        await _pump(tester, locale, AppRoute.backup);
        await _fitsToTheEnd(tester, 'Backup');
        await _pump(tester, locale, AppRoute.settingsNode);
        await _fitsToTheEnd(tester, 'Node');
        await _pump(tester, locale, AppRoute.relays);
        await _fitsToTheEnd(tester, 'Relays');
        await _pump(tester, locale, AppRoute.nodeInfo(cubaPubkey));
        await _fitsToTheEnd(tester, 'Node info');
      });

      testWidgets('About and the licence dialog', (tester) async {
        await _pump(tester, locale, AppRoute.about);
        await _fitsToTheEnd(tester, 'About');
        await _tapText(tester, l10n.aboutLicenseLabel);
        expect(find.byType(MostroDialog), findsOneWidget);
        await _fitsToTheEnd(
          tester,
          'Licence dialog',
          within: find.byType(MostroDialog),
        );
      });
    });
  }
}
