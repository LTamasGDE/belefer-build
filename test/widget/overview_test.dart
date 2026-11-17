import 'package:belefer/domain/calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('üres hónap: 0% | 0 Ft és érthető üres állapot', (tester) async {
    await pumpBelefer(tester);

    expect(find.text('2026. november'), findsOneWidget);
    expect(find.text('0% | ${ft(0)}'), findsOneWidget);
    expect(find.text('Nincs kiadás'), findsOneWidget);
    expect(find.text('Új kiadás'), findsOneWidget);
    expect(find.text('Új bevétel'), findsOneWidget);
  });

  testWidgets('havi összegek, diagram és kiemelés', (tester) async {
    final state = (await tester.runAsync(openTestState))!;
    await tester.runAsync(() async {
      await state.saveTransaction(
        expense('Lakbér', 100000, 'housing', CalendarDay(2026, 11, 1)),
      );
      await state.saveTransaction(
        expense('Bevásárlás', 24500, 'groceries', CalendarDay(2026, 11, 10)),
      );
      await state.saveTransaction(
        income('Fizetés', 350000, 'salary', CalendarDay(2026, 11, 5)),
      );
      // Másik hónap: nem számít bele.
      await state.saveTransaction(
        expense('Mozi', 3000, 'entertainment', CalendarDay(2026, 10, 31)),
      );
    });
    await pumpBelefer(tester, state: state);

    expect(find.text('100% | ${ft(124500)}'), findsOneWidget);
    expect(find.text(ft(225500)), findsOneWidget);
    expect(find.text(ft(350000)), findsOneWidget);
    expect(find.byKey(const ValueKey('center-total')), findsOneWidget);

    // Jelmagyarázat: koppintásra kiemelés név, százalék és összeg szerint.
    await tester.tap(find.byKey(const ValueKey('legend-housing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('center-housing')), findsOneWidget);
    expect(find.text('80,3%'), findsNWidgets(2));
    expect(find.text(ft(100000)), findsNWidgets(2));

    // Újabb koppintás megszünteti a kiemelést.
    await tester.tap(find.byKey(const ValueKey('legend-housing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('center-total')), findsOneWidget);

    // Koppintás közvetlenül a diagram szeletére (a gyűrű bal felső részén
    // a 19,7%-os Élelmiszer szelet van).
    final donut = find.byKey(const ValueKey('expense-donut'));
    final size = tester.getSize(donut);
    final ringRadius = size.shortestSide / 2 - 7;
    final center = tester.getCenter(donut);
    await tester.tapAt(center + Offset(-ringRadius * 0.6, -ringRadius * 0.8));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('center-groceries')), findsOneWidget);
    expect(find.text('19,7%'), findsNWidgets(2));
  });

  testWidgets('a jelmagyarázat képernyőolvasóval is elérhető', (tester) async {
    final semantics = tester.ensureSemantics();
    final state = (await tester.runAsync(openTestState))!;
    await tester.runAsync(
      () => state.saveTransaction(
        expense('Lakbér', 180000, 'housing', CalendarDay(2026, 11, 1)),
      ),
    );
    await pumpBelefer(tester, state: state);

    expect(
      tester.getSemantics(find.byKey(const ValueKey('legend-housing'))),
      isSemantics(
        label: 'Lakhatás: 100%, ${ft(180000)}',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('hónapváltás előre és vissza', (tester) async {
    final state = (await tester.runAsync(openTestState))!;
    await tester.runAsync(
      () => state.saveTransaction(
        expense('Októberi', 5000, 'dining', CalendarDay(2026, 10, 12)),
      ),
    );
    await pumpBelefer(tester, state: state);
    expect(find.text('0% | ${ft(0)}'), findsOneWidget);

    await tester.tap(find.byTooltip('Előző hónap'));
    await tester.pumpAndSettle();
    expect(find.text('2026. október'), findsOneWidget);
    expect(find.text('100% | ${ft(5000)}'), findsOneWidget);

    await tester.tap(find.byTooltip('Ugrás az aktuális hónapra'));
    await tester.pumpAndSettle();
    expect(find.text('2026. november'), findsOneWidget);
  });
}
