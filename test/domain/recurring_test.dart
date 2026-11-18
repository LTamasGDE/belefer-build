import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/recurring.dart';
import 'package:flutter_test/flutter_test.dart';

RecurringRule _rule({
  Frequency frequency = Frequency.monthly,
  int interval = 1,
  CalendarDay? start,
  CalendarDay? end,
  CalendarDay? handled,
  List<AmountChange> changes = const [],
  ReminderSettings reminder = const ReminderSettings(),
}) => RecurringRule(
  id: 7,
  type: EntryType.expense,
  title: 'Lakbér',
  categoryId: 'housing',
  amount: 180000,
  frequency: frequency,
  interval: interval,
  startDate: start ?? CalendarDay(2026, 1, 31),
  endDate: end,
  handledThrough: handled,
  amountChanges: changes,
  reminder: reminder,
);

void main() {
  group('esedékességek', () {
    test('havi tétel a rövidebb hónapokban a hónap utolsó napjára esik', () {
      final rule = _rule();
      expect(rule.occurrenceAt(0), CalendarDay(2026, 1, 31));
      expect(rule.occurrenceAt(1), CalendarDay(2026, 2, 28));
      expect(rule.occurrenceAt(2), CalendarDay(2026, 3, 31));
      expect(rule.occurrenceAt(3), CalendarDay(2026, 4, 30));
    });

    test('heti és kétheti tétel', () {
      final weekly = _rule(
        frequency: Frequency.weekly,
        start: CalendarDay(2026, 11, 3),
      );
      expect(
        weekly.occurrencesBetween(
          CalendarDay(2026, 11, 1),
          CalendarDay(2026, 11, 30),
        ),
        [
          CalendarDay(2026, 11, 3),
          CalendarDay(2026, 11, 10),
          CalendarDay(2026, 11, 17),
          CalendarDay(2026, 11, 24),
        ],
      );
      final biweekly = _rule(
        frequency: Frequency.weekly,
        interval: 2,
        start: CalendarDay(2026, 11, 3),
      );
      expect(biweekly.nextOccurrence(CalendarDay(2026, 11, 4)),
          CalendarDay(2026, 11, 17));
    });

    test('éves tétel szökőnapon', () {
      final rule = _rule(
        frequency: Frequency.yearly,
        start: CalendarDay(2028, 2, 29),
      );
      expect(rule.occurrenceAt(1), CalendarDay(2029, 2, 28));
      expect(rule.occurrenceAt(4), CalendarDay(2032, 2, 29));
    });

    test('a záró dátum után nincs több esedékesség', () {
      final rule = _rule(
        start: CalendarDay(2026, 1, 5),
        end: CalendarDay(2026, 3, 10),
      );
      expect(
        rule.occurrencesBetween(
          CalendarDay(2026, 1, 1),
          CalendarDay(2026, 12, 31),
        ),
        hasLength(3),
      );
      expect(rule.nextOccurrence(CalendarDay(2026, 3, 11)), isNull);
    });

    test('csak a még nem kezelt esedékességek járnak le', () {
      final rule = _rule(
        start: CalendarDay(2026, 9, 5),
        handled: CalendarDay(2026, 10, 5),
      );
      expect(rule.dueOccurrences(CalendarDay(2026, 11, 17)), [
        CalendarDay(2026, 11, 5),
      ]);
    });

    test('összegváltozás a megadott naptól érvényes', () {
      final rule = _rule(
        start: CalendarDay(2026, 1, 5),
        changes: [
          AmountChange(from: CalendarDay(2026, 6, 1), amount: 200000),
          AmountChange(from: CalendarDay(2026, 9, 1), amount: 210000),
        ],
      );
      expect(rule.amountOn(CalendarDay(2026, 5, 5)), 180000);
      expect(rule.amountOn(CalendarDay(2026, 6, 5)), 200000);
      expect(rule.amountOn(CalendarDay(2026, 11, 5)), 210000);
      expect(rule.transactionFor(CalendarDay(2026, 7, 5)).amount, 200000);
      expect(rule.transactionFor(CalendarDay(2026, 7, 5)).recurringId, 7);
    });
  });

  test('tárolás oda-vissza', () {
    final rule = _rule(
      end: CalendarDay(2027, 1, 1),
      handled: CalendarDay(2026, 10, 31),
      changes: [AmountChange(from: CalendarDay(2026, 6, 1), amount: 1)],
      reminder: const ReminderSettings(
        enabled: true,
        daysBefore: 2,
        hour: 8,
        minute: 30,
        customText: 'Fizesd: {név}',
      ),
    );
    final copy = RecurringRule.fromMap(7, rule.toMap());
    expect(copy.toMap(), rule.toMap());
  });

  test('emberi leírás', () {
    expect(_rule(start: CalendarDay(2026, 1, 5)).describe(), 'havonta 5-én');
    expect(
      _rule(start: CalendarDay(2026, 1, 20), interval: 3).describe(),
      'negyedévente 20-án',
    );
    expect(
      _rule(
        frequency: Frequency.weekly,
        start: CalendarDay(2026, 11, 17),
      ).describe(),
      'hetente kedden',
    );
  });

  group('emlékeztetők', () {
    test('a kért nappal előbb, a kért időpontban', () {
      final rule = _rule(
        start: CalendarDay(2026, 1, 20),
        reminder: const ReminderSettings(
          enabled: true,
          daysBefore: 2,
          hour: 8,
          minute: 15,
        ),
      );
      final plan = planReminders(
        [rule],
        now: DateTime(2026, 11, 17, 12),
        enabled: true,
      );
      expect(plan.first.at, DateTime(2026, 11, 18, 8, 15));
      expect(plan.first.occurrence, CalendarDay(2026, 11, 20));
      expect(plan.first.body, contains('Lakbér'));
      expect(plan.first.body, startsWith('Holnapután'));
    });

    test('egyéni szöveg helyőrzőkkel', () {
      final rule = _rule(
        start: CalendarDay(2026, 1, 20),
        reminder: const ReminderSettings(
          enabled: true,
          customText: '{név}: {összeg}, {mikor} ({dátum})',
        ),
      );
      final body = reminderBody(
        rule,
        CalendarDay(2026, 11, 20),
        CalendarDay(2026, 11, 19),
      );
      expect(body, 'Lakbér: 180 000 Ft, holnap (november 20.)');
    });

    test('kikapcsolva nincs emlékeztető', () {
      final rule = _rule(
        reminder: const ReminderSettings(enabled: true),
      );
      expect(
        planReminders([rule], now: DateTime(2026, 11, 17), enabled: false),
        isEmpty,
      );
      expect(
        planReminders([_rule()], now: DateTime(2026, 11, 17), enabled: true),
        isEmpty,
      );
    });
  });
}
