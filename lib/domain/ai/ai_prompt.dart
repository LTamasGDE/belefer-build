import 'dart:convert';

import '../accounts.dart';
import '../calendar.dart';
import '../categories.dart';
import '../formatting.dart';
import '../models.dart';
import '../quick_entry/interpreter.dart';
import '../recurring.dart';
import '../text_fold.dart';

/// Milyen szöveget értelmez az AI.
enum AiInputKind {
  /// A felhasználó által beírt mondat (gyorsrögzítés).
  sentence,

  /// Blokk vagy számla felismert szövege.
  receipt,

  /// A Revolut alkalmazás értesítése.
  notification,

  /// Apple Pay-fizetés adatai a Parancsok automatizmusából.
  applePay,
}

/// Az AI válasza, ellenőrzés előtt.
class AiReading {
  const AiReading({
    this.status = 'ok',
    this.intent = 'record',
    this.type,
    this.amount,
    this.currency = 'HUF',
    this.title,
    this.categoryId,
    this.date,
    this.frequency,
    this.interval,
    this.targetRule,
    this.accountHint,
    this.note,
  });

  /// `ok`, `failed` (sikertelen/elutasított fizetés), `internal_transfer`
  /// (saját számlák közötti mozgás, feltöltés, átváltás) vagy
  /// `not_a_transaction` (nem pénzmozgás, pl. reklám, jóváhagyáskérés).
  final String status;

  /// `record`, `create_recurring`, `cancel_recurring`, `change_recurring`.
  final String intent;
  final EntryType? type;

  /// Az eredeti pénznemben (tört is lehet).
  final double? amount;
  final String currency;
  final String? title;
  final String? categoryId;
  final CalendarDay? date;
  final Frequency? frequency;
  final int? interval;
  final String? targetRule;
  final String? accountHint;
  final String? note;

  bool get isHuf => currency.toUpperCase() == 'HUF';
}

/// A rendszerutasítás: a feladat, a mai nap, a kategóriák, a számlák, az
/// ismétlődő tételek és a felhasználó korábbi besorolásai.
String buildAiSystemPrompt({
  required QuickEntryContext context,
  required AiInputKind kind,
  List<Account> accounts = const [],
}) {
  final today = context.today;
  final buffer = StringBuffer()
    ..writeln(
      'You are the bookkeeping engine of "Belefér", a Hungarian personal '
      'finance app. Read the input and answer with exactly ONE JSON object, '
      'no other text.',
    )
    ..writeln(
      'Today is ${today.toIso()} (${_weekdayNames[DateTime.utc(today.year, today.month, today.day).weekday - 1]}). '
      'Resolve relative dates (tegnap, pénteken, múlt héten, 3 napja, '
      'nov. 3.) to YYYY-MM-DD. Never return a future date for a record, '
      'except for the first due date of a new recurring item.',
    )
    ..writeln(
      'The input may contain typos, missing accents, slang, abbreviations, '
      'any word order, Hungarian number words (kétezer-ötszáz), "12e" = '
      '12000, "2,5k" = 2500, "1,5 millió" = 1500000. Quantities like "3 kg" '
      'or "2 db" are not the amount.',
    )
    ..writeln()
    ..writeln('Expense categories (id: name):');
  for (final category in categoriesFor(EntryType.expense)) {
    buffer.writeln('- ${category.id}: ${category.name}');
  }
  buffer.writeln('Income categories (id: name):');
  for (final category in categoriesFor(EntryType.income)) {
    buffer.writeln('- ${category.id}: ${category.name}');
  }

  final learned = _learnedExamples(context.history);
  if (learned.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln(
        "The user's earlier entries (title → category id); follow these "
        'habits for similar merchants:',
      );
    for (final line in learned) {
      buffer.writeln('- $line');
    }
  }

  if (context.rules.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Existing recurring items (title, amount, schedule):');
    for (final rule in context.rules.take(40)) {
      buffer.writeln(
        '- ${rule.title}, ${rule.amountOn(today)} Ft, ${rule.describe()}',
      );
    }
  }

  if (accounts.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Accounts/cards of the user (name: recognizing words):');
    for (final account in accounts) {
      buffer.writeln(
        '- ${account.name} (${account.kind.label})'
        '${account.matchers.isEmpty ? '' : ': ${account.matchers.join(', ')}'}',
      );
    }
  }

  buffer
    ..writeln()
    ..writeln(switch (kind) {
      AiInputKind.sentence =>
        'INPUT: a short sentence the user typed to record money. It can '
            'also create a recurring item ("Netflix havi 4990", "minden hónap '
            '5-én lakbér 180e" → create_recurring), cancel one ("lemondtam a '
            'Spotifyt" → cancel_recurring, target_rule = exact existing title) '
            'or change its amount ("mostantól 190 ezer a lakbér" → '
            'change_recurring). Spending is expense; salary, gifts received, '
            'refunds, selling things are income.',
      AiInputKind.receipt =>
        'INPUT: OCR text of a shop receipt or an invoice (maybe a '
            'screenshot of an e-invoice). The amount is the grand total to pay '
            '(Összesen / Fizetendő / Végösszeg / Bruttó végösszeg), not VAT, '
            'not net, not change. Title = the shop or seller name, short '
            '(without Kft./Zrt.). Date = purchase or invoice date. Always '
            'expense, intent record.',
      AiInputKind.notification =>
        'INPUT: a push notification of the Revolut banking app. Decide the '
            'status carefully: a completed card payment or transfer sent = '
            'ok + expense; money received, refund, cashback = ok + income; '
            'declined, failed, rejected, insufficient funds, reversed, '
            'cancelled = failed; moving money to savings/vault/pocket, '
            'exchanging currency, topping up, transfers between own accounts '
            '= internal_transfer; requests to confirm a payment, security '
            'codes, marketing, reports, anything that is not a completed '
            'money movement = not_a_transaction. Title = merchant or person, '
            'short. Copy any card name, last card digits or account words '
            '(e.g. joint, közös, savings) into account_hint.',
      AiInputKind.applePay =>
        'INPUT: an Apple Pay card payment recorded by iOS (amount, '
            'merchant, card name). It is an expense, intent record; give a '
            'clean short title for the merchant and the best category. Put '
            'the card name into account_hint.',
    })
    ..writeln()
    ..writeln('JSON keys:')
    ..writeln(
      '{"status": "ok"|"failed"|"internal_transfer"|"not_a_transaction", '
      '"intent": "record"|"create_recurring"|"cancel_recurring"|"change_recurring", '
      '"type": "expense"|"income"|null, '
      '"amount": number|null (in the original currency), '
      '"currency": ISO 4217 code, default "HUF" (Ft, forint = HUF; € = EUR), '
      '"title": short Hungarian title, max 40 characters, or null, '
      '"category_id": one of the ids above or null, '
      '"date": "YYYY-MM-DD" only if the input states or implies a date, else null, '
      '"frequency": "weekly"|"monthly"|"yearly"|null, '
      '"interval": integer|null (2 = every second week/month), '
      '"target_rule": exact title of an existing recurring item or null, '
      '"account_hint": string|null, '
      '"note": short Hungarian remark if something is uncertain, else null}',
    );
  return buffer.toString();
}

/// A felhasználói üzenet.
String buildAiUserMessage(String input, AiInputKind kind) => switch (kind) {
  AiInputKind.sentence => 'Sentence: $input',
  AiInputKind.receipt => 'Receipt text:\n$input',
  AiInputKind.notification => 'Revolut notification:\n$input',
  AiInputKind.applePay => 'Apple Pay payment:\n$input',
};

/// Az AI válaszának értelmezése (megengedően: a kódblokk-jelöléseket és a
/// felesleges szöveget eldobja).
AiReading parseAiReading(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('Az AI válasza nem JSON.');
  }
  final decoded = jsonDecode(raw.substring(start, end + 1));
  if (decoded is! Map)
    throw const FormatException('Az AI válasza nem objektum.');
  final map = decoded.cast<String, Object?>();

  String? text(String key) {
    final value = map[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed.toLowerCase() == 'null' ? null : trimmed;
  }

  double? number(String key) {
    final value = map[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value
          .replaceAll(RegExp(r'[\s ]'), '')
          .replaceAll(',', '.');
      return double.tryParse(cleaned);
    }
    return null;
  }

  CalendarDay? date;
  final dateText = text('date');
  if (dateText != null) {
    try {
      date = CalendarDay.parse(dateText.substring(0, 10));
    } on Object {
      date = null;
    }
  }

  final typeText = text('type');
  final frequencyText = text('frequency');
  final interval = number('interval')?.round();
  return AiReading(
    status: text('status') ?? 'ok',
    intent: text('intent') ?? 'record',
    type: switch (typeText) {
      'expense' => EntryType.expense,
      'income' => EntryType.income,
      _ => null,
    },
    amount: number('amount'),
    currency: (text('currency') ?? 'HUF').toUpperCase(),
    title: text('title'),
    categoryId: text('category_id'),
    date: date,
    frequency: switch (frequencyText) {
      'weekly' => Frequency.weekly,
      'monthly' => Frequency.monthly,
      'yearly' => Frequency.yearly,
      _ => null,
    },
    interval: interval != null && interval >= 1 && interval <= 12
        ? interval
        : null,
    targetRule: text('target_rule'),
    accountHint: text('account_hint'),
    note: text('note'),
  );
}

/// Az AI válaszából ellenőrzött gyorsrögzítési eredmény. A hiányzó adatokat
/// a beépített értelmező eredményéből ([fallback]) pótolja.
QuickEntryResult quickEntryFromAi(
  AiReading reading,
  QuickEntryContext context, {
  required int? amountHuf,
  QuickEntryResult? fallback,
  List<String> notes = const [],
}) {
  final today = context.today;
  RecurringRule? target;
  if (reading.targetRule != null) {
    final key = foldForMatching(reading.targetRule!);
    for (final rule in context.rules) {
      if (foldForMatching(rule.title) == key) target = rule;
    }
    if (target == null) {
      for (final rule in context.rules) {
        final title = foldForMatching(rule.title);
        if (title.contains(key) || key.contains(title)) target = rule;
      }
    }
  }

  var intent = switch (reading.intent) {
    'create_recurring' => QuickIntent.createRecurring,
    'cancel_recurring' => QuickIntent.cancelRecurring,
    'change_recurring' => QuickIntent.changeRecurring,
    _ => QuickIntent.record,
  };
  if ((intent == QuickIntent.cancelRecurring ||
          intent == QuickIntent.changeRecurring) &&
      target == null) {
    target = fallback?.targetRule;
  }
  if (intent == QuickIntent.changeRecurring && target == null) {
    intent = QuickIntent.createRecurring;
  }

  final category = reading.categoryId == null
      ? null
      : categoryById(reading.categoryId!);
  final type =
      target?.type ??
      reading.type ??
      category?.type ??
      fallback?.type ??
      EntryType.expense;
  final validCategory = category != null && category.type == type
      ? category
      : null;
  final categoryId =
      target?.categoryId ??
      validCategory?.id ??
      (fallback != null && !fallback.categoryGuessed && fallback.type == type
          ? fallback.categoryId
          : CategoryCatalog.fallbackIdFor(type));

  var title = reading.title ?? fallback?.title;
  if (target != null &&
      (intent == QuickIntent.cancelRecurring ||
          intent == QuickIntent.changeRecurring)) {
    title = target.title;
  }
  if (title != null && title.length > 40) title = title.substring(0, 40).trim();

  var date = reading.date ?? fallback?.date ?? today;
  if (intent == QuickIntent.record && date.compareTo(today) > 0) date = today;
  if (intent == QuickIntent.changeRecurring && reading.date == null) {
    date = target?.nextOccurrence(today) ?? today;
  }

  final amount = amountHuf ?? fallback?.amount;
  return QuickEntryResult(
    intent: intent,
    type: type,
    typeExplicit: true,
    amount: amount != null && amount > 0 ? amount : null,
    title: title,
    merchant: reading.title,
    categoryId: categoryId,
    categoryGuessed: validCategory == null && target == null,
    date: date,
    dateExplicit: reading.date != null || (fallback?.dateExplicit ?? false),
    frequency: intent == QuickIntent.createRecurring
        ? (reading.frequency ?? fallback?.frequency ?? Frequency.monthly)
        : null,
    interval: reading.interval ?? fallback?.interval ?? 1,
    targetRule: target,
    notes: [...notes, ?reading.note],
    fromAi: true,
  );
}

List<String> _learnedExamples(List<Transaction> history) {
  final recent = [...history]..sort((a, b) => b.date.compareTo(a.date));
  final seen = <String>{};
  final lines = <String>[];
  for (final transaction in recent) {
    final key = foldForMatching(transaction.title);
    if (key.isEmpty || !seen.add(key)) continue;
    if (categoryById(transaction.categoryId) == null) continue;
    lines.add('${transaction.title} → ${transaction.categoryId}');
    if (lines.length >= 40) break;
  }
  return lines;
}

const List<String> _weekdayNames = [
  'hétfő',
  'kedd',
  'szerda',
  'csütörtök',
  'péntek',
  'szombat',
  'vasárnap',
];

/// Rövid szöveg egy deviza-összegről: „12,50 EUR ≈ 4 913 Ft”.
String currencyNote(double amount, String currency, int huf) {
  final original = amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2).replaceAll('.', ',');
  return '$original $currency ≈ ${formatForint(huf)} (ECB-árfolyam)';
}
