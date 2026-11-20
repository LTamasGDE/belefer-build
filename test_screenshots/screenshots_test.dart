// Képernyőképek a vizuális ellenőrzéshez, valódi betűkészletekkel.
//
// Nem része a normál `flutter test` futásnak. Előállítás:
//   flutter test test_screenshots --update-goldens
// A képek a test_screenshots/goldens/ mappába kerülnek.
import 'dart:convert';
import 'dart:io';

import 'package:belefer/app.dart';
import 'package:belefer/data/local_store.dart';
import 'package:belefer/domain/accounts.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/model/belefer_model.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/recurring.dart';
import 'package:belefer/services/platform_services.dart';
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

class _AndroidCapture implements CaptureBridge {
  @override
  bool get supportsNotifications => true;
  @override
  bool get supportsApplePay => false;
  @override
  Future<List<Map<Object?, Object?>>> drain() async => const [];
  @override
  Future<bool> isNotificationAccessGranted() async => true;
  @override
  Future<void> openNotificationAccessSettings() async {}
  @override
  Future<void> setRevolutCaptureEnabled(bool enabled) async {}
}

Future<AppState> _state({
  bool withData = true,
  bool dark = false,
  bool tour = false,
  CaptureBridge capture = const NoCaptureBridge(),
}) async {
  final store = await LocalStore.open(newDatabaseFactoryMemory(), 'shot.db');
  final state = AppState(
    store: store,
    capture: capture,
    versionLabel: '0.3.0 (3)',
    today: () => _today,
    now: () => DateTime(2026, 11, 17, 12),
  );
  await state.load();
  if (!tour) await state.markTourSeen();
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
    for (final rule in [
      RecurringRule(
        type: e,
        title: 'Lakbér',
        categoryId: 'housing',
        amount: 180000,
        startDate: CalendarDay(2026, 1, 1),
        reminder: const ReminderSettings(enabled: true),
      ),
      RecurringRule(
        type: e,
        title: 'Netflix',
        categoryId: 'subscriptions',
        amount: 4990,
        startDate: CalendarDay(2026, 1, 25),
      ),
      RecurringRule(
        type: i,
        title: 'Fizetés',
        categoryId: 'salary',
        amount: 420000,
        startDate: CalendarDay(2026, 1, 5),
      ),
      RecurringRule(
        type: e,
        title: 'Edzőterem',
        categoryId: 'health',
        amount: 15000,
        startDate: CalendarDay(2026, 11, 17),
        autoBook: false,
        reminder: const ReminderSettings(enabled: true, daysBefore: 0),
      ),
    ]) {
      await state.saveRule(rule);
    }
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

      await _tab(tester, 'Ismétlődő');
      await _shot(tester, '13_recurring_$mode');
      await tester.tap(find.text('Lakbér').first);
      await tester.pumpAndSettle();
      await _shot(tester, '14_recurring_form_$mode');
      await tester.tap(find.byTooltip('Bezárás'));
      await tester.pumpAndSettle();

      await _tab(tester, 'Áttekintés');
      await tester.ensureVisible(find.byKey(const ValueKey('quick-entry-bar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-entry-bar')));
      await tester.pumpAndSettle();
      await _shot(tester, '15_quick_entry_empty_$mode');
      await tester.enterText(
        find.byKey(const ValueKey('quick-entry-field')),
        'tegnap lidl 4 590',
      );
      await tester.pumpAndSettle();
      await _shot(tester, '16_quick_entry_$mode');
      await tester.enterText(
        find.byKey(const ValueKey('quick-entry-field')),
        'Spotify havi 1990',
      );
      await tester.pumpAndSettle();
      await _shot(tester, '17_quick_entry_recurring_$mode');
      for (final (name, text) in const [
        ('17a_quick_entry_transfer', 'Átraktam 10000 forintot CIB számláról a revolut sajátra'),
        ('17b_quick_entry_multi', 'kávé 900, ebéd 2800, mozi 3000'),
        ('17c_quick_entry_question', 'mennyit költöttem ebben a hónapban?'),
        ('17d_quick_entry_guess', 'xyz 5000'),
      ]) {
        await tester.enterText(
          find.byKey(const ValueKey('quick-entry-field')),
          text,
        );
        await tester.pumpAndSettle();
        await _shot(tester, '${name}_$mode');
      }
      await tester.tap(find.byTooltip('Bezárás'));
      await tester.pumpAndSettle();

      await _tab(tester, 'Tételek');
      await tester.tap(find.byTooltip('Keresés'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('search-field')),
        'bevasarlas',
      );
      await tester.pumpAndSettle();
      await _shot(tester, '18_search_$mode');
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

  testWidgets('bemutató (bemutató adatokkal)', (tester) async {
    _phone(tester);
    final state = (await tester.runAsync(
      () => _state(withData: false, tour: true),
    ))!;
    await _pump(tester, state);
    await _shot(tester, '19_tour_welcome');
    await tester.tap(find.byKey(const ValueKey('tour-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tour-next')));
    await tester.pumpAndSettle();
    await _shot(tester, '20_tour_quick_entry');
    await tester.tap(find.byKey(const ValueKey('tour-next')));
    await tester.pumpAndSettle();
    await _shot(tester, '21_tour_forecast');
    for (var step = 0; step < 3; step++) {
      await tester.tap(find.byKey(const ValueKey('tour-next')));
      await tester.pumpAndSettle();
    }
    await _shot(tester, '22_tour_recurring');
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

  testWidgets('számlák, saját modell, automatikus rögzítés', (tester) async {
    _phone(tester);
    currentModel = BeleferModel.parse(
      File('assets/model/belefer_model.bin').readAsBytesSync(),
    );
    addTearDown(() => currentModel = null);
    final state = (await tester.runAsync(() async {
      final state = await _state(capture: _AndroidCapture());
      await state.saveAccount(
        const Account(
          name: 'Saját',
          kind: AccountKind.personal,
          isDefault: true,
        ),
      );
      final joint = await state.saveAccount(
        const Account(
          name: 'Közös',
          kind: AccountKind.shared,
          matchers: ['Közös', 'Joint'],
        ),
      );
      await state.saveAccount(
        const Account(name: 'Megtakarítás', kind: AccountKind.savings),
      );
      await state.saveTransaction(
        Transaction(
          type: EntryType.expense,
          title: 'Lidl',
          amount: 12400,
          categoryId: 'groceries',
          date: CalendarDay(2026, 11, 17),
          note: 'Revolut-értesítés · Joint',
          accountId: joint.id,
          source: 'revolut',
        ),
      );
      await state.setRevolutCaptureEnabled(true);
      return state;
    }))!;
    await _pump(tester, state);
    await _shot(tester, '23_overview_accounts');
    await _tab(tester, 'Tételek');
    await _shot(tester, '24_transactions_accounts');
    await _tab(tester, 'Beállítások');
    await _shot(tester, '25_settings_model_capture');
    await tester.tap(find.byKey(const ValueKey('open-capture')));
    await tester.pumpAndSettle();
    await _shot(tester, '26_capture');
    await tester.tap(find.text('Számlák és felismerő szavak'));
    await tester.pumpAndSettle();
    await _shot(tester, '27_accounts');
    await tester.tap(find.text('Közös'));
    await tester.pumpAndSettle();
    await _shot(tester, '28_account_editor');
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Számlák').first)).pop();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Automatikus rögzítés').first)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-model')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('model-try')),
      'tegnap a hentesnél 6700',
    );
    await tester.pumpAndSettle();
    await _shot(tester, '29_model');
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
