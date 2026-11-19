import 'package:belefer/app.dart';
import 'package:belefer/data/local_store.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/formatting.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/services/exchange_rates.dart';
import 'package:belefer/services/platform_services.dart';
import 'package:belefer/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast_memory.dart' hide Transaction;

/// A tesztek rögzített „mai” napja: 2026. november 17., kedd.
final CalendarDay testToday = CalendarDay(2026, 11, 17);

/// Forintösszeg a felületen használt formában (nem törhető szóközzel).
String ft(int amount) => formatForint(amount);

/// Új, memóriában tárolt állapot rögzített mai nappal.
///
/// A körbevezetést alapból látottnak jelöli; a [showTour] igaz értékével az
/// első indítás viselkedése próbálható ki.
Future<AppState> openTestState({
  DatabaseFactory? factory,
  String path = 'belefer_test.db',
  bool showTour = false,
  ReminderScheduler reminders = const NoopReminderScheduler(),
  WidgetPublisher widget = const NoopWidgetPublisher(),
  CaptureBridge capture = const NoCaptureBridge(),
  ExchangeRates rates = const NoExchangeRates(),
  http.Client? httpClient,
}) async {
  final store = await LocalStore.open(
    factory ?? newDatabaseFactoryMemory(),
    path,
  );
  final state = AppState(
    store: store,
    versionLabel: '0.3.0 (3)',
    today: () => testToday,
    now: () => DateTime(2026, 11, 17, 12),
    reminders: reminders,
    widget: widget,
    capture: capture,
    rates: rates,
    httpClient: httpClient,
  );
  await state.load();
  if (!showTour) await state.markTourSeen();
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

/// Rögzített árfolyamok tesztekhez.
class FixedRates implements ExchangeRates {
  const FixedRates(this.rates);

  final Map<String, double> rates;

  @override
  Future<double?> hufPer(String currency) async => rates[currency];
}

/// Előre betöltött eseménysor az automatikus rögzítés teszteléséhez.
class FakeCaptureBridge implements CaptureBridge {
  FakeCaptureBridge({this.supportsNotifications = true});

  final List<Map<Object?, Object?>> queue = [];
  bool granted = false;
  bool? enabled;
  int settingsOpened = 0;

  @override
  final bool supportsNotifications;

  @override
  bool get supportsApplePay => !supportsNotifications;

  @override
  Future<List<Map<Object?, Object?>>> drain() async {
    final items = [...queue];
    queue.clear();
    return items;
  }

  @override
  Future<bool> isNotificationAccessGranted() async => granted;

  @override
  Future<void> openNotificationAccessSettings() async => settingsOpened++;

  @override
  Future<void> setRevolutCaptureEnabled(bool value) async => enabled = value;
}
