import 'dart:convert';

import 'package:belefer/domain/ai/ai_prompt.dart';
import 'package:belefer/domain/ai/ai_settings.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:belefer/domain/recurring.dart';
import 'package:belefer/services/ai_client.dart';
import 'package:belefer/services/ai_interpreter.dart';
import 'package:belefer/services/exchange_rates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/ai_fakes.dart';
import '../support/test_app.dart';

http.Response geminiReply(Map<String, Object?> json) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(json)},
            ],
          },
        },
      ],
    }),
  ),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response mistralReply(Map<String, Object?> json) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'choices': [
        {
          'message': {'content': jsonEncode(json)},
        },
      ],
    }),
  ),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  final context = QuickEntryContext(today: testToday);

  group('Gemini', () {
    test('kérés és válasz', () async {
      late http.Request sent;
      final client = GeminiClient(
        apiKey: 'kulcs',
        model: 'gemini-flash-lite-latest',
        httpClient: MockClient((request) async {
          sent = request;
          return geminiReply({'amount': 4500, 'title': 'Lidl'});
        }),
      );
      final text = await client.completeJson(system: 'rendszer', user: 'Lidl');
      expect(jsonDecode(text), {'amount': 4500, 'title': 'Lidl'});
      expect(sent.headers['x-goog-api-key'], 'kulcs');
      expect(
        sent.url.path,
        endsWith('gemini-flash-lite-latest:generateContent'),
      );
      // A kulcs nem kerül az URL-be.
      expect(sent.url.toString(), isNot(contains('kulcs')));
      final body = jsonDecode(sent.body) as Map;
      expect(
        (body['generationConfig'] as Map)['responseMimeType'],
        'application/json',
      );
    });

    test('nem elérhető modellnél a következővel próbálkozik', () async {
      final tried = <String>[];
      final client = GeminiClient(
        apiKey: 'k',
        model: 'nincs-ilyen',
        httpClient: MockClient((request) async {
          final model = request.url.pathSegments.last.split(':').first;
          tried.add(model);
          if (model == 'gemini-flash-lite-latest') {
            return geminiReply({'amount': 1});
          }
          return http.Response('{}', 404);
        }),
      );
      await client.completeJson(system: 's', user: 'u');
      expect(tried, ['nincs-ilyen', 'gemini-flash-lite-latest']);
      // A működő modellt jegyzi meg.
      await client.completeJson(system: 's', user: 'u');
      expect(tried.last, 'gemini-flash-lite-latest');
      expect(tried, hasLength(3));
    });

    test('hibás kulcs és elfogyott keret', () async {
      Future<AiException> failWith(int status) async {
        final client = GeminiClient(
          apiKey: 'k',
          model: 'm',
          httpClient: MockClient((_) async => http.Response('{}', status)),
        );
        try {
          await client.completeJson(system: 's', user: 'u');
        } on AiException catch (error) {
          return error;
        }
        fail('Hibát vártunk ($status).');
      }

      final forbidden = await failWith(403);
      expect(forbidden.retryable, isFalse);
      expect(forbidden.message, contains('kulcs'));
      final quota = await failWith(429);
      expect(quota.retryable, isTrue);
      final server = await failWith(503);
      expect(server.retryable, isTrue);
    });
  });

  test('Mistral', () async {
    late http.Request sent;
    final client = MistralClient(
      apiKey: 'mk',
      model: 'mistral-small-latest',
      httpClient: MockClient((request) async {
        sent = request;
        return mistralReply({'amount': 990});
      }),
    );
    final text = await client.completeJson(system: 's', user: 'u');
    expect(jsonDecode(text), {'amount': 990});
    expect(sent.headers['Authorization'], 'Bearer mk');
    final body = jsonDecode(sent.body) as Map;
    expect(body['model'], 'mistral-small-latest');
    expect((body['response_format'] as Map)['type'], 'json_object');
  });

  test('a beállításokból készül a kliens', () {
    expect(createAiClient(const AiSettings()), isNull);
    expect(
      createAiClient(const AiSettings(provider: AiProvider.gemini)),
      isNull,
      reason: 'kulcs nélkül nincs kliens',
    );
    expect(
      createAiClient(
        const AiSettings(provider: AiProvider.gemini, geminiKey: 'k'),
      ),
      isA<GeminiClient>(),
    );
    final mistral = createAiClient(
      const AiSettings(provider: AiProvider.mistral, mistralKey: 'k'),
    );
    expect(mistral, isA<MistralClient>());
    expect((mistral! as MistralClient).model, 'mistral-small-latest');
    final restored = AiSettings.fromMap(
      const AiSettings(
        provider: AiProvider.mistral,
        mistralKey: 'abc',
        geminiModel: 'gemini-x',
      ).toMap(),
    );
    expect(restored.provider, AiProvider.mistral);
    expect(restored.apiKey, 'abc');
    expect(restored.geminiModel, 'gemini-x');
  });

  group('AI-válasz értelmezése', () {
    test('kódblokkban, szöveges számmal', () {
      final reading = parseAiReading(
        'Íme:\n```json\n{"status":"ok","type":"expense","amount":"4 590",'
        '"currency":"huf","title":"Lidl","category_id":"groceries",'
        '"date":"2026-11-16","account_hint":"Közös"}\n```',
      );
      expect(reading.amount, 4590);
      expect(reading.isHuf, isTrue);
      expect(reading.type, EntryType.expense);
      expect(reading.date, CalendarDay(2026, 11, 16));
      expect(reading.accountHint, 'Közös');
    });

    test('hiányos és hibás mezők', () {
      final reading = parseAiReading(
        '{"amount":null,"title":"null","date":"tegnap","interval":40}',
      );
      expect(reading.amount, isNull);
      expect(reading.title, isNull);
      expect(reading.date, isNull);
      expect(reading.interval, isNull);
      expect(reading.status, 'ok');
      expect(() => parseAiReading('nem json'), throwsFormatException);
    });

    test('ellenőrzés: kategória, jövőbeli dátum, ismétlődő tétel', () {
      final netflix = RecurringRule(
        id: 5,
        type: EntryType.expense,
        title: 'Netflix',
        categoryId: 'subscriptions',
        amount: 4990,
        startDate: CalendarDay(2026, 1, 3),
      );
      final ctx = QuickEntryContext(today: testToday, rules: [netflix]);

      // Bevételi kategória kiadáshoz nem fogadható el.
      final wrongCategory = quickEntryFromAi(
        const AiReading(
          type: EntryType.expense,
          amount: 1200,
          title: 'Pék',
          categoryId: 'salary',
        ),
        ctx,
        amountHuf: 1200,
      );
      expect(wrongCategory.categoryId, 'other_expense');
      expect(wrongCategory.categoryGuessed, isTrue);
      expect(wrongCategory.fromAi, isTrue);

      final future = quickEntryFromAi(
        AiReading(amount: 500, title: 'Kávé', date: CalendarDay(2026, 12, 1)),
        ctx,
        amountHuf: 500,
      );
      expect(future.date, testToday);

      final cancel = quickEntryFromAi(
        const AiReading(intent: 'cancel_recurring', targetRule: 'netflix'),
        ctx,
        amountHuf: null,
      );
      expect(cancel.intent, QuickIntent.cancelRecurring);
      expect(cancel.targetRule?.id, 5);
      expect(cancel.title, 'Netflix');
    });
  });

  group('AI-értelmező', () {
    test('az AI eredménye, forintban', () async {
      final ai = FakeAiClient(
        (_) => jsonEncode({
          'type': 'expense',
          'amount': 4500,
          'title': 'Lidl',
          'category_id': 'groceries',
          'date': '2026-11-16',
        }),
      );
      final outcome =
          await AiInterpreter(
            client: ai,
            rates: const NoExchangeRates(),
          ).interpret(
            'tegnap lidl 4500',
            AiInputKind.sentence,
            context,
            fallback: interpretQuickEntry('tegnap lidl 4500', context),
          );
      expect(outcome.usedAi, isTrue);
      expect(outcome.result.amount, 4500);
      expect(outcome.result.categoryId, 'groceries');
      expect(outcome.result.date, CalendarDay(2026, 11, 16));
      expect(ai.systems.single, contains('2026-11-17'));
      expect(ai.systems.single, contains('groceries'));
    });

    test('devizás összeg átváltása', () async {
      final ai = FakeAiClient(
        (_) => jsonEncode({
          'amount': 4.5,
          'currency': 'EUR',
          'title': 'Starbucks',
          'category_id': 'dining',
        }),
      );
      final outcome =
          await AiInterpreter(
            client: ai,
            rates: const FixedRates({'EUR': 400}),
          ).interpret(
            'Paid €4.50 at Starbucks',
            AiInputKind.notification,
            context,
            fallback: interpretQuickEntry('Paid 4.50 Starbucks', context),
          );
      expect(outcome.result.amount, 1800);
      expect(outcome.result.notes.join(), contains('EUR'));
    });

    test('árfolyam nélkül nem találgat összeget', () async {
      final ai = FakeAiClient(
        (_) => jsonEncode({'amount': 12, 'currency': 'USD', 'title': 'App'}),
      );
      final outcome =
          await AiInterpreter(
            client: ai,
            rates: const NoExchangeRates(),
          ).interpret(
            'Paid \$12 App',
            AiInputKind.notification,
            context,
            fallback: interpretQuickEntry('Paid 12 App', context),
          );
      expect(outcome.result.amount, isNull);
      expect(outcome.result.notes.join(), contains('forintban'));
    });

    test('hiba esetén a beépített értelmező dolgozik', () async {
      final fallback = interpretQuickEntry('lidl 4500', context);
      final outcome =
          await const AiInterpreter(
            client: FailingAiClient(
              AiException('Elfogyott a keret.', retryable: true),
            ),
            rates: NoExchangeRates(),
          ).interpret(
            'lidl 4500',
            AiInputKind.sentence,
            context,
            fallback: fallback,
          );
      expect(outcome.usedAi, isFalse);
      expect(outcome.error, 'Elfogyott a keret.');
      expect(outcome.retryable, isTrue);
      expect(outcome.result.amount, 4500);

      final garbage =
          await AiInterpreter(
            client: FakeAiClient((_) => 'sajnálom'),
            rates: const NoExchangeRates(),
          ).interpret(
            'lidl 4500',
            AiInputKind.sentence,
            context,
            fallback: fallback,
          );
      expect(garbage.usedAi, isFalse);
      expect(garbage.result.amount, 4500);
    });

    test('AI nélkül a tartalék eredmény', () async {
      final fallback = interpretQuickEntry('lidl 4500', context);
      final outcome =
          await const AiInterpreter(
            client: null,
            rates: NoExchangeRates(),
          ).interpret(
            'lidl 4500',
            AiInputKind.sentence,
            context,
            fallback: fallback,
          );
      expect(outcome.usedAi, isFalse);
      expect(outcome.error, isNull);
      expect(identical(outcome.result, fallback), isTrue);
    });
  });
}
