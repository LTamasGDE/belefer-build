// Képernyőképek a vizuális ellenőrzéshez, valódi betűkészletekkel.
//
// Nem része a normál `flutter test` futásnak. Előállítás:
//   flutter test test_screenshots --update-goldens
// A képek a test_screenshots/goldens/ mappába kerülnek.
import 'dart:convert';

import 'package:belefer/app.dart';
import 'package:belefer/data/local_store.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Transaction;

final CalendarDay _today = CalendarDay(2026, 11, 17);

Future<void> _loadFonts() async {
  final manifest = await rootBundle.loadString('FontManifest.json');
  final families = (json.decode(manifest) as List<dynamic>)
      .cast<Map<String, dynamic>>();
  for (final family in families) {
    final loader = FontLoader(family['family'] as String);
    for (final font
        in (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

Transaction _tx(
  EntryType type,
  String title,
  int amount,
  String category,
  int day, {
  String? note,
  int month = 11,
}) => Transaction(
  type: type,
  title: title,
  amount: amount,
  categoryId: category,
  date: CalendarDay(2026, month, day),
  note: note,
);

Future<AppState> _state({bool withData = true, bool dark = false}) async {
  final store = await LocalStore.open(newDatabaseFactoryMemory(), 'shot.db');
  final state = AppState(
    store: store,
    versionLabel: '0.1.0 (1)',
    today: () => _today,
  );
  await state.load();
  if (withData) {
    const e = EntryType.expense;
    const i = EntryType.income;
    for (final t in [
      _tx(i, 'Fizetés', 420000, 'salary', 5),
      _tx(i, 'Ösztöndíj', 35000, 'scholarship', 10),
      _tx(e, 'Lakbér', 180000, 'housing', 1, note: 'november'),
      _tx(e, 'Rezsi', 24800, 'utilities', 8),
      _tx(e, 'Heti bevásárlás', 31800, 'groceries', 9),
      _tx(
        e,
        'Hosszú megnevezésű közös hétvégi bevásárlás a piacon',
        20500,
        'groceries',
        15,
      ),
      _tx(e, 'Havi bérlet', 8950, 'transport', 3),
      _tx(e, 'Ebéd a csapattal', 14600, 'dining', 16),
      _tx(e, 'Zenei előfizetés', 1990, 'subscriptions', 12),
      _tx(e, 'Mozi', 3200, 'entertainment', 17),
    ]) {
      await state.saveTransaction(t);
    }
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
        type: EntryType.expense,
        title: 'Heti bevásárlás',
        categoryId: 'groceries',
      ),
    );
    await state.saveTemplate(
      const EntryTemplate(
        type: EntryType.income,
        title: 'Fizetés',
        categoryId: 'salary',
        amount: 420000,
      ),
    );
  }
  await state.setDarkMode(dark);
  return state;
}

Future<void> _pump(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: BeleferApp(state: state),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await expectLater(
    find.byKey(const ValueKey('shot')),
    matchesGoldenFile('goldens/$name.png'),
  );
}

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void _phone(WidgetTester tester, {double textScale = 1}) {
  tester.view.physicalSize = const Size(720, 1560);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  setUpAll(_loadFonts);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('képernyők ($mode)', (tester) async {
      _phone(tester);
      final state = (await tester.runAsync(() => _state(dark: dark)))!;
      await _pump(tester, state);
      await _shot(tester, '01_overview_$mode');

      final legend = find.byKey(const ValueKey('legend-groceries'));
      await tester.ensureVisible(legend);
      await tester.pumpAndSettle();
      await tester.tap(legend);
      await _shot(tester, '02_overview_selected_$mode');

      await _tab(tester, 'Tételek');
      await _shot(tester, '03_transactions_$mode');

      await _tab(tester, 'Sablonok');
      await _shot(tester, '04_templates_$mode');

      await tester.tap(find.text('Használat').first);
      await tester.pumpAndSettle();
      await _shot(tester, '05_form_from_template_$mode');
      await tester.tap(find.byTooltip('Bezárás'));
      await tester.pumpAndSettle();

      await _tab(tester, 'Beállítások');
      await _shot(tester, '06_settings_$mode');
    });
  }

  testWidgets('üres állapotok', (tester) async {
    _phone(tester);
    final state = (await tester.runAsync(() => _state(withData: false)))!;
    await _pump(tester, state);
    await _shot(tester, '07_overview_empty');
    await _tab(tester, 'Sablonok');
    await _shot(tester, '08_templates_empty');
  });

  testWidgets('nagy betűméret (1,6×)', (tester) async {
    _phone(tester, textScale: 1.6);
    final state = (await tester.runAsync(_state))!;
    await _pump(tester, state);
    await _shot(tester, '09_overview_large_text');
    await _tab(tester, 'Tételek');
    await _shot(tester, '10_transactions_large_text');
    await _tab(tester, 'Sablonok');
    await _shot(tester, '10b_templates_large_text');
    await _tab(tester, 'Tételek');
    await tester.tap(find.text('Új tétel'));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('save-transaction'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await _shot(tester, '11_form_errors_large_text');
  });

  testWidgets('széles kijelző (tablet, fekvő)', (tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final state = (await tester.runAsync(_state))!;
    await _pump(tester, state);
    await _shot(tester, '12_overview_wide');
  });
}
