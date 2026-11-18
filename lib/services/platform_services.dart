import '../domain/recurring.dart';

/// Az esedékes tételek emlékeztetőinek ütemezése a telefon értesítéseivel.
abstract class ReminderScheduler {
  /// A korábban ütemezett emlékeztetők helyére a [reminders] kerül.
  Future<void> schedule(List<PlannedReminder> reminders);

  /// Értesítési engedély kérése (ha kell). Igaz, ha megjelenhetnek.
  Future<bool> ensurePermission();

  /// Azonnali próba-értesítés.
  Future<void> showNow({required String title, required String body});
}

/// A kezdőképernyő-widget adatai.
class HomeWidgetData {
  const HomeWidgetData({
    required this.monthLabel,
    required this.income,
    required this.expense,
    required this.balance,
    required this.balanceNegative,
    required this.nextDue,
  });

  final String monthLabel;
  final String income;
  final String expense;
  final String balance;
  final bool balanceNegative;

  /// A következő esedékes tétel rövid leírása, vagy üres.
  final String nextDue;

  Map<String, String> toMap() => {
    'month': monthLabel,
    'income': income,
    'expense': expense,
    'balance': balance,
    'negative': balanceNegative ? '1' : '0',
    'next': nextDue,
  };
}

/// A kezdőképernyő-widget frissítése.
abstract class WidgetPublisher {
  Future<void> publish(HomeWidgetData data);
}

/// Tesztekhez és a platformszolgáltatások nélküli futáshoz.
class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {}

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> showNow({required String title, required String body}) async {}
}

class NoopWidgetPublisher implements WidgetPublisher {
  const NoopWidgetPublisher();

  @override
  Future<void> publish(HomeWidgetData data) async {}
}
