import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/recurring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';
import '../support/ui_helpers.dart';

void main() {
  group('gyorsrögzítés', () {
    testWidgets('a kérdések halványan látszanak, majd egy mondatból könyvel', (
      tester,
    ) async {
      final state = await pumpBelefer(tester);
      await tapVisible(tester, find.byKey(const ValueKey('quick-entry-bar')));

      // Üresen a kötelező kérdések látszanak.
      expect(find.byKey(const ValueKey('hint-amount')), findsOneWidget);
      expect(find.byKey(const ValueKey('hint-what')), findsOneWidget);
      expect(find.textContaining('Mennyi?'), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey('quick-entry-field')),
        'tegnap lidl 4500',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-result')), findsOneWidget);
      expect(find.text('Elkönyvelés'), findsOneWidget);

      await tapVisible(
        tester,
        find.byKey(const ValueKey('quick-entry-submit')),
      );
      expect(state.transactions, hasLength(1));
      final saved = state.transactions.single;
      expect(saved.title, 'Lidl');
      expect(saved.amount, 4500);
      expect(saved.categoryId, 'groceries');
      expect(saved.date, CalendarDay(2026, 11, 16));
      expect(find.textContaining('Kiadás rögzítve: Lidl'), findsOneWidget);

      // Visszavonás.
      await tester.tap(find.text('Visszavonás'));
      await tester.pumpAndSettle();
      expect(state.transactions, isEmpty);
    });

    testWidgets('átvezetést felismer, és nem könyveli', (tester) async {
      final state = await pumpBelefer(tester);
      await tapVisible(tester, find.byKey(const ValueKey('quick-entry-bar')));
      await tester.enterText(
        find.byKey(const ValueKey('quick-entry-field')),
        'Átraktam 10000 forintot CIB számláról a revolut sajátra',
      );
      await tester.pumpAndSettle();
      expect(find.text('Átvezetés'), findsOneWidget);
      expect(find.textContaining('CIB →'), findsOneWidget);
      expect(find.text('Rendben, nem könyvelem'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('quick-entry-submit')),
      );
      expect(state.transactions, isEmpty);
      expect(find.textContaining('nem könyveltem'), findsOneWidget);
    });

    testWidgets('több tételt egyszerre könyvel, és együtt vonja vissza', (
      tester,
    ) async {
      final state = await pumpBelefer(tester);
      await tapVisible(tester, find.byKey(const ValueKey('quick-entry-bar')));
      await tester.enterText(
        find.byKey(const ValueKey('quick-entry-field')),
        'Lidl 4500 és benzin 20 000',
      );
      await tester.pumpAndSettle();
      expect(find.text('2 tétel elkönyvelése'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('quick-entry-submit')),
      );
      expect(state.transactions, hasLength(2));
      await tester.tap(find.text('Visszavonás'));
      await tester.pumpAndSettle();
      expect(state.transactions, isEmpty);
    });

    testWidgets('bizonytalan tippnél ellenőrzést kér', (tester) async {
      await pumpBelefer(tester);
      await tapVisible(tester, find.byKey(const ValueKey('quick-entry-bar')));
      await tester.enterText(
        find.byKey(const ValueKey('quick-entry-field')),
        'xyz 5000',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Ellenőrizd'), findsOneWidget);
      expect(find.textContaining('Minden megvan'), findsNothing);
    });

    testWidgets('hiányos mondatnál megmondja, mi kell még', (tester) async {
      await pumpBelefer(tester);
      await tapVisible(tester, find.byKey(const ValueKey('quick-entry-bar')));
      await tester.enterText(
        find.byKey(const ValueKey('quick-entry-field')),
        'lidl',
      );
      await tester.pumpAndSettle();
      expect(find.text('Még kell: Mennyi?'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('quick-entry-submit')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('ismétlődő tételt is létrehoz egy mondatból', (tester) async {
      final state = await pumpBelefer(tester);
      await tapVisible(tester, find.byKey(const ValueKey('quick-entry-bar')));
      await tester.enterText(
        find.byKey(const ValueKey('quick-entry-field')),
        'Netflix havi 4990',
      );
      await tester.pumpAndSettle();
      expect(find.text('Ismétlődő tétel létrehozása'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('quick-entry-submit')),
      );
      expect(state.rules.single.title, 'Netflix');
      expect(state.rules.single.frequency, Frequency.monthly);
      // A mai esedékesség rögtön rögzül.
      expect(state.transactions.single.recurringId, state.rules.single.id);
    });
  });

  group('ismétlődő tételek', () {
    testWidgets('felvétel űrlapon, a lista és a havi összesítő', (
      tester,
    ) async {
      final state = await pumpBelefer(tester);
      await goToTab(tester, 'Ismétlődő');
      expect(find.text('Még nincs ismétlődő tétel'), findsOneWidget);

      await tapVisible(tester, find.text('Új ismétlődő tétel'));
      await enterField(tester, 'field-amount', '180000');
      await enterField(tester, 'field-title', 'Lakbér');
      await tapVisible(tester, find.text('Lakhatás'));
      expect(find.byKey(const ValueKey('reminder-preview')), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('save-recurring')));

      expect(state.rules.single.title, 'Lakbér');
      expect(find.text('Lakbér'), findsWidgets);
      expect(find.byKey(const ValueKey('recurring-totals')), findsOneWidget);
    });

    testWidgets('jóváhagyásra váró tétel rögzítése', (tester) async {
      final state = await tester.runAsync(openTestState);
      await tester.runAsync(
        () => state!.saveRule(
          RecurringRule(
            type: EntryType.expense,
            title: 'Edzőterem',
            categoryId: 'health',
            amount: 15000,
            startDate: testToday,
            autoBook: false,
          ),
        ),
      );
      await pumpBelefer(tester, state: state);
      expect(find.text('Jóváhagyásra vár'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(ValueKey('book-pending-${state!.rules.single.id}')),
      );
      expect(state.transactions.single.title, 'Edzőterem');
      expect(find.text('Jóváhagyásra vár'), findsNothing);
    });
  });

  testWidgets('keresés minden hónap tételei között', (tester) async {
    final state = await tester.runAsync(openTestState);
    await tester.runAsync(() async {
      await state!.saveTransaction(
        expense('Kávé', 890, 'dining', CalendarDay(2026, 10, 3)),
      );
      await state.saveTransaction(
        expense('Lakbér', 180000, 'housing', CalendarDay(2026, 11, 1)),
      );
    });
    await pumpBelefer(tester, state: state);
    await goToTab(tester, 'Tételek');
    await tester.tap(find.byTooltip('Keresés'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'kave');
    await tester.pumpAndSettle();
    expect(find.text('1 találat'), findsOneWidget);
    expect(find.text('Kávé'), findsOneWidget);
  });

  testWidgets('saját kategória az űrlapról', (tester) async {
    final state = await pumpBelefer(tester);
    await tapVisible(tester, find.byKey(const ValueKey('quick-expense')));
    await tapVisible(tester, find.byKey(const ValueKey('new-category-chip')));
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'Kutya',
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const ValueKey('save-category')));
    expect(state.customCategories.single.name, 'Kutya');
    // Az új kategória ki is van választva.
    await enterField(tester, 'field-amount', '8000');
    await enterField(tester, 'field-title', 'Táp');
    await tapVisible(tester, find.byKey(const ValueKey('save-transaction')));
    expect(
      state.transactions.single.categoryId,
      state.customCategories.single.id,
    );
  });

  group('bemutató', () {
    testWidgets('első indításkor jön, kihagyható, és nem töröl', (
      tester,
    ) async {
      final state = await tester.runAsync(() => openTestState(showTour: true));
      await pumpBelefer(tester, state: state);
      expect(find.text('Üdv a Belefér-ben!'), findsOneWidget);
      expect(state!.isDemo, isTrue);

      await tester.tap(find.byKey(const ValueKey('tour-next')));
      await tester.pumpAndSettle();
      expect(find.text('A hónap egy pillantásra'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tour-skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tour-title')), findsNothing);
      expect(state.isDemo, isFalse);
      expect(state.transactions, isEmpty);
      expect(state.tourSeen, isTrue);
    });

    testWidgets('végigjátszható és a Beállításokból újraindítható', (
      tester,
    ) async {
      final state = await pumpBelefer(tester);
      await goToTab(tester, 'Beállítások');
      await tapVisible(tester, find.byKey(const ValueKey('replay-tour')));
      expect(find.text('Üdv a Belefér-ben!'), findsOneWidget);
      var guard = 0;
      while (find.text('Kezdjük!').evaluate().isEmpty && guard++ < 15) {
        await tester.tap(find.byKey(const ValueKey('tour-next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('Beállítások'), findsWidgets);
      await tester.tap(find.text('Kezdjük!'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tour-title')), findsNothing);
      expect(state.isDemo, isFalse);
    });
  });
}
