import 'dart:convert';
import 'dart:io';

import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/capture/captured_event.dart';
import 'package:belefer/domain/model/belefer_model.dart';
import 'package:belefer/domain/model/features.dart';
import 'package:belefer/domain/model/personal_memory.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:belefer/domain/quick_entry/receipt_parser.dart';
import 'package:belefer/domain/quick_entry/tokens.dart';
import 'package:belefer/domain/recurring.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/model.dart';
import '../../support/test_app.dart';

void main() {
  final model = loadTestModel();
  final golden =
      jsonDecode(File('test/fixtures/model_golden.json').readAsStringSync())
          as Map<String, Object?>;

  group('egyezés a tanítóprogrammal', () {
    test('szavak, jellemzők és hash', () {
      for (final raw in golden['features']! as List) {
        final item = raw as Map<String, Object?>;
        final text = item['text']! as String;
        final words = modelWords(text);
        expect(words, item['words'], reason: text);
        final vector = vectorize(sequenceFeatures(words), model.dimBits);
        expect(vector.buckets, item['buckets'], reason: text);
        expect(vector.weight, closeTo(item['weight']! as double, 1e-9));
      }
    });

    test('ugyanazok a valószínűségek', () {
      for (final raw in golden['predictions']! as List) {
        final item = raw as Map<String, Object?>;
        final head = item['head']! as String;
        final text = item['text']! as String;
        final expected = (item['probs']! as List).cast<num>();
        final actual = head == 'title'
            ? model.titleProbabilities(tokensOf(text))
            : model.classify(head, text).probabilities;
        expect(actual, hasLength(expected.length), reason: text);
        for (var i = 0; i < expected.length; i++) {
          expect(
            actual[i],
            closeTo(expected[i].toDouble(), 2e-6),
            reason: '$head: $text',
          );
        }
      }
    });

    test('a modellfájl fejei', () {
      expect(
        model.heads.keys,
        containsAll(['category', 'intent', 'status', 'title']),
      );
      expect(model.heads['intent']!.labels, [
        'cancel_recurring',
        'change_recurring',
        'create_recurring',
        'record',
      ]);
      expect(model.weightCount, greaterThan(100000));
      expect(model.flags['sw'], contains('kb'));
    });
  });

  group('a modell az értelmezőben', () {
    setUp(() => currentModel = model);
    tearDown(() => currentModel = null);
    final context = QuickEntryContext(today: testToday);

    test('ismeretlen szavak kategóriája és megnevezése', () {
      final butcher = interpretQuickEntry('tegnap a hentesnél 6700', context);
      expect(butcher.categoryId, 'groceries');
      expect(butcher.categoryGuessed, isFalse);
      expect(butcher.title, 'Hentes');
      expect(butcher.amount, 6700);
      expect(butcher.date, CalendarDay(2026, 11, 16));

      final sofa = interpretQuickEntry('vettem egy kanapét 45e', context);
      expect(sofa.categoryId, 'housing');
      expect(sofa.title, 'Kanapé');
      expect(sofa.amount, 45000);

      final car = interpretQuickEntry(
        'elvittem a kocsit átvizsgálásra 38000',
        context,
      );
      expect(car.categoryId, 'transport');

      final bill = interpretQuickEntry('befizettem a csekket 12400', context);
      expect(bill.categoryId, 'utilities');
      expect(bill.title, 'Csekk');
    });

    test('modell nélkül ugyanezek „Egyéb” kategóriát kapnak', () {
      currentModel = null;
      final butcher = interpretQuickEntry('tegnap a hentesnél 6700', context);
      expect(butcher.categoryId, 'other_expense');
      expect(butcher.categoryGuessed, isTrue);
    });

    test('lemondás a szótárban nem szereplő megfogalmazással', () {
      final spotify = RecurringRule(
        id: 3,
        type: EntryType.expense,
        title: 'Spotify',
        categoryId: 'subscriptions',
        amount: 1990,
        startDate: CalendarDay(2026, 1, 5),
      );
      final result = interpretQuickEntry(
        'nem fizetek már a spotifyra',
        QuickEntryContext(today: testToday, rules: [spotify]),
      );
      expect(result.intent, QuickIntent.cancelRecurring);
      expect(result.targetRule?.id, 3);
    });

    test('blokk ismeretlen boltból: kategória a tételsorokból', () {
      final result = interpretReceipt(
        'NOVA BT\nALGOFLEX 1290\nC-VITAMIN 990\nÖSSZESEN 2280 Ft',
        context,
      );
      expect(result.categoryId, 'health');
      expect(result.amount, 2280);
    });

    test('banki értesítések', () {
      CapturedEvent event(String title, String text) => CapturedEvent(
        id: text,
        source: CaptureSource.revolut,
        receivedAt: DateTime(2026, 11, 17, 10),
        title: title,
        text: text,
      );
      expect(
        classifyOffline(
          event('Revolut', 'A kártyádat zároltuk gyanús tevékenység miatt'),
          context,
        ).status,
        'not_a_transaction',
      );
      final paid = classifyOffline(
        event('Lidl', 'Fizettél 4 590 Ft-ot'),
        context,
      );
      expect(paid.status, 'ok');
      expect(paid.result.type, EntryType.expense);
      expect(paid.result.amount, 4590);
      final received = classifyOffline(
        event('Revolut', 'You received 20 000 HUF from Bence'),
        context,
      );
      expect(received.status, 'ok');
      expect(received.result.type, EntryType.income);
      expect(
        classifyOffline(
          event('Revolut', 'Card payment at MOL failed'),
          context,
        ).status,
        'failed',
      );
      expect(
        classifyOffline(
          event('Revolut', 'You moved 50 000 HUF to Savings'),
          context,
        ).status,
        'internal_transfer',
      );
    });
  });

  group('személyes rész', () {
    test('a korábbi megnevezésekre emlékszik, elírva is', () {
      final memory = PersonalMemory.from([
        expense('Rózsika néni takarítás', 8000, 'other_expense', testToday),
        expense('Zongoraóra Kovácsnénál', 6000, 'education', testToday),
        expense('Lidl', 4000, 'groceries', testToday),
      ]);
      expect(memory.size, 3);
      final piano = memory.recall(modelWords('zongora ora kovacsnenal 6000'));
      expect(piano?.categoryId, 'education');
      expect(piano?.title, 'Zongoraóra Kovácsnénál');
      final cleaning = memory.recall(modelWords('rozsika neninek 8000'));
      expect(cleaning?.categoryId, 'other_expense');
      expect(memory.recall(modelWords('benzin 20000')), isNull);
    });

    test('gyorsítótár: ugyanarra a listára nem épül újra', () {
      final history = [expense('Lidl', 4000, 'groceries', testToday)];
      expect(
        identical(PersonalMemory.of(history), PersonalMemory.of(history)),
        isTrue,
      );
    });
  });

  test('a ragok levágása a megnevezésből', () {
    expect(trimCaseSuffix('pékségben'), 'pékség');
    expect(trimCaseSuffix('pizzára'), 'pizza');
    expect(trimCaseSuffix('Lidlbe'), 'Lidl');
    expect(trimCaseSuffix('kamera'), 'kamera');
    expect(trimCaseSuffix('Netflixet'), 'Netflix');
    expect(trimCaseSuffix('kanapét'), 'kanapé');
    expect(trimCaseSuffix('kávéra'), 'kávé');
    expect(trimCaseSuffix('csirkére'), 'csirke');
    expect(trimCaseSuffix('kabát'), 'kabát');
    expect(trimCaseSuffix('autóra'), 'autó');
  });
}

/// A `tokenize` egyszerűsített tokenjei (mint a Python `raw_tokens`).
List<String> tokensOf(String text) => [
  for (final token in tokenize(text)) token.folded,
];
