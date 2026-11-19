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

/// Az automatikus rögzítés platformoldala: Androidon a Revolut-értesítések,
/// iOS-en az Apple Pay-fizetések (Parancsok-automatizmus) sora.
abstract class CaptureBridge {
  /// Androidon: értesítés-olvasás lehetséges.
  bool get supportsNotifications;

  /// iOS-en: Apple Pay-automatizmus lehetséges.
  bool get supportsApplePay;

  /// A sorban váró események (és a sor ürítése).
  Future<List<Map<Object?, Object?>>> drain();

  /// Megadta-e a felhasználó az értesítés-hozzáférést (Android).
  Future<bool> isNotificationAccessGranted();

  /// A rendszer értesítés-hozzáférési beállításainak megnyitása (Android).
  Future<void> openNotificationAccessSettings();

  /// A Revolut-értesítések gyűjtésének be- és kikapcsolása (Android).
  Future<void> setRevolutCaptureEnabled(bool enabled);
}

class NoCaptureBridge implements CaptureBridge {
  const NoCaptureBridge();

  @override
  bool get supportsNotifications => false;

  @override
  bool get supportsApplePay => false;

  @override
  Future<List<Map<Object?, Object?>>> drain() async => const [];

  @override
  Future<bool> isNotificationAccessGranted() async => false;

  @override
  Future<void> openNotificationAccessSettings() async {}

  @override
  Future<void> setRevolutCaptureEnabled(bool enabled) async {}
}

/// A platformszolgáltatások (a `main` állítja be; tesztben cserélhető).
abstract final class Services {
  static ReceiptScanner receiptScanner = const UnavailableReceiptScanner();
  static AppLinks appLinks = const NoAppLinks();
}
