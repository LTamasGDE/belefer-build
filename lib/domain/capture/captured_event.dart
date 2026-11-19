import '../calendar.dart';
import '../model/belefer_model.dart';
import '../models.dart';
import '../quick_entry/amount_parser.dart';
import '../quick_entry/interpreter.dart';
import '../quick_entry/tokens.dart';
import '../text_fold.dart';

/// Honnan érkezett az automatikusan rögzítendő tétel.
enum CaptureSource {
  revolut('revolut', 'Revolut-értesítés'),
  applePay('applepay', 'Apple Pay');

  const CaptureSource(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static CaptureSource fromStorage(Object? value) {
    for (final source in CaptureSource.values) {
      if (source.storageKey == value) return source;
    }
    return CaptureSource.revolut;
  }
}

/// Egy beérkezett értesítés vagy Apple Pay-fizetés, feldolgozás előtt.
class CapturedEvent {
  const CapturedEvent({
    required this.id,
    required this.source,
    required this.receivedAt,
    this.title = '',
    this.text = '',
    this.card,
    this.amountText,
    this.merchant,
  });

  /// A platform sorából (Android: értesítés, iOS: App Intent).
  factory CapturedEvent.fromMap(Map<Object?, Object?> map) {
    String? text(String key) {
      final value = map[key];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final time = map['time'];
    return CapturedEvent(
      id: text('id') ?? '${map['time']}',
      source: CaptureSource.fromStorage(map['source']),
      receivedAt: time is num
          ? DateTime.fromMillisecondsSinceEpoch(time.toInt())
          : DateTime.now(),
      title: text('title') ?? '',
      text: text('text') ?? '',
      card: text('card'),
      amountText: text('amount'),
      merchant: text('merchant'),
    );
  }

  final String id;
  final CaptureSource source;
  final DateTime receivedAt;

  /// Az értesítés címe és szövege (Revolut).
  final String title;
  final String text;

  /// Apple Pay: a kártya neve a Walletben, az összeg és a kereskedő.
  final String? card;
  final String? amountText;
  final String? merchant;

  CalendarDay get day => CalendarDay.fromDateTime(receivedAt);

  /// A modellnek és a felismerésnek átadott szöveg.
  String get description => switch (source) {
    CaptureSource.revolut => [
      title,
      text,
    ].where((part) => part.isNotEmpty).join('\n'),
    CaptureSource.applePay => [
      if (amountText != null) 'Összeg: $amountText',
      if (merchant != null) 'Kereskedő: $merchant',
      if (card != null) 'Kártya: $card',
    ].join('\n'),
  };

  /// A számla felismeréséhez használt szöveg.
  String get accountText => [?card, title, text, ?merchant].join(' ');
}

/// A beépített (internet nélküli) besorolás eredménye.
class OfflineCaptureReading {
  const OfflineCaptureReading({
    required this.status,
    required this.result,
    this.currency = 'HUF',
    this.foreignAmount,
  });

  final String status;
  final QuickEntryResult result;
  final String currency;
  final double? foreignAmount;
}

const List<String> _failedWords = [
  'declin',
  'elutasit',
  'sikertelen',
  'nem sikerult',
  'insufficient',
  'failed',
  'fedezet',
  'rejected',
  'elegtelen',
  'megszakad',
  'visszautasit',
  'reverted',
  'cancelled',
  'megszakitott',
  'torolve',
];

const List<String> _internalWords = [
  'savings',
  'megtakaritas',
  'vault',
  'pocket',
  'persely',
  'exchanged',
  'atvaltottal',
  'atvaltas',
  'atvaltott',
  'money added',
  'top up',
  'topped up',
  'feltoltes',
  'feltoltotted',
  'feltoltve',
  'between your accounts',
  'sajat szamlak',
];

const List<String> _notTransactionWords = [
  'confirm',
  'jovahagy',
  'erosits',
  'erositsd',
  'kod',
  'code',
  'verification',
  'ellenoriz',
  'review',
  'offer',
  'ajanlat',
  'report',
  'kimutatas',
  'osszefoglalo',
];

const List<String> _incomeWords = [
  'received',
  'kaptal',
  'erkezett',
  'jovairas',
  'jovairtunk',
  'refund',
  'visszaterites',
  'visszaterult',
  'cashback',
  'payment from',
  'utalt neked',
];

/// Internet nélküli besorolás: kulcsszavak a sikertelen fizetésre, a saját
/// számlák közötti mozgásra és a nem pénzmozgásra; a többi a beépített
/// gyorsrögzítési értelmezővel.
OfflineCaptureReading classifyOffline(
  CapturedEvent event,
  QuickEntryContext context,
) {
  final folded = foldForMatching(event.description);
  bool hasAny(List<String> words) => words.any(folded.contains);

  final sentence = event.source == CaptureSource.applePay
      ? '${event.merchant ?? ''} ${event.amountText ?? ''}'
      : '${event.title} ${event.text}';
  var result = interpretQuickEntry(sentence, context);
  final (currency, foreign) = _detectCurrency(
    event.source == CaptureSource.applePay
        ? (event.amountText ?? '')
        : sentence,
  );
  if (event.source == CaptureSource.applePay && event.merchant != null) {
    result = _withTitle(result, event.merchant!, expense: true);
  }

  String status;
  // A saját modell az értesítés egészéből dönt; ha bizonytalan, a
  // kulcsszavak.
  final model = currentModel;
  final modelStatus =
      model != null && event.source == CaptureSource.revolut
      ? model.classify('status', event.description)
      : null;
  if (event.source == CaptureSource.applePay) {
    status = 'ok';
  } else if (modelStatus != null && modelStatus.confidence >= 0.6) {
    status = switch (modelStatus.best) {
      'failed' => 'failed',
      'internal' => 'internal_transfer',
      'other' => 'not_a_transaction',
      _ => 'ok',
    };
    if (status == 'ok') {
      final type = modelStatus.best == 'income'
          ? EntryType.income
          : EntryType.expense;
      if (result.type != type) result = _withType(result, type);
    }
  } else if (hasAny(_failedWords)) {
    status = 'failed';
  } else if (hasAny(_internalWords)) {
    status = 'internal_transfer';
  } else if (!result.hasAmount && foreign == null) {
    status = 'not_a_transaction';
  } else if (hasAny(_notTransactionWords) && !folded.contains('paid')) {
    status = 'not_a_transaction';
  } else {
    status = 'ok';
    if (hasAny(_incomeWords)) {
      result = _withType(result, EntryType.income);
    } else if (result.type == EntryType.income && !result.categoryGuessed) {
      // Kártyás fizetésnél a bevételi kategória téves (pl. „Fizetés” szó).
      result = _withType(result, EntryType.expense);
    }
  }
  if (event.source == CaptureSource.revolut &&
      status == 'ok' &&
      !result.hasAmount &&
      foreign == null) {
    status = 'not_a_transaction';
  }
  return OfflineCaptureReading(
    status: status,
    result: result,
    currency: currency,
    foreignAmount: foreign,
  );
}

/// Devizás összeg felismerése (€, $, £, EUR, USD…); forintnál `('HUF', null)`.
(String, double?) _detectCurrency(String text) {
  const symbols = {'€': 'EUR', r'$': 'USD', '£': 'GBP'};
  // Csak nagybetűvel: az angol „try” ne legyen török líra.
  final codes = RegExp(
    r'\b(EUR|USD|GBP|CHF|CZK|PLN|RON|SEK|NOK|DKK|JPY|TRY)\b',
  );
  String? currency;
  var at = -1;
  var tokenLength = 1;
  for (final entry in symbols.entries) {
    final index = text.indexOf(entry.key);
    if (index >= 0) {
      currency = entry.value;
      at = index;
    }
  }
  if (currency == null) {
    final code = codes.firstMatch(text);
    if (code == null) return ('HUF', null);
    currency = code.group(1);
    at = code.start;
    tokenLength = 3;
  }
  // A pénznem melletti szám (utána: „€4.50”, „USD 12”; előtte: „12,30 EUR”).
  final after = text.substring(at + tokenLength);
  final afterMatch = RegExp(r'^\s?(\d[\d  .,]*)').firstMatch(after);
  if (afterMatch != null) {
    return (currency!, _parseLooseNumber(afterMatch.group(1)!));
  }
  final before = text.substring(0, at);
  final beforeMatch = RegExp(r'(\d[\d  .,]*)\s?$').firstMatch(before);
  return (
    currency!,
    beforeMatch == null ? null : _parseLooseNumber(beforeMatch.group(1)!),
  );
}

/// Az első szám a szövegben, ezres elválasztókkal és tizedesekkel:
/// „4 590”, „4.590”, „1,234.56”, „1.234,56”, „4,50”.
double? _parseLooseNumber(String text) {
  final match = RegExp(r'\d[\d  .,]*').firstMatch(text);
  if (match == null) return null;
  var raw = match.group(0)!.replaceAll(RegExp(r'[  ]'), '');
  raw = raw.replaceAll(RegExp(r'[.,]+$'), '');
  final lastSeparator = raw.lastIndexOf(RegExp(r'[.,]'));
  if (lastSeparator >= 0 && raw.length - lastSeparator - 1 <= 2) {
    raw =
        '${raw.substring(0, lastSeparator).replaceAll(RegExp(r'[.,]'), '')}.'
        '${raw.substring(lastSeparator + 1)}';
  } else {
    raw = raw.replaceAll(RegExp(r'[.,]'), '');
  }
  return double.tryParse(raw);
}

/// Forintösszeg az Apple Pay-ből érkező szövegből („4 590 Ft”,
/// „HUF 4,590.00”, „4.590 Ft”).
int? parseHufAmount(String text) {
  final value = _parseLooseNumber(text);
  if (value != null && value > 0) return value.round();
  final tokens = tokenize(text);
  final pick = pickAmount(
    findAmountCandidates([for (final token in tokens) token.folded]),
  );
  return pick?.value;
}

QuickEntryResult _withType(QuickEntryResult result, EntryType type) =>
    QuickEntryResult(
      intent: QuickIntent.record,
      type: type,
      typeExplicit: true,
      amount: result.amount,
      title: result.title,
      merchant: result.merchant,
      categoryId: result.type == type
          ? result.categoryId
          : (type == EntryType.income ? 'other_income' : 'other_expense'),
      categoryGuessed: result.type != type || result.categoryGuessed,
      date: result.date,
      dateExplicit: result.dateExplicit,
      notes: result.notes,
    );

QuickEntryResult _withTitle(
  QuickEntryResult result,
  String title, {
  required bool expense,
}) {
  final type = expense ? EntryType.expense : result.type;
  final keepCategory = result.type == type && !result.categoryGuessed;
  return QuickEntryResult(
    intent: QuickIntent.record,
    type: type,
    typeExplicit: true,
    amount: result.amount,
    title: result.title != null && !result.categoryGuessed
        ? result.title
        : title,
    merchant: title,
    categoryId: keepCategory ? result.categoryId : 'other_expense',
    categoryGuessed: !keepCategory,
    date: result.date,
    dateExplicit: result.dateExplicit,
    notes: result.notes,
  );
}

/// A napló egy bejegyzése: mi érkezett, és mi lett vele.
class CaptureLogEntry {
  const CaptureLogEntry({
    required this.time,
    required this.source,
    required this.raw,
    required this.outcome,
    this.detail = '',
    this.amount,
    this.merchantKey = '',
    this.transactionId,
  });

  factory CaptureLogEntry.fromMap(Map<Object?, Object?> map) {
    final time = map['time'];
    final amount = map['amount'];
    final transaction = map['tx'];
    return CaptureLogEntry(
      time: time is num
          ? DateTime.fromMillisecondsSinceEpoch(time.toInt())
          : DateTime.fromMillisecondsSinceEpoch(0),
      source: CaptureSource.fromStorage(map['source']),
      raw: (map['raw'] as String?) ?? '',
      outcome: CaptureOutcome.fromStorage(map['outcome']),
      detail: (map['detail'] as String?) ?? '',
      amount: amount is num ? amount.toInt() : null,
      merchantKey: (map['merchant'] as String?) ?? '',
      transactionId: transaction is num ? transaction.toInt() : null,
    );
  }

  final DateTime time;
  final CaptureSource source;
  final String raw;
  final CaptureOutcome outcome;
  final String detail;
  final int? amount;
  final String merchantKey;
  final int? transactionId;

  Map<String, Object?> toMap() => <String, Object?>{
    'time': time.millisecondsSinceEpoch,
    'source': source.storageKey,
    'raw': raw.length > 400 ? raw.substring(0, 400) : raw,
    'outcome': outcome.storageKey,
    'detail': detail,
    'amount': amount,
    'merchant': merchantKey,
    'tx': transactionId,
  };
}

/// Mi lett egy beérkezett eseménnyel.
enum CaptureOutcome {
  booked('booked', 'Rögzítve'),
  failed('failed', 'Sikertelen fizetés – nem rögzítve'),
  ignored('ignored', 'Nem pénzmozgás – kihagyva'),
  transfer('transfer', 'Saját számlák közötti mozgás – kihagyva'),
  duplicate('duplicate', 'Ismétlődő értesítés – kihagyva'),
  unclear('unclear', 'Nem derült ki az összeg – nem rögzítve');

  const CaptureOutcome(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static CaptureOutcome fromStorage(Object? value) {
    for (final outcome in CaptureOutcome.values) {
      if (outcome.storageKey == value) return outcome;
    }
    return CaptureOutcome.ignored;
  }
}
