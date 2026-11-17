import 'package:belefer/app.dart';
import 'package:belefer/data/local_store.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/formatting.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

/// A tesztek rögzített „mai” napja: 2026. november 17., kedd.
final CalendarDay testToday = CalendarDay(2026, 11, 17);

/// Forintösszeg a felületen használt formában (nem törhető szóközzel).
String ft(int amount) => formatForint(amount);

/// Új, memóriában tárolt állapot rögzített mai nappal.
Future<AppState> openTestState({
  DatabaseFactory? factory,
  String path = 'belefer_test.db',
}) async {
  final store = await LocalStore.open(
    factory ?? newDatabaseFactoryMemory(),
    path,
  );
  final state = AppState(
    store: store,
    versionLabel: '0.1.0 (1)',
    today: () => testToday,
  );
  await state.load();
  return state;
}

/// Az alkalmazás elindítása widgettesztben.
Future<AppState> pumpBelefer(WidgetTester tester, {AppState? state}) async {
  final appState = state ?? (await tester.runAsync(openTestState))!;
  await tester.pumpWidget(BeleferApp(state: appState));
  await tester.pumpAndSettle();
  return appState;
}

Transaction expense(
  String title,
  int amount,
  String categoryId,
  CalendarDay date, {
  String? note,
}) => Transaction(
  type: EntryType.expense,
  title: title,
  amount: amount,
  categoryId: categoryId,
  date: date,
  note: note,
);

Transaction income(
  String title,
  int amount,
  String categoryId,
  CalendarDay date,
) => Transaction(
  type: EntryType.income,
  title: title,
  amount: amount,
  categoryId: categoryId,
  date: date,
);
