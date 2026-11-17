import 'dart:io';

import 'package:belefer/data/local_store.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart' hide Transaction;

import '../support/test_app.dart';

void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('belefer_test_');
    dbPath = '${tempDir.path}/belefer.db';
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('a helyi adatok újranyitás után is megvannak', () async {
    final first = await LocalStore.open(databaseFactoryIo, dbPath);
    final saved = await first.saveTransaction(
      expense(
        'Lakbér',
        180000,
        'housing',
        CalendarDay(2026, 11, 1),
        note: 'november',
      ),
    );
    final template = await first.saveTemplate(
      const EntryTemplate(
        type: EntryType.income,
        title: 'Fizetés',
        categoryId: 'salary',
        amount: 350000,
      ),
    );
    await first.writeDarkMode(true);
    await first.close();

    final reopened = await LocalStore.open(databaseFactoryIo, dbPath);
    final transactions = await reopened.loadTransactions();
    expect(transactions, hasLength(1));
    final transaction = transactions.single;
    expect(transaction.id, saved.id);
    expect(transaction.title, 'Lakbér');
    expect(transaction.amount, 180000);
    expect(transaction.type, EntryType.expense);
    expect(transaction.categoryId, 'housing');
    expect(transaction.date, CalendarDay(2026, 11, 1));
    expect(transaction.note, 'november');

    final templates = await reopened.loadTemplates();
    expect(templates.single.id, template.id);
    expect(templates.single.title, 'Fizetés');
    expect(templates.single.amount, 350000);
    expect(await reopened.readDarkMode(), isTrue);
    await reopened.close();
  });

  test('a dátum naptári napként tárolódik', () async {
    final store = await LocalStore.open(databaseFactoryIo, dbPath);
    await store.saveTransaction(
      expense('Éjféli vásárlás', 990, 'groceries', CalendarDay(2026, 1, 31)),
    );
    await store.close();

    final raw = await File(dbPath).readAsString();
    expect(raw, contains('"date":"2026-01-31"'));
    expect(raw, isNot(contains('T23')));
  });

  test('szerkesztés és törlés', () async {
    final store = await LocalStore.open(databaseFactoryIo, dbPath);
    final saved = await store.saveTransaction(
      expense('Kávé', 900, 'dining', CalendarDay(2026, 11, 17)),
    );
    await store.saveTransaction(
      Transaction(
        id: saved.id,
        type: EntryType.expense,
        title: 'Kávé és kifli',
        amount: 1400,
        categoryId: 'dining',
        date: saved.date,
      ),
    );
    var all = await store.loadTransactions();
    expect(all.single.title, 'Kávé és kifli');
    expect(all.single.amount, 1400);

    await store.deleteTransaction(saved.id!);
    all = await store.loadTransactions();
    expect(all, isEmpty);
    await store.close();
  });

  test('az összes adat törlése a beállításokat is visszaállítja', () async {
    final store = await LocalStore.open(databaseFactoryIo, dbPath);
    await store.saveTransaction(
      expense('Mozi', 3200, 'entertainment', CalendarDay(2026, 11, 2)),
    );
    await store.saveTemplate(
      const EntryTemplate(
        type: EntryType.expense,
        title: 'Lakbér',
        categoryId: 'housing',
      ),
    );
    await store.writeDarkMode(true);
    await store.clearAll();
    await store.close();

    final reopened = await LocalStore.open(databaseFactoryIo, dbPath);
    expect(await reopened.loadTransactions(), isEmpty);
    expect(await reopened.loadTemplates(), isEmpty);
    expect(await reopened.readDarkMode(), isFalse);
    await reopened.close();
  });
}
