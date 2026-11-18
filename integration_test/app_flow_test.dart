// Alapfolyamat valódi eszközön vagy emulátoron/szimulátoron, valódi
// fájlalapú Sembast-adatbázissal az alkalmazás saját tárhelyén.
//
// Futtatás: flutter test integration_test/app_flow_test.dart -d <eszköz>
import 'package:belefer/app.dart';
import 'package:belefer/bootstrap.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/formatting.dart';
import 'package:belefer/ui/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const String _databaseName = 'belefer_integration_test.db';

Future<void> _goToTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToCenter(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await _scrollToCenter(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enterField(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await _scrollToCenter(tester, finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(HomeShell))).brightness;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sablonból rögzítés, diagram, téma, újranyitás és adattörlés', (
    tester,
  ) async {
    var state = await openAppState(databaseName: _databaseName);
    await state.clearAllData();
    await tester.pumpWidget(BeleferApp(state: state));
    await tester.pumpAndSettle();

    // Első indításkor a bemutató jön; kihagyható.
    final skip = find.byKey(const ValueKey('tour-skip'));
    if (skip.evaluate().isNotEmpty) {
      expect(find.text('Üdv a Belefér-ben!'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tour-next')));
      await tester.pumpAndSettle();
      await tester.tap(skip);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('tour-skip')), findsNothing);
    expect(state.transactions, isEmpty);
    expect(find.text('0% | ${formatForint(0)}'), findsOneWidget);

    // Sablon létrehozása.
    await _goToTab(tester, 'Sablonok');
    await _tapVisible(tester, find.text('Kiadási sablon'));
    await _enterField(tester, 'field-amount', '180000');
    await _enterField(tester, 'field-title', 'Lakbér');
    await _tapVisible(tester, find.text('Lakhatás'));
    await _tapVisible(tester, find.byKey(const ValueKey('save-template')));
    expect(find.text('Lakbér'), findsOneWidget);

    // Tétel rögzítése a sablonból, a mai dátummal.
    await _tapVisible(tester, find.text('Használat'));
    expect(find.text(formatFullDate(CalendarDay.today())), findsOneWidget);
    await _tapVisible(tester, find.byKey(const ValueKey('save-transaction')));
    expect(find.text('Kiadás mentve'), findsOneWidget);

    // Diagram és kiemelés.
    await _goToTab(tester, 'Áttekintés');
    expect(find.text('100% | ${formatForint(180000)}'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const ValueKey('legend-housing')));
    expect(find.byKey(const ValueKey('center-housing')), findsOneWidget);

    // Témaváltás.
    await _goToTab(tester, 'Beállítások');
    await _tapVisible(tester, find.byKey(const ValueKey('dark-mode-switch')));
    expect(_brightness(tester), Brightness.dark);

    // Újranyitás: az adatbázis lezárása és újra betöltése.
    await state.close();
    await tester.pumpWidget(const SizedBox.shrink());
    state = await openAppState(databaseName: _databaseName);
    expect(state.transactions, hasLength(1));
    expect(state.templates, hasLength(1));
    expect(state.darkMode, isTrue);
    await tester.pumpWidget(BeleferApp(state: state));
    await tester.pumpAndSettle();
    expect(_brightness(tester), Brightness.dark);
    expect(find.text('100% | ${formatForint(180000)}'), findsOneWidget);

    // Gyorsrögzítés egy mondatból.
    await _tapVisible(tester, find.byKey(const ValueKey('quick-entry-bar')));
    await tester.enterText(
      find.byKey(const ValueKey('quick-entry-field')),
      'Lidl 4500',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-result')), findsOneWidget);
    await _tapVisible(tester, find.byKey(const ValueKey('quick-entry-submit')));
    expect(find.textContaining('Kiadás rögzítve: Lidl'), findsOneWidget);
    expect(state.transactions, hasLength(2));

    // Keresés minden tétel között.
    await _goToTab(tester, 'Tételek');
    await tester.tap(find.byTooltip('Keresés'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'lidl');
    await tester.pumpAndSettle();
    expect(find.text('1 találat'), findsOneWidget);
    await tester.tap(find.byTooltip('Keresés bezárása'));
    await tester.pumpAndSettle();

    // Összes adat törlése.
    await _goToTab(tester, 'Beállítások');
    await _tapVisible(tester, find.byKey(const ValueKey('clear-all-data')));
    await _tapVisible(tester, find.text('Végleges törlés'));
    expect(state.transactions, isEmpty);
    expect(state.templates, isEmpty);
    expect(_brightness(tester), Brightness.light);
    await _goToTab(tester, 'Áttekintés');
    expect(find.text('0% | ${formatForint(0)}'), findsOneWidget);

    await state.close();
  });
}
