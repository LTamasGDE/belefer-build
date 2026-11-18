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

/// Honnan érkezik a blokk vagy számla.
enum ReceiptSource {
  /// Fotó a kamerával.
  camera,

  /// Kép vagy képernyőkép a galériából.
  gallery,

  /// Fájl: PDF-számla vagy kép.
  file,
}

/// Egy beolvasott blokk vagy számla.
class ReceiptCapture {
  const ReceiptCapture({required this.text, this.imagePath, this.fileName});

  /// A felismert szöveg (soronként).
  final String text;

  /// A kép helye a készüléken (előnézethez), ha kép volt.
  final String? imagePath;

  /// A kiválasztott fájl neve, ha fájlból jött.
  final String? fileName;
}

/// Hiba a beolvasás közben, a felhasználónak szóló üzenettel.
class ReceiptScanException implements Exception {
  const ReceiptScanException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Kép vagy PDF kiválasztása és szövegfelismerés a készüléken.
abstract class ReceiptScanner {
  /// `null`, ha a felhasználó megszakította a kiválasztást.
  Future<ReceiptCapture?> capture(ReceiptSource source);
}

class UnavailableReceiptScanner implements ReceiptScanner {
  const UnavailableReceiptScanner();

  @override
  Future<ReceiptCapture?> capture(ReceiptSource source) async =>
      throw const ReceiptScanException(
        'A szövegfelismerés ezen az eszközön nem érhető el.',
      );
}

/// Az alkalmazást megnyitó hivatkozások (pl. a kezdőképernyő-widgetről:
/// `belefer://gyors`, `belefer://blokk`).
abstract class AppLinks {
  /// A hivatkozás, amellyel az alkalmazás elindult (vagy `null`).
  Future<Uri?> initialLink();

  /// A futás közben érkező hivatkozások.
  Stream<Uri> get links;
}

class NoAppLinks implements AppLinks {
  const NoAppLinks();

  @override
  Future<Uri?> initialLink() async => null;

  @override
  Stream<Uri> get links => const Stream.empty();
}

/// A platformszolgáltatások (a `main` állítja be; tesztben cserélhető).
abstract final class Services {
  static ReceiptScanner receiptScanner = const UnavailableReceiptScanner();
  static AppLinks appLinks = const NoAppLinks();
}
