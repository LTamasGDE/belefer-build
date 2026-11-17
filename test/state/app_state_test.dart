import 'package:belefer/data/local_store.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Transaction;

import '../support/test_app.dart';

void main() {
  test('nyitáskor az aktuális hónap látszik, lapozható', () async {
    final state = await openTestState();
    expect(state.selectedMonth, const YearMonth(2026, 11));
    expect(state.isCurrentMonth, isTrue);

    state.showNextMonth();
    expect(state.selectedMonth, const YearMonth(2026, 12));
    state.showNextMonth();
    expect(state.selectedMonth, const YearMonth(2027, 1));
    expect(state.isCurrentMonth, isFalse);
    state.showCurrentMonth();
    expect(state.selectedMonth, const YearMonth(2026, 11));
    await state.close();
  });

  test('mentés, szerkesztés és törlés után friss az összesítés', () async {
    final state = await openTestState();
    var notifications = 0;
    state.addListener(() => notifications++);

    final rent = await state.saveTransaction(
      expense('Lakbér', 180000, 'housing', CalendarDay(2026, 11, 1)),
    );
    await state.saveTransaction(
      income('Fizetés', 350000, 'salary', CalendarDay(2026, 11, 5)),
    );
    expect(state.summary.expense, 180000);
    expect(state.summary.balance, 170000);
    expect(state.transactionsOfSelectedMonth(), hasLength(2));

    await state.saveTransaction(
      Transaction(
        id: rent.id,
        type: EntryType.expense,
        title: 'Lakbér',
        amount: 190000,
        categoryId: 'housing',
        date: rent.date,
      ),
    );
    expect(state.transactions, hasLength(2));
    expect(state.summary.expense, 190000);

    await state.deleteTransaction(rent.id!);
    expect(state.summary.expense, 0);
    expect(state.summary.balance, 350000);
    expect(notifications, 4);
    await state.close();
  });

  test('a sablonból mentett tétel független a sablontól', () async {
    final state = await openTestState();
    final template = await state.saveTemplate(
      const EntryTemplate(
        type: EntryType.expense,
        title: 'Lakbér',
        categoryId: 'housing',
        amount: 180000,
      ),
    );
    await state.saveTransaction(
      expense(template.title, template.amount!, template.categoryId, testToday),
    );

    await state.saveTemplate(
      EntryTemplate(
        id: template.id,
        type: EntryType.expense,
        title: 'Lakbér 2027',
        categoryId: 'housing',
        amount: 200000,
      ),
    );
    await state.deleteTemplate(template.id!);

    expect(state.templates, isEmpty);
    final saved = state.transactions.single;
    expect(saved.title, 'Lakbér');
    expect(saved.amount, 180000);
    await state.close();
  });

  test('sötét mód és összes adat törlése, újranyitással ellenőrizve', () async {
    final factory = databaseFactoryMemoryFs;
    final state = await openTestState(factory: factory, path: 'reopen.db');
    await state.saveTransaction(
      expense('Mozi', 3200, 'entertainment', testToday),
    );
    await state.saveTemplate(
      const EntryTemplate(
        type: EntryType.income,
        title: 'Fizetés',
        categoryId: 'salary',
      ),
    );
    await state.setDarkMode(true);
    state.showPreviousMonth();
    await state.close();

    final reopened = await openTestState(factory: factory, path: 'reopen.db');
    expect(reopened.darkMode, isTrue);
    expect(reopened.transactions, hasLength(1));
    expect(reopened.templates, hasLength(1));
    expect(reopened.selectedMonth, const YearMonth(2026, 11));

    reopened.showPreviousMonth();
    await reopened.clearAllData();
    expect(reopened.transactions, isEmpty);
    expect(reopened.templates, isEmpty);
    expect(reopened.darkMode, isFalse);
    expect(reopened.selectedMonth, const YearMonth(2026, 11));
    await reopened.close();

    final third = await openTestState(factory: factory, path: 'reopen.db');
    expect(third.transactions, isEmpty);
    expect(third.templates, isEmpty);
    expect(third.darkMode, isFalse);
    await third.close();
  });

  test('a verziócímke a build metaadataiból jön', () async {
    final store = await LocalStore.open(newDatabaseFactoryMemory(), 'v.db');
    final state = AppState(store: store, versionLabel: '0.1.0 (1)');
    expect(state.versionLabel, '0.1.0 (1)');
    await state.close();
  });
}
