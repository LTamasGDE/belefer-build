import 'package:belefer/domain/accounts.dart';
import 'package:belefer/domain/capture/captured_event.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

const _own = Account(
  id: 1,
  name: 'Saját',
  kind: AccountKind.personal,
  matchers: ['Saját Revolut', '4821'],
  isDefault: true,
);
const _savings = Account(
  id: 2,
  name: 'Megtakarítás',
  kind: AccountKind.savings,
  matchers: ['Megtakarítás'],
);
const _joint = Account(
  id: 3,
  name: 'Közös',
  kind: AccountKind.shared,
  matchers: ['Közös', 'Joint', '7710'],
);
const _accounts = [_own, _savings, _joint];

CapturedEvent revolut(String title, String text) => CapturedEvent(
  id: title + text,
  source: CaptureSource.revolut,
  receivedAt: DateTime(2026, 11, 17, 10, 30),
  title: title,
  text: text,
);

void main() {
  final context = QuickEntryContext(today: testToday);

  group('számla felismerése', () {
    test('szó, kártyaszám vége és alapértelmezett', () {
      expect(matchAccount(_accounts, 'Apple Pay Közös kártya')?.id, 3);
      expect(matchAccount(_accounts, 'Paid with Joint card')?.id, 3);
      expect(matchAccount(_accounts, 'Kártya •7710, Lidl')?.id, 3);
      expect(matchAccount(_accounts, 'Kártya: Saját Revolut')?.id, 1);
      // Nincs illeszkedés: az alapértelmezett számla.
      expect(matchAccount(_accounts, 'Lidl 4 590 Ft')?.id, 1);
      expect(matchAccount(const [_savings, _joint], 'Lidl'), isNull);
    });

    test('összeg darabja nem számít kártyaszámnak', () {
      // „14 821 Ft” nem a 4821-re végződő kártya.
      expect(matchAccount(const [_savings, _joint], 'Lidl 14 821 Ft'), isNull);
      expect(matchAccount(const [_joint], '5355 1234 5678 7710')?.id, 3);
      expect(matchAccount(const [_joint], '535512345678 7710')?.id, 3);
    });

    test('a hosszabb felismerő szó nyer', () {
      const a = Account(
        id: 10,
        name: 'Revolut',
        kind: AccountKind.personal,
        matchers: ['Revolut'],
      );
      const b = Account(
        id: 11,
        name: 'Közös Revolut',
        kind: AccountKind.shared,
        matchers: ['Közös Revolut'],
      );
      expect(matchAccount(const [a, b], 'Kártya: Közös Revolut')?.id, 11);
      expect(matchAccount(const [a, b], 'Kártya: Revolut')?.id, 10);
    });

    test('a számla mentése és visszaolvasása', () {
      final restored = Account.fromMap(3, _joint.toMap());
      expect(restored.name, 'Közös');
      expect(restored.kind, AccountKind.shared);
      expect(restored.matchers, ['Közös', 'Joint', '7710']);
      expect(restored.isDefault, isFalse);
    });
  });

  group('beépített besorolás', () {
    test('kártyás fizetés kiadás, összeggel', () {
      final reading = classifyOffline(
        revolut('Lidl', 'Fizettél 4 590 Ft-ot'),
        context,
      );
      expect(reading.status, 'ok');
      expect(reading.currency, 'HUF');
      expect(reading.result.amount, 4590);
      expect(reading.result.type, EntryType.expense);
    });

    test('sikertelen fizetés', () {
      for (final text in [
        'Payment declined: insufficient funds',
        'A 4 590 Ft-os fizetés sikertelen volt',
        'Elutasított kártyás fizetés: Lidl 4 590 Ft',
      ]) {
        expect(
          classifyOffline(revolut('Revolut', text), context).status,
          'failed',
          reason: text,
        );
      }
    });

    test('saját számlák közötti mozgás és feltöltés', () {
      for (final text in [
        '10 000 Ft átkerült a Megtakarítás perselybe',
        'You topped up 20 000 HUF',
        'Exchanged 50 EUR to HUF',
      ]) {
        expect(
          classifyOffline(revolut('Revolut', text), context).status,
          'internal_transfer',
          reason: text,
        );
      }
    });

    test('nem pénzmozgás', () {
      expect(
        classifyOffline(
          revolut('Revolut', 'Erősítsd meg a bejelentkezést'),
          context,
        ).status,
        'not_a_transaction',
      );
      expect(
        classifyOffline(revolut('Revolut', 'Új ajánlat vár rád'), context)
            .status,
        'not_a_transaction',
      );
    });

    test('bejövő utalás bevétel', () {
      final reading = classifyOffline(
        revolut('Kovács Anna', 'Kaptál 12 000 Ft-ot'),
        context,
      );
      expect(reading.status, 'ok');
      expect(reading.result.type, EntryType.income);
      expect(reading.result.amount, 12000);
    });

    test('devizás összeg felismerése', () {
      final euro = classifyOffline(
        revolut('Starbucks', 'Paid €4.50 at Starbucks'),
        context,
      );
      expect(euro.currency, 'EUR');
      expect(euro.foreignAmount, 4.5);
      final dollar = classifyOffline(
        revolut('Amazon', 'Paid USD 1,234.56'),
        context,
      );
      expect(dollar.currency, 'USD');
      expect(dollar.foreignAmount, 1234.56);
      final after = classifyOffline(
        revolut('Card 4821', 'Paid 12,30 EUR at Zara'),
        context,
      );
      expect(after.currency, 'EUR');
      expect(after.foreignAmount, 12.3);
      // Angol szöveg nem pénznem.
      expect(
        classifyOffline(
          revolut('Revolut', 'Try Premium: 1 990 Ft havonta'),
          context,
        ).currency,
        'HUF',
      );
    });

    test('Apple Pay: a kereskedő a megnevezés', () {
      final reading = classifyOffline(
        CapturedEvent(
          id: '1',
          source: CaptureSource.applePay,
          receivedAt: DateTime(2026, 11, 17, 9),
          amountText: '4 590 Ft',
          merchant: 'SPAR',
          card: 'Saját Revolut',
        ),
        context,
      );
      expect(reading.status, 'ok');
      expect(reading.result.title?.toLowerCase(), 'spar');
      expect(reading.result.type, EntryType.expense);
    });

    test('Apple Pay összeg formátumai', () {
      expect(parseHufAmount('4 590 Ft'), 4590);
      expect(parseHufAmount('HUF 4,590.00'), 4590);
      expect(parseHufAmount('4.590 Ft'), 4590);
      expect(parseHufAmount('12 345 Ft'), 12345);
      expect(parseHufAmount('Ft 990'), 990);
    });
  });

  test('esemény a platform sorából', () {
    final event = CapturedEvent.fromMap({
      'id': 'abc',
      'source': 'applepay',
      'time': DateTime(2026, 11, 16, 18, 5).millisecondsSinceEpoch,
      'amount': '2 990 Ft',
      'merchant': 'Rossmann',
      'card': 'Közös',
    });
    expect(event.source, CaptureSource.applePay);
    expect(event.day.day, 16);
    expect(event.description, contains('Kereskedő: Rossmann'));
    expect(event.accountText, contains('Közös'));

    final android = CapturedEvent.fromMap({
      'id': 'x',
      'source': 'revolut',
      'time': 0,
      'title': ' Lidl ',
      'text': '',
    });
    expect(android.title, 'Lidl');
    expect(android.description, 'Lidl');
  });

  test('naplóbejegyzés mentése és visszaolvasása', () {
    final entry = CaptureLogEntry(
      time: DateTime(2026, 11, 17, 10),
      source: CaptureSource.revolut,
      raw: 'Lidl\nFizettél 4 590 Ft-ot',
      outcome: CaptureOutcome.booked,
      detail: 'Lidl, 4590 Ft',
      amount: 4590,
      merchantKey: 'lidl',
      transactionId: 7,
    );
    final restored = CaptureLogEntry.fromMap(entry.toMap());
    expect(restored.outcome, CaptureOutcome.booked);
    expect(restored.amount, 4590);
    expect(restored.transactionId, 7);
    expect(restored.time, entry.time);
  });
}
