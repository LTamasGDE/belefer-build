import 'dart:convert';

import 'package:belefer/domain/accounts.dart';
import 'package:belefer/domain/capture/captured_event.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:belefer/services/ai_client.dart';
import 'package:belefer/services/ai_interpreter.dart';
import 'package:belefer/services/capture_processor.dart';
import 'package:belefer/services/exchange_rates.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ai_fakes.dart';
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
  matchers: ['Közös'],
);

CaptureProcessor processor(AiClient? client, {ExchangeRates? rates}) =>
    CaptureProcessor(
      interpreter: AiInterpreter(
        client: client,
        rates: rates ?? const NoExchangeRates(),
        accounts: const [_own, _joint],
      ),
      accounts: const [_own, _joint],
    );

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

FakeAiClient replying(Map<String, Object?> json) =>
    FakeAiClient((_) => jsonEncode(json));

void main() {
  final context = QuickEntryContext(today: testToday);

  test('AI-val rögzít, az esemény napjára, a felismert számlára', () async {
    final decision = await processor(
      replying({
        'status': 'ok',
        'type': 'expense',
        'amount': 4590,
        'title': 'Lidl',
        'category_id': 'groceries',
        'account_hint': 'Közös',
      }),
    ).decide(revolut('Fizettél 4 590 Ft-ot', title: 'Lidl'), context, recent: []);
    expect(decision.outcome, CaptureOutcome.booked);
    final transaction = decision.transaction!;
    expect(transaction.amount, 4590);
    expect(transaction.title, 'Lidl');
    expect(transaction.categoryId, 'groceries');
    expect(transaction.date.day, 16);
    expect(transaction.accountId, 3);
    expect(transaction.source, 'revolut');
    expect(transaction.note, contains('Revolut-értesítés'));
    expect(decision.log.detail, contains('AI'));
  });

  test('sikertelen fizetés, saját számlák közötti mozgás, egyéb', () async {
    for (final (status, expected) in [
      ('failed', CaptureOutcome.failed),
      ('internal_transfer', CaptureOutcome.transfer),
      ('not_a_transaction', CaptureOutcome.ignored),
    ]) {
      final decision = await processor(
        replying({'status': status, 'amount': 1000, 'title': 'X'}),
      ).decide(revolut('valami 1 000 Ft'), context, recent: []);
      expect(decision.outcome, expected, reason: status);
      expect(decision.transaction, isNull);
    }
  });

  test('AI nélkül a beépített besorolás szűr', () async {
    final failed = await processor(
      null,
    ).decide(revolut('Payment declined at Lidl, 4 590 Ft'), context, recent: []);
    expect(failed.outcome, CaptureOutcome.failed);

    final booked = await processor(
      const FailingAiClient(AiException('Nincs net', retryable: true)),
    ).decide(revolut('Fizettél 4 590 Ft-ot', title: 'Lidl'), context, recent: []);
    expect(booked.outcome, CaptureOutcome.booked);
    expect(booked.transaction!.amount, 4590);
    // Nincs felismerő szó: az alapértelmezett számla.
    expect(booked.transaction!.accountId, 1);
    expect(booked.log.detail, isNot(contains('AI')));
  });

  test('összeg nélkül nem rögzít', () async {
    final decision = await processor(
      replying({'status': 'ok', 'title': 'Lidl'}),
    ).decide(revolut('Lidl'), context, recent: []);
    expect(decision.outcome, CaptureOutcome.unclear);
  });

  test('deviza AI nélkül is átváltva', () async {
    final decision = await processor(
      null,
      rates: const FixedRates({'EUR': 400}),
    ).decide(revolut('Paid €4.50 at Starbucks', title: 'Starbucks'), context,
        recent: []);
    expect(decision.outcome, CaptureOutcome.booked);
    expect(decision.transaction!.amount, 1800);
    expect(decision.transaction!.note, contains('EUR'));
  });

  test('Apple Pay: kártyanév szerinti számla, ismétlés kiszűrése', () async {
    final ai = replying({
      'status': 'ok',
      'type': 'expense',
      'amount': 2990,
      'title': 'Rossmann',
      'category_id': 'health',
    });
    final first = await processor(ai).decide(
      applePay(amount: '2 990 Ft', merchant: 'Rossmann', card: 'Közös'),
      context,
      recent: [],
    );
    expect(first.outcome, CaptureOutcome.booked);
    expect(first.transaction!.accountId, 3);
    expect(first.transaction!.source, 'applepay');

    // Elutasított, majd 3 perc múlva megismételt érintés.
    final retry = await processor(ai).decide(
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
    final later = await processor(ai).decide(
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

  test('Apple Pay AI nélkül: összeg és kereskedő a mezőkből', () async {
    final decision = await processor(null).decide(
      applePay(amount: 'HUF 12,500.00', merchant: 'MOL', card: 'Saját'),
      context,
      recent: [],
    );
    expect(decision.outcome, CaptureOutcome.booked);
    expect(decision.transaction!.amount, 12500);
    expect(decision.transaction!.type, EntryType.expense);
    expect(decision.transaction!.accountId, 1);
  });
}
