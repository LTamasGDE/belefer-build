import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/monthly_summary.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  group('havi összesítés', () {
    test('bevétel, kiadás és a kettő különbsége', () {
      final items = [
        income('Fizetés', 350000, 'salary', CalendarDay(2026, 11, 5)),
        expense('Lakbér', 100000, 'housing', CalendarDay(2026, 11, 1)),
        expense('Bevásárlás', 24500, 'groceries', CalendarDay(2026, 11, 10)),
      ];
      final summary = summarizeMonth(items, const YearMonth(2026, 11));
      expect(summary.income, 350000);
      expect(summary.expense, 124500);
      expect(summary.balance, 225500);
    });

    test('negatív egyenleg, ha több ment el, mint amennyi bejött', () {
      final items = [
        income('Ösztöndíj', 40000, 'scholarship', CalendarDay(2026, 3, 2)),
        expense('Albérlet', 90000, 'housing', CalendarDay(2026, 3, 3)),
      ];
      final summary = summarizeMonth(items, const YearMonth(2026, 3));
      expect(summary.balance, -50000);
    });

    test('hónaphatár: az utolsó és az első nap a saját hónapjába kerül', () {
      final items = [
        expense('Októberi utolsó', 1000, 'dining', CalendarDay(2026, 10, 31)),
        expense('Novemberi első', 2000, 'dining', CalendarDay(2026, 11, 1)),
        expense('Novemberi utolsó', 3000, 'dining', CalendarDay(2026, 11, 30)),
        expense('Decemberi első', 4000, 'dining', CalendarDay(2026, 12, 1)),
      ];
      expect(summarizeMonth(items, const YearMonth(2026, 10)).expense, 1000);
      expect(summarizeMonth(items, const YearMonth(2026, 11)).expense, 5000);
      expect(summarizeMonth(items, const YearMonth(2026, 12)).expense, 4000);
    });

    test('évhatár: december 31. és január 1. külön hónap', () {
      final items = [
        income('Szilveszter', 5000, 'gift_income', CalendarDay(2026, 12, 31)),
        income('Újév', 7000, 'gift_income', CalendarDay(2027, 1, 1)),
      ];
      const december = YearMonth(2026, 12);
      expect(summarizeMonth(items, december).income, 5000);
      expect(summarizeMonth(items, december.next).income, 7000);
      expect(summarizeMonth(items, december.next.previous).income, 5000);
    });

    test('ugyanaz a hónap másik évben nem számít bele', () {
      final items = [
        expense('Tavalyi', 1000, 'other_expense', CalendarDay(2025, 11, 17)),
      ];
      final summary = summarizeMonth(items, const YearMonth(2026, 11));
      expect(summary.expense, 0);
      expect(summary.expenseSlices, isEmpty);
    });

    test('üres hónap', () {
      final summary = summarizeMonth(const [], const YearMonth(2026, 11));
      expect(summary.income, 0);
      expect(summary.expense, 0);
      expect(summary.balance, 0);
      expect(summary.hasExpense, isFalse);
      expect(summary.expenseTotalPercentTenths, 0);
      expect(summary.expenseSlices, isEmpty);
    });
  });

  group('diagram adatai', () {
    test('kategóriánként összesít, csökkenő sorrendben', () {
      final items = [
        expense('Bevásárlás 1', 10000, 'groceries', CalendarDay(2026, 11, 3)),
        expense('Lakbér', 100000, 'housing', CalendarDay(2026, 11, 1)),
        expense('Bevásárlás 2', 14500, 'groceries', CalendarDay(2026, 11, 12)),
        income('Fizetés', 350000, 'salary', CalendarDay(2026, 11, 5)),
      ];
      final slices = summarizeMonth(
        items,
        const YearMonth(2026, 11),
      ).expenseSlices;
      expect(slices.map((s) => s.categoryId), ['housing', 'groceries']);
      expect(slices.map((s) => s.amount), [100000, 24500]);
      // 100000 / 124500 = 80,32%, 24500 / 124500 = 19,68%
      expect(slices.map((s) => s.percentTenths), [803, 197]);
    });

    test('a százalékok összege mindig pontosan 100,0%', () {
      final amounts = [1, 1, 1];
      expect(distributeTenths(amounts), [334, 333, 333]);
      expect(distributeTenths(amounts).reduce((a, b) => a + b), 1000);

      final uneven = [12345, 678, 9, 1000000, 333];
      expect(distributeTenths(uneven).reduce((a, b) => a + b), 1000);
    });

    test('egyetlen kategória 100%', () {
      final summary = summarizeMonth([
        expense('Lakbér', 180000, 'housing', CalendarDay(2026, 11, 1)),
      ], const YearMonth(2026, 11));
      expect(summary.expenseSlices.single.percentTenths, 1000);
      expect(summary.expenseTotalPercentTenths, 1000);
    });
  });

  group('tétellista', () {
    test('dátum szerint csökkenő, azonos napon az újabb elöl', () {
      final items = [
        expense('a', 1, 'dining', CalendarDay(2026, 11, 3)).copyWith(id: 1),
        expense('b', 1, 'dining', CalendarDay(2026, 11, 9)).copyWith(id: 2),
        expense('c', 1, 'dining', CalendarDay(2026, 11, 3)).copyWith(id: 3),
        income('d', 1, 'salary', CalendarDay(2026, 10, 30)).copyWith(id: 4),
      ];
      final list = transactionsInMonth(items, const YearMonth(2026, 11));
      expect(list.map((t) => t.title), ['b', 'c', 'a']);

      final incomes = transactionsInMonth(
        items,
        const YearMonth(2026, 10),
        type: EntryType.income,
      );
      expect(incomes.map((t) => t.title), ['d']);
    });

    test('a kiadás előjeles összege negatív, a bevételé pozitív', () {
      expect(
        expense('x', 500, 'dining', CalendarDay(2026, 1, 1)).signedAmount,
        -500,
      );
      expect(
        income('y', 500, 'salary', CalendarDay(2026, 1, 1)).signedAmount,
        500,
      );
    });
  });
}
