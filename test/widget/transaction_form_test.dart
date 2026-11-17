import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';
import '../support/ui_helpers.dart';

void main() {
  testWidgets('hibás mezők jelzése, mentés nélkül', (tester) async {
    final state = await pumpBelefer(tester);
    await tapVisible(tester, find.byKey(const ValueKey('quick-expense')));
    expect(find.text('Új kiadás'), findsOneWidget);

    await tapVisible(tester, find.byKey(const ValueKey('save-transaction')));
    expect(find.text('Add meg az összeget.'), findsOneWidget);
    expect(find.text('Adj meg egy megnevezést.'), findsOneWidget);
    expect(find.text('Válassz kategóriát.'), findsOneWidget);
    expect(state.transactions, isEmpty);
    expect(find.text('Új kiadás'), findsOneWidget);
  });

  testWidgets('dupla koppintásra is csak egy tétel jön létre', (tester) async {
    final state = await pumpBelefer(tester);
    await tapVisible(tester, find.byKey(const ValueKey('quick-expense')));

    await enterField(tester, 'field-amount', '2490');
    await enterField(tester, 'field-title', 'Ebéd');
    await tapVisible(tester, find.text('Étterem, kávé'));

    final save = find.byKey(const ValueKey('save-transaction'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(state.transactions, hasLength(1));
    expect(state.transactions.single.amount, 2490);
    expect(state.transactions.single.date, testToday);
    expect(find.text('100% | ${ft(2490)}'), findsOneWidget);
  });

  testWidgets('típusváltáskor a kategória a típushoz igazodik', (tester) async {
    await pumpBelefer(tester);
    await tapVisible(tester, find.byKey(const ValueKey('quick-expense')));
    expect(find.text('Lakhatás'), findsOneWidget);
    expect(find.text('Ösztöndíj'), findsNothing);

    await tapVisible(tester, find.text('Bevétel'));
    expect(find.text('Új bevétel'), findsOneWidget);
    expect(find.text('Ösztöndíj'), findsOneWidget);
    expect(find.text('Lakhatás'), findsNothing);
  });

  testWidgets('tétel megtekintése, szerkesztése és törlése megerősítéssel', (
    tester,
  ) async {
    final state = (await tester.runAsync(openTestState))!;
    await tester.runAsync(
      () => state.saveTransaction(
        expense('Kávé', 900, 'dining', CalendarDay(2026, 11, 16)),
      ),
    );
    await pumpBelefer(tester, state: state);
    await goToTab(tester, 'Tételek');
    expect(find.textContaining('Tegnap'), findsOneWidget);

    await tapVisible(tester, find.text('Kávé'));
    expect(find.text('Tétel szerkesztése'), findsOneWidget);
    expect(fieldText(tester, 'field-amount'), '900');
    await enterField(tester, 'field-title', 'Kávé és kifli');
    await enterField(tester, 'field-amount', '1400');
    await tapVisible(tester, find.byKey(const ValueKey('save-transaction')));

    expect(state.transactions.single.title, 'Kávé és kifli');
    expect(state.transactions.single.amount, 1400);
    expect(find.text('Kávé és kifli'), findsOneWidget);

    // Törlés: előbb megerősítést kér, a Mégse nem töröl.
    await tapVisible(tester, find.text('Kávé és kifli'));
    await tapVisible(tester, find.byTooltip('Törlés'));
    expect(find.text('Törlöd a tételt?'), findsOneWidget);
    await tapVisible(tester, find.text('Mégse'));
    expect(state.transactions, hasLength(1));

    await tapVisible(tester, find.byTooltip('Törlés'));
    await tapVisible(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Törlés'),
      ),
    );
    expect(state.transactions, isEmpty);
    expect(find.text('Tétel törölve'), findsOneWidget);
    expect(find.text('Ebben a hónapban még nincs tétel'), findsOneWidget);

    await goToTab(tester, 'Áttekintés');
    expect(find.text('0% | ${ft(0)}'), findsOneWidget);
  });

  testWidgets('szűrés típus szerint', (tester) async {
    final state = (await tester.runAsync(openTestState))!;
    await tester.runAsync(() async {
      await state.saveTransaction(
        expense('Bérlet', 8950, 'transport', CalendarDay(2026, 11, 2)),
      );
      await state.saveTransaction(
        income('Novemberi bér', 350000, 'salary', CalendarDay(2026, 11, 5)),
      );
    });
    await pumpBelefer(tester, state: state);
    await goToTab(tester, 'Tételek');
    expect(find.text('Bérlet'), findsOneWidget);
    expect(find.text('Novemberi bér'), findsOneWidget);

    final filter = find.descendant(
      of: find.byType(ListView),
      matching: find.text('Bevétel'),
    );
    await tapVisible(tester, filter);
    expect(find.text('Bérlet'), findsNothing);
    expect(find.text('Novemberi bér'), findsOneWidget);
    expect(state.transactions.where((t) => t.type == EntryType.income), hasLength(1));
  });
}
