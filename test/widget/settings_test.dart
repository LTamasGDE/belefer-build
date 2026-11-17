import 'package:belefer/domain/models.dart';
import 'package:belefer/ui/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Transaction;

import '../support/test_app.dart';
import '../support/ui_helpers.dart';

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(HomeShell))).brightness;

void main() {
  testWidgets('sötét mód, amely újranyitás után is megmarad', (tester) async {
    final factory = databaseFactoryMemoryFs;
    final state = (await tester.runAsync(
      () => openTestState(factory: factory, path: 'theme.db'),
    ))!;
    await pumpBelefer(tester, state: state);
    expect(_brightness(tester), Brightness.light);

    await goToTab(tester, 'Beállítások');
    expect(find.text('Verzió 0.1.0 (1)'), findsOneWidget);
    await tapVisible(tester, find.byKey(const ValueKey('dark-mode-switch')));
    expect(_brightness(tester), Brightness.dark);

    // Újranyitás: az állapot az adatbázisból töltődik be újra.
    await tester.runAsync(state.close);
    final reopened = (await tester.runAsync(
      () => openTestState(factory: factory, path: 'theme.db'),
    ))!;
    expect(reopened.darkMode, isTrue);
    await pumpBelefer(tester, state: reopened);
    expect(_brightness(tester), Brightness.dark);
  });

  testWidgets('összes adat törlése megerősítés után', (tester) async {
    final state = (await tester.runAsync(openTestState))!;
    await tester.runAsync(() async {
      await state.saveTransaction(
        expense('Lakbér', 180000, 'housing', testToday),
      );
      await state.saveTemplate(
        const EntryTemplate(
          type: EntryType.expense,
          title: 'Lakbér',
          categoryId: 'housing',
        ),
      );
      await state.setDarkMode(true);
    });
    await pumpBelefer(tester, state: state);
    expect(_brightness(tester), Brightness.dark);

    await goToTab(tester, 'Beállítások');
    await tapVisible(tester, find.byKey(const ValueKey('clear-all-data')));
    expect(find.text('Minden adat törlése?'), findsOneWidget);
    expect(find.textContaining('1 tétel és 1 sablon'), findsOneWidget);

    // A Mégse nem töröl semmit.
    await tapVisible(tester, find.text('Mégse'));
    expect(state.transactions, hasLength(1));

    await tapVisible(tester, find.byKey(const ValueKey('clear-all-data')));
    await tapVisible(tester, find.text('Végleges törlés'));

    expect(state.transactions, isEmpty);
    expect(state.templates, isEmpty);
    expect(state.darkMode, isFalse);
    expect(_brightness(tester), Brightness.light);
    expect(find.text('Minden adat törölve'), findsOneWidget);

    await goToTab(tester, 'Áttekintés');
    expect(find.text('0% | ${ft(0)}'), findsOneWidget);
    await goToTab(tester, 'Sablonok');
    expect(find.text('Rögzíts gyorsabban sablonokkal'), findsOneWidget);
  });
}
