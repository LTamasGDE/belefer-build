import '../domain/accounts.dart';
import '../domain/ai/ai_prompt.dart';
import '../domain/quick_entry/interpreter.dart';
import 'ai_client.dart';
import 'exchange_rates.dart';

/// Az AI-értelmezés eredménye.
class AiOutcome {
  const AiOutcome({
    required this.result,
    this.reading,
    this.error,
    this.retryable = false,
  });

  /// Az ellenőrzött eredmény (AI-ból, vagy hiba esetén a tartalékból).
  final QuickEntryResult result;

  /// Az AI nyers válasza (ha volt).
  final AiReading? reading;

  /// Ha az AI nem volt elérhető: miért.
  final String? error;
  final bool retryable;

  bool get usedAi => reading != null;

  /// A pénzmozgás állapota (`ok`, `failed`, `internal_transfer`,
  /// `not_a_transaction`).
  String get status => reading?.status ?? 'ok';
}

/// Szöveg értelmezése AI-val; ha az AI nem érhető el, a beépített
/// értelmező eredményével ([fallback]) tér vissza.
class AiInterpreter {
  const AiInterpreter({
    required this.client,
    required this.rates,
    this.accounts = const [],
  });

  final AiClient? client;
  final ExchangeRates rates;
  final List<Account> accounts;

  Future<AiOutcome> interpret(
    String input,
    AiInputKind kind,
    QuickEntryContext context, {
    required QuickEntryResult fallback,
  }) async {
    final client = this.client;
    if (client == null) return AiOutcome(result: fallback);
    try {
      final raw = await client.completeJson(
        system: buildAiSystemPrompt(
          context: context,
          kind: kind,
          accounts: accounts,
        ),
        user: buildAiUserMessage(input, kind),
      );
      final reading = parseAiReading(raw);
      final notes = <String>[];
      int? amountHuf;
      final amount = reading.amount;
      if (amount != null && amount > 0) {
        if (reading.isHuf) {
          amountHuf = amount.round();
        } else {
          final rate = await rates.hufPer(reading.currency);
          if (rate != null) {
            amountHuf = (amount * rate).round();
            notes.add(currencyNote(amount, reading.currency, amountHuf));
          } else {
            notes.add(
              'Nem sikerült átváltani: ${amount.toStringAsFixed(2)} '
              '${reading.currency}. Add meg az összeget forintban.',
            );
          }
        }
      }
      final result = quickEntryFromAi(
        reading,
        context,
        amountHuf: amountHuf,
        // Devizás összegnél a beépített értelmező forintnak hinné a számot.
        fallback: reading.isHuf ? fallback : _withoutAmount(fallback),
        notes: notes,
      );
      return AiOutcome(result: result, reading: reading);
    } on AiException catch (error) {
      return AiOutcome(
        result: fallback,
        error: error.message,
        retryable: error.retryable,
      );
    } on FormatException {
      return AiOutcome(
        result: fallback,
        error: 'Az AI válasza nem volt értelmezhető.',
        retryable: true,
      );
    }
  }
}

QuickEntryResult _withoutAmount(QuickEntryResult result) => QuickEntryResult(
  intent: result.intent,
  type: result.type,
  typeExplicit: result.typeExplicit,
  amount: null,
  title: result.title,
  merchant: result.merchant,
  categoryId: result.categoryId,
  categoryGuessed: result.categoryGuessed,
  date: result.date,
  dateExplicit: result.dateExplicit,
  frequency: result.frequency,
  interval: result.interval,
  targetRule: result.targetRule,
  notes: result.notes,
);
