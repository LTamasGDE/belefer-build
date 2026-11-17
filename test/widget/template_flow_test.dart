import 'package:belefer/domain/formatting.dart';
import 'package:belefer/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';
import '../support/ui_helpers.dart';

void main() {
  testWidgets(
    'sablon létrehozása, majd tétel rögzítése belőle módosított összeggel',
    (tester) async {
      final state = await pumpBelefer(tester);

      await goToTab(tester, 'Sablonok');
      expect(find.text('Rögzíts gyorsabban sablonokkal'), findsOneWidget);
      await tapVisible(tester, find.text('Kiadási sablon'));

      // Új sablon: Lakbér, Lakhatás, 180 000 Ft.
      expect(find.text('Új sablon'), findsOneWidget);
      await enterField(tester, 'field-amount', '180000');
      expect(fieldText(tester, 'field-amount'), '180 000');
      await enterField(tester, 'field-title', 'Lakbér');
      await tapVisible(tester, find.text('Lakhatás'));
      await tapVisible(tester, find.byKey(const ValueKey('save-template')));

      expect(state.templates, hasLength(1));
      expect(find.text('Lakbér'), findsOneWidget);
      expect(find.text('Lakhatás · ${ft(180000)}'), findsOneWidget);

      // Használat: kitöltött űrlap a mai dátummal.
      await tapVisible(tester, find.text('Használat'));
      expect(find.text('Új kiadás'), findsOneWidget);
      expect(fieldText(tester, 'field-title'), 'Lakbér');
      expect(fieldText(tester, 'field-amount'), '180 000');
      expect(find.text(formatFullDate(testToday)), findsOneWidget);

      // Mentés előtt minden mező szerkeszthető.
      await enterField(tester, 'field-amount', '185000');
      await enterField(tester, 'field-note', 'decemberi emelés előtt');
      await tapVisible(tester, find.byKey(const ValueKey('save-transaction')));

      expect(find.text('Kiadás mentve'), findsOneWidget);
      final saved = state.transactions.single;
      expect(saved.title, 'Lakbér');
      expect(saved.amount, 185000);
      expect(saved.type, EntryType.expense);
      expect(saved.categoryId, 'housing');
      expect(saved.date, testToday);
      expect(saved.note, 'decemberi emelés előtt');
      // A sablon változatlan.
      expect(state.templates.single.amount, 180000);

      await goToTab(tester, 'Áttekintés');
      expect(find.text('100% | ${ft(185000)}'), findsOneWidget);

      await goToTab(tester, 'Tételek');
      expect(find.text('Lakbér'), findsOneWidget);
      expect(
        find.text(formatForint(-185000, signed: true)),
        findsOneWidget,
      );
    },
  );

  testWidgets('az új tétel űrlapján a megfelelő típusú sablonok jelennek meg', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final state = (await tester.runAsync(openTestState))!;
    await tester.runAsync(() async {
      await state.saveTemplate(
        const EntryTemplate(
          type: EntryType.expense,
          title: 'Lakbér',
          categoryId: 'housing',
          amount: 180000,
        ),
      );
      await state.saveTemplate(
        const EntryTemplate(
          type: EntryType.income,
          title: 'Fizetés',
          categoryId: 'salary',
        ),
      );
    });
    await pumpBelefer(tester, state: state);

    await tapVisible(tester, find.byKey(const ValueKey('quick-income')));
    expect(find.text('Új bevétel'), findsOneWidget);
    expect(find.bySemanticsLabel('Sablon: Fizetés'), findsOneWidget);
    expect(find.bySemanticsLabel('Sablon: Lakbér'), findsNothing);

    await tapVisible(tester, find.bySemanticsLabel('Sablon: Fizetés'));
    expect(fieldText(tester, 'field-title'), 'Fizetés');
    // Összeg nélküli sablon: az összeg üres marad, mentés előtt meg kell adni.
    expect(fieldText(tester, 'field-amount'), '');
    await tapVisible(tester, find.byKey(const ValueKey('save-transaction')));
    expect(find.text('Add meg az összeget.'), findsOneWidget);
    expect(state.transactions, isEmpty);

    await enterField(tester, 'field-amount', '350000');
    await tapVisible(tester, find.byKey(const ValueKey('save-transaction')));
    expect(state.transactions.single.amount, 350000);
    expect(state.transactions.single.type, EntryType.income);
    semantics.dispose();
  });
}
