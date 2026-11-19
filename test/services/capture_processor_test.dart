import 'package:belefer/domain/accounts.dart';
import 'package:belefer/domain/capture/captured_event.dart';
import 'package:belefer/domain/model/belefer_model.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:belefer/services/capture_processor.dart';
import 'package:belefer/services/exchange_rates.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/model.dart';
import '../support/test_app.dart';

const _own = Account(
  id: 1,
  name: 'Saját',
  kind: AccountKind.personal,
  matchers: ['Saját'],
  isDefault: true,
);
const _joint = Account(
  id: 3,
  name: 'Közös',
  kind: AccountKind.shared,
  matchers: ['Közös', 'Joint'],
);

CaptureProcessor processor({ExchangeRates rates = const NoExchangeRates()}) =>
    CaptureProcessor(rates: rates, accounts: const [_own, _joint]);

CapturedEvent revolut(String text, {String title = 'Revolut'}) =>
    CapturedEvent(
      id: text,
      source: CaptureSource.revolut,
      receivedAt: DateTime(2026, 11, 16, 18, 20),
      title: title,
      text: text,
    );

CapturedEvent applePay({
  required String amount,
  required String merchant,
  required String card,
  DateTime? at,
}) => CapturedEvent(
  id: '$merchant$at',
  source: CaptureSource.applePay,
  receivedAt: at ?? DateTime(2026, 11, 17, 9),
  amountText: amount,
  merchant: merchant,
  card: card,
);

void main() {
  final context = QuickEntryContext(today: testToday);

  for (final withModel in [false, true]) {
    group(withModel ? 'a saját modellel' : 'csak szabályokkal', () {
      setUp(() => currentModel = withModel ? loadTestModel() : null);
      tearDown(() => currentModel = null);

      test('rögzít az esemény napjára, az alapértelmezett számlára', () async {
        final decision = await processor().decide(
          revolut('Fizettél 4 590 Ft-ot', title: 'Lidl'),
          context,
          recent: [],
        );
        expect(decision.outcome, CaptureOutcome.booked);
        final transaction = decision.transaction!;
        expect(transaction.amount, 4590);
        expect(transaction.title, 'Lidl');
        expect(transaction.categoryId, 'groceries');
        expect(transaction.type, EntryType.expense);
        expect(transaction.date.day, 16);
        expect(transaction.accountId, 1);
        expect(transaction.source, 'revolut');
        expect(transaction.note, contains('Revolut-értesítés'));
      });

      test('közös számla a felismerő szóból', () async {
        final decision = await processor().decide(
          revolut('Anna spent 12 400 HUF at Tesco', title: 'Joint'),
          context,
          recent: [],
        );
        expect(decision.outcome, CaptureOutcome.booked);
        expect(decision.transaction!.accountId, 3);
        expect(decision.transaction!.amount, 12400);
      });

      test('sikertelen fizetés, saját számlák közötti mozgás, egyéb', () async {
        for (final (text, expected) in [
          ('Payment declined at Lidl, 4 590 Ft', CaptureOutcome.failed),
          ('Nincs elég fedezet a 4 590 Ft-os fizetéshez', CaptureOutcome.failed),
          ('10 000 Ft átkerült a Megtakarítás perselybe', CaptureOutcome.transfer),
          ('You topped up 20 000 HUF', CaptureOutcome.transfer),
          ('Erősítsd meg a bejelentkezést', CaptureOutcome.ignored),
        ]) {
          final decision = await processor().decide(
            revolut(text),
            context,
            recent: [],
          );
          expect(decision.outcome, expected, reason: text);
          expect(decision.transaction, isNull);
        }
      });

      test('deviza átváltva', () async {
        final decision = await processor(
          rates: const FixedRates({'EUR': 400}),
        ).decide(
          revolut('Paid €4.50 at Starbucks', title: 'Starbucks'),
          context,
          recent: [],
        );
        expect(decision.outcome, CaptureOutcome.booked);
        expect(decision.transaction!.amount, 1800);
        expect(decision.transaction!.note, contains('EUR'));
      });

      test('árfolyam nélkül nem találgat', () async {
        final decision = await processor().decide(
          revolut('Paid €4.50 at Starbucks', title: 'Starbucks'),
          context,
          recent: [],
        );
        expect(decision.outcome, CaptureOutcome.unclear);
        expect(decision.log.detail, contains('forintban'));
      });

      test('Apple Pay: kártyanév szerinti számla, ismétlés kiszűrése', () async {
        final first = await processor().decide(
          applePay(amount: '2 990 Ft', merchant: 'Rossmann', card: 'Közös'),
          context,
          recent: [],
        );
        expect(first.outcome, CaptureOutcome.booked);
        expect(first.transaction!.accountId, 3);
        expect(first.transaction!.source, 'applepay');

        // Elutasított, majd 3 perc múlva megismételt érintés.
        final retry = await processor().decide(
          applePay(
            amount: '2 990 Ft',
            merchant: 'Rossmann',
            card: 'Közös',
            at: DateTime(2026, 11, 17, 9, 3),
          ),
          context,
          recent: [first.log],
        );
        expect(retry.outcome, CaptureOutcome.duplicate);

        // Fél óra múlva már új vásárlás.
        final later = await processor().decide(
          applePay(
            amount: '2 990 Ft',
            merchant: 'Rossmann',
            card: 'Közös',
            at: DateTime(2026, 11, 17, 9, 40),
          ),
          context,
          recent: [first.log],
        );
        expect(later.outcome, CaptureOutcome.booked);
      });

      test('Apple Pay: összeg és kereskedő a mezőkből', () async {
        final decision = await processor().decide(
          applePay(amount: 'HUF 12,500.00', merchant: 'MOL', card: 'Saját'),
          context,
          recent: [],
        );
        expect(decision.outcome, CaptureOutcome.booked);
        expect(decision.transaction!.amount, 12500);
        expect(decision.transaction!.type, EntryType.expense);
        expect(decision.transaction!.categoryId, 'transport');
        expect(decision.transaction!.accountId, 1);
      });
    });
  }

  test('a modell az ismeretlen kereskedőt is besorolja', () async {
    currentModel = loadTestModel();
    addTearDown(() => currentModel = null);
    final decision = await processor().decide(
      applePay(amount: '6 700 Ft', merchant: 'Kovács Hentesáru', card: 'Saját'),
      context,
      recent: [],
    );
    expect(decision.transaction!.categoryId, 'groceries');
  });
}
