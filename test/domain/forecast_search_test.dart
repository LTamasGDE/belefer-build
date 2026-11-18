import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/categories.dart';
import 'package:belefer/domain/forecast.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/recurring.dart';
import 'package:belefer/domain/search.dart';
import 'package:belefer/domain/text_fold.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(
  int id,
  EntryType type,
  String title,
  int amount,
  String category,
  CalendarDay date, {
  String? note,
  int? recurringId,
}) => Transaction(
  id: id,
  type: type,
  title: title,
  amount: amount,
  categoryId: category,
  date: date,
  note: note,
  recurringId: recurringId,
);

void main() {
  final today = CalendarDay(2026, 11, 17);

  group('előrejelzés', () {
    final rent = RecurringRule(
      id: 1,
      type: EntryType.expense,
      title: 'Lakbér',
      categoryId: 'housing',
      amount: 180000,
      startDate: CalendarDay(2026, 1, 25),
    );
    final salary = RecurringRule(
      id: 2,
      type: EntryType.income,
      title: 'Fizetés',
      categoryId: 'salary',
      amount: 400000,
      startDate: CalendarDay(2026, 1, 10),
      handledThrough: CalendarDay(2026, 11, 10),
    );
    final transactions = [
      _t(
        1,
        EntryType.income,
        'Fizetés',
        400000,
        'salary',
        CalendarDay(2026, 11, 10),
        recurringId: 2,
      ),
      _t(
        2,
        EntryType.expense,
        'Lidl',
        17000,
        'groceries',
        CalendarDay(2026, 11, 3),
      ),
      _t(
        3,
        EntryType.expense,
        'Mozi',
        17000,
        'entertainment',
        CalendarDay(2026, 11, 12),
      ),
    ];

    test('az aktuális hónapban a várható tételekkel és a napi átlaggal', () {
      final forecast = forecastMonth(
        transactions: transactions,
        rules: [rent, salary],
        month: YearMonth(2026, 11),
        today: today,
      )!;
      expect(forecast.actualIncome, 400000);
      expect(forecast.actualExpense, 34000);
      expect(forecast.upcoming.map((u) => u.rule.title), ['Lakbér']);
      expect(forecast.upcomingExpense, 180000);
      expect(forecast.remainingDays, 13);
      expect(forecast.basedOnHistory, isFalse);
      // 34 000 Ft / 17 nap = 2000 Ft/nap, 13 napra 26 000 Ft.
      expect(forecast.projectedVariableExpense, 26000);
      expect(forecast.projectedBalance, 400000 - 34000 - 180000 - 26000);
    });

    test('múltbeli hónapra nincs előrejelzés', () {
      expect(
        forecastMonth(
          transactions: transactions,
          rules: [rent],
          month: YearMonth(2026, 10),
          today: today,
        ),
        isNull,
      );
    });

    test('a jövő hónapban minden esedékesség várható', () {
      final forecast = forecastMonth(
        transactions: transactions,
        rules: [rent, salary],
        month: YearMonth(2026, 12),
        today: today,
      )!;
      expect(forecast.upcomingIncome, 400000);
      expect(forecast.upcomingExpense, 180000);
    });
  });

  group('keresés', () {
    final all = [
      _t(
        1,
        EntryType.expense,
        'Lidl bevásárlás',
        12450,
        'groceries',
        CalendarDay(2026, 11, 3),
      ),
      _t(
        2,
        EntryType.expense,
        'Kávé',
        890,
        'dining',
        CalendarDay(2026, 11, 5),
        note: 'Starbucks a munkahely mellett',
      ),
      _t(
        3,
        EntryType.income,
        'Fizetés',
        420000,
        'salary',
        CalendarDay(2026, 10, 10),
      ),
      _t(
        4,
        EntryType.expense,
        'Lakbér',
        180000,
        'housing',
        CalendarDay(2026, 10, 1),
      ),
    ];

    List<int?> ids(String query) =>
        searchTransactions(all, query).map((t) => t.id).toList();

    test('ékezet- és kisbetű-független', () {
      expect(ids('kave'), [2]);
      expect(ids('LAKBÉR'), [4]);
      expect(ids('fizetes'), [3]);
    });

    test('megjegyzésben, kategóriában, típusban és hónapban is keres', () {
      expect(ids('starbucks'), [2]);
      expect(ids('élelmiszer'), [1]);
      expect(ids('bevétel'), [3]);
      expect(ids('október'), [3, 4]);
      expect(ids('kiadás november'), [2, 1]);
    });

    test('összegre és dátumra is', () {
      expect(ids('12450'), [1]);
      expect(ids('12 450'), [1]);
      expect(ids('2026.11.05'), [2]);
      expect(ids('2026-10-01'), [4]);
    });

    test('elírást tűr', () {
      expect(ids('bevasrlas'), [1]);
      expect(ids('fizettés'), [3]);
    });

    test('üres keresés üres eredmény', () {
      expect(ids('  '), isEmpty);
    });
  });

  group('szövegillesztés', () {
    test('ékezetek', () {
      expect(foldAccents('Árvíztűrő tükörfúrógép'), 'arvizturo tukorfurogep');
    });

    test('szerkesztési távolság (felcserélt betűk is)', () {
      expect(editDistance('lidl', 'lild'), 1);
      expect(editDistance('kave', 'kvae'), 1);
      expect(editDistance('tesco', 'teszko'), 2);
    });

    test('toldalékos és elírt szavak', () {
      expect(fuzzyWordMatch('lidlben', 'lidl'), isTrue);
      expect(fuzzyWordMatch('tescoban', 'tesco'), isTrue);
      expect(fuzzyWordMatch('netflixet', 'netflix'), isTrue);
      expect(fuzzyWordMatch('benzinkut', 'benzin'), isTrue);
      expect(fuzzyWordMatch('lidl', 'aldi'), isFalse);
      expect(fuzzyWordMatch('tej', 'tea'), isFalse);
    });
  });

  group('saját kategóriák', () {
    test('a katalógus a saját kategóriákat az Egyéb elé teszi', () {
      final catalog = CategoryCatalog([
        const Category(
          id: 'c1',
          type: EntryType.expense,
          name: 'Kutya',
          colorValue: 0xFF14B8A6,
          iconKey: 'pets',
          custom: true,
        ),
      ]);
      final expense = catalog.forType(EntryType.expense);
      expect(expense[expense.length - 2].name, 'Kutya');
      expect(expense.last.id, 'other_expense');
      expect(catalog.byId('c1')?.custom, isTrue);
      expect(
        catalog.forType(EntryType.income).any((c) => c.id == 'c1'),
        isFalse,
      );
    });
  });
}
