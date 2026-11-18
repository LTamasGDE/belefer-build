import 'calendar.dart';
import 'models.dart';
import 'recurring.dart';

/// Bemutató adatok a körbevezetéshez, ha a felhasználónak még nincs saját
/// adata. Csak a memóriában élnek, sosem kerülnek mentésre.
class DemoData {
  DemoData._(this.transactions, this.templates, this.rules);

  factory DemoData.build(CalendarDay today) {
    CalendarDay day(int monthOffset, int dayOfMonth) {
      final month = YearMonth(today.year, today.month + monthOffset);
      final clamped = dayOfMonth > month.daysInMonth
          ? month.daysInMonth
          : dayOfMonth;
      return CalendarDay(month.year, month.month, clamped);
    }

    CalendarDay recent(int daysAgo) =>
        CalendarDay(today.year, today.month, today.day - daysAgo);

    var nextId = -1;
    Transaction t(
      EntryType type,
      String title,
      int amount,
      String category,
      CalendarDay date, {
      int? recurringId,
    }) => Transaction(
      id: nextId--,
      type: type,
      title: title,
      amount: amount,
      categoryId: category,
      date: date,
      recurringId: recurringId,
    );

    const out = EntryType.expense;
    const income = EntryType.income;
    final firstOfMonth = day(0, 1);
    final transactions = <Transaction>[
      t(income, 'Fizetés', 420000, 'salary', day(0, 1), recurringId: -3),
      t(out, 'Lakbér', 180000, 'housing', day(0, 1), recurringId: -1),
      t(out, 'Netflix', 4990, 'subscriptions', day(0, 1), recurringId: -2),
      t(out, 'Lidl', 12450, 'groceries', recent(1)),
      t(out, 'Kávé', 890, 'dining', recent(0)),
      t(out, 'Bérlet', 8950, 'transport', recent(2)),
      t(out, 'Mozi', 3200, 'entertainment', recent(3)),
      t(out, 'Tesco', 8730, 'groceries', recent(5)),
      t(out, 'Ebéd', 2490, 'dining', recent(6)),
      t(out, 'Villanyszámla', 9800, 'utilities', recent(8)),
      t(out, 'Gyógyszertár', 3400, 'health', recent(9)),
      // Előző hónapok, hogy az előrejelzés is mutasson valamit.
      t(income, 'Fizetés', 420000, 'salary', day(-1, 1), recurringId: -3),
      t(out, 'Lakbér', 180000, 'housing', day(-1, 1), recurringId: -1),
      t(out, 'Bevásárlás', 64000, 'groceries', day(-1, 15)),
      t(out, 'Étterem', 18000, 'dining', day(-1, 20)),
    ]..removeWhere((transaction) => transaction.date.compareTo(today) > 0);

    final templates = [
      EntryTemplate(
        id: -1,
        type: out,
        title: 'Lakbér',
        categoryId: 'housing',
        amount: 180000,
      ),
      EntryTemplate(
        id: -2,
        type: income,
        title: 'Fizetés',
        categoryId: 'salary',
        amount: 420000,
      ),
      EntryTemplate(id: -3, type: out, title: 'Kávé', categoryId: 'dining'),
    ];

    final reminder = const ReminderSettings(enabled: true);
    final rules = [
      RecurringRule(
        id: -1,
        type: out,
        title: 'Lakbér',
        categoryId: 'housing',
        amount: 180000,
        startDate: firstOfMonth,
        reminder: reminder,
        handledThrough: firstOfMonth,
      ),
      RecurringRule(
        id: -2,
        type: out,
        title: 'Netflix',
        categoryId: 'subscriptions',
        amount: 4990,
        startDate: firstOfMonth,
        handledThrough: firstOfMonth,
      ),
      RecurringRule(
        id: -3,
        type: income,
        title: 'Fizetés',
        categoryId: 'salary',
        amount: 420000,
        startDate: firstOfMonth,
        handledThrough: firstOfMonth,
      ),
      RecurringRule(
        id: -4,
        type: out,
        title: 'Edzőterem',
        categoryId: 'health',
        amount: 15000,
        startDate: CalendarDay(today.year, today.month, today.day + 5),
        autoBook: false,
        reminder: reminder,
      ),
    ];
    return DemoData._(transactions, templates, rules);
  }

  final List<Transaction> transactions;
  final List<EntryTemplate> templates;
  final List<RecurringRule> rules;
}
