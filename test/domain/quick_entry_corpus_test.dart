import 'dart:io';

import 'package:belefer/domain/accounts.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/model/belefer_model.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:belefer/domain/recurring.dart';
import 'package:flutter_test/flutter_test.dart';

/// A gyorsrögzítés mondatgyűjteménye (test/fixtures/quick_entry_*.txt):
/// több száz valósághű mondat elvárt eredménnyel, esetcsoportonként.
const _accounts = [
  Account(id: 1, name: 'Saját', matchers: ['revolut'], isDefault: true),
  Account(id: 2, name: 'Megtakarítás', kind: AccountKind.savings),
  Account(id: 3, name: 'Közös', kind: AccountKind.shared),
];

RecurringRule _rule(
  int id,
  String title,
  String category,
  int amount, {
  EntryType type = EntryType.expense,
}) => RecurringRule(
  id: id,
  type: type,
  title: title,
  categoryId: category,
  amount: amount,
  frequency: Frequency.monthly,
  startDate: CalendarDay(2026, 1, 5),
);

void main() {
  currentModel = BeleferModel.parse(
    File('assets/model/belefer_model.bin').readAsBytesSync(),
  );
  final context = QuickEntryContext(
    today: CalendarDay(2026, 11, 20),
    accounts: _accounts,
    rules: [
      _rule(1, 'Netflix', 'subscriptions', 4990),
      _rule(2, 'Lakbér', 'housing', 180000),
      _rule(3, 'Spotify', 'subscriptions', 1990),
      _rule(4, 'Edzőterem bérlet', 'entertainment', 15000),
      _rule(5, 'Fizetés', 'salary', 450000, type: EntryType.income),
    ],
  );
  for (final file in const [
    'test/fixtures/quick_entry_corpus.txt',
    'test/fixtures/quick_entry_holdout.txt',
  ]) {
    group(file.split('/').last, () {
      var section = '';
      for (final line in File(file).readAsLinesSync()) {
        if (line.startsWith('## ')) section = line.substring(3);
        if (line.startsWith('#') || line.trim().isEmpty) continue;
        final parts = line.split('||');
        final text = parts[0].trim();
        final expected = <String, String>{};
        for (final pair in parts[1].split(';')) {
          final item = pair.trim();
          if (item.isEmpty) continue;
          final at = item.indexOf('=');
          expected[item.substring(0, at)] = item.substring(at + 1);
        }
        test('$section: $text', () {
          final result = interpretQuickEntry(text, context);
          final errors = checkResult(result, expected, context);
          expect(errors, isEmpty, reason: describe(result));
        });
      }
    });
  }
}

String describe(QuickEntryResult r) {
  final account = r.accountId == null
      ? ''
      : ' acc=${_accounts.firstWhere((a) => a.id == r.accountId).name}';
  return '${r.intent.name} ${r.type == EntryType.income ? 'b' : 'k'} '
      'a=${r.amount} "${r.title}" ${r.categoryId} ${r.date}$account'
      '${r.intent == QuickIntent.transfer ? ' ${r.transferFrom}→${r.transferTo}' : ''}'
      '${r.currency != null ? ' ${r.foreignAmount} ${r.currency}' : ''}'
      '${r.items.length > 1 ? ' n=${r.items.length}' : ''}'
      '${r.frequency != null ? ' f=${r.frequency!.name}/${r.interval}' : ''}'
      '${r.targetRule != null ? ' rule=${r.targetRule!.title}' : ''}';
}

List<String> checkResult(
  QuickEntryResult r,
  Map<String, String> expect,
  QuickEntryContext context,
) {
  final errors = <String>[];
  bool oneOf(String? actual, String expected) =>
      expected.split('/').any((option) => option == actual);
  for (final MapEntry(:key, :value) in expect.entries) {
    switch (key) {
      case 'i':
        final name = switch (r.intent) {
          QuickIntent.record => 'record',
          QuickIntent.createRecurring => 'recurring',
          QuickIntent.cancelRecurring => 'cancel',
          QuickIntent.changeRecurring => 'change',
          QuickIntent.transfer => 'transfer',
          QuickIntent.question => 'question',
        };
        if (name != value) errors.add('szándék $name≠$value');
      case 't':
        final actual = r.type == EntryType.income ? 'b' : 'k';
        if (actual != value) errors.add('típus $actual≠$value');
        if (r.intent == QuickIntent.transfer) errors.add('átvezetésnek vette');
      case 'a':
        final want = value == '-' ? null : int.parse(value);
        if (r.amount != want) errors.add('összeg ${r.amount}≠$value');
      case 'c':
        if (!oneOf(r.categoryId, value)) {
          errors.add('kategória ${r.categoryId}≠$value');
        }
        if (r.intent == QuickIntent.transfer) errors.add('átvezetésnek vette');
      case 'ti':
        if (!oneOf(r.title, value)) errors.add('megnevezés "${r.title}"≠$value');
      case 'd':
        if (r.date.toString() != value) errors.add('dátum ${r.date}≠$value');
      case 'acc':
        final name = r.accountId == null
            ? null
            : context.accounts.firstWhere((a) => a.id == r.accountId).name;
        if (name != value) errors.add('számla $name≠$value');
      case 'from':
        if (r.transferFrom != value) errors.add('honnan ${r.transferFrom}≠$value');
      case 'to':
        if (r.transferTo != value) errors.add('hová ${r.transferTo}≠$value');
      case 'cur':
        if (r.currency != value) errors.add('deviza ${r.currency}≠$value');
      case 'fa':
        if (r.foreignAmount != double.parse(value)) {
          errors.add('devizaösszeg ${r.foreignAmount}≠$value');
        }
      case 'n':
        final count = r.items.isEmpty ? 1 : r.items.length;
        if (count != int.parse(value)) errors.add('tételszám $count≠$value');
        if (r.items.isNotEmpty) {
          for (final MapEntry(key: k2, value: v2) in expect.entries) {
            if (k2 == 'd' &&
                r.items.any((item) => item.date.toString() != v2)) {
              errors.add('altétel dátuma');
            }
          }
        }
      case 'f':
        if (r.frequency?.name != value) {
          errors.add('gyakoriság ${r.frequency?.name}≠$value');
        }
      case 'iv':
        if (r.interval != int.parse(value)) {
          errors.add('köz ${r.interval}≠$value');
        }
      case 'rule':
        if (r.targetRule?.title != value) {
          errors.add('szabály ${r.targetRule?.title}≠$value');
        }
      case 'sure':
        if (value == 'no' && r.guessed.isEmpty && r.isComplete) {
          errors.add('nem jelzi a bizonytalanságot');
        }
      default:
        errors.add('ismeretlen kulcs: $key');
    }
  }
  // Ahol nincs „sure”, egy tisztán kereskedős vagy kulcsszavas találatnál
  // ne legyen tipp-jelzés a megnevezésen sem (külön nem ellenőrizzük).
  return errors;
}
