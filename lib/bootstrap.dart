import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

import 'data/local_store.dart';
import 'domain/model/belefer_model.dart';
import 'services/exchange_rates.dart';
import 'services/platform_services.dart';
import 'state/app_state.dart';

/// Az alapértelmezett adatbázisfájl neve az alkalmazás saját tárhelyén.
const String defaultDatabaseName = 'belefer.db';

/// Megnyitja a helyi adatbázist és betölti az állapotot.
///
/// Az adatok az alkalmazás saját, más alkalmazások számára nem elérhető
/// tárhelyén vannak (Androidon az app adatkönyvtára, iOS-en az
/// Application Support mappa).
Future<AppState> openAppState({
  String databaseName = defaultDatabaseName,
  ReminderScheduler reminders = const NoopReminderScheduler(),
  WidgetPublisher widget = const NoopWidgetPublisher(),
  CaptureBridge capture = const NoCaptureBridge(),
  ExchangeRates rates = const NoExchangeRates(),
}) async {
  await loadBeleferModel();
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final store = await LocalStore.open(
    databaseFactoryIo,
    '${directory.path}/$databaseName',
  );
  final state = AppState(
    store: store,
    versionLabel: await _versionLabel(),
    reminders: reminders,
    widget: widget,
    capture: capture,
    rates: rates,
  );
  await state.load();
  return state;
}

/// A saját nyelvi modell betöltése az alkalmazás csomagjából.
///
/// Ha valamiért nem sikerül, a szabályalapú értelmező dolgozik tovább.
Future<void> loadBeleferModel() async {
  try {
    final data = await rootBundle.load('assets/model/belefer_model.bin');
    currentModel = BeleferModel.parse(data.buffer.asUint8List());
  } on Object catch (error) {
    debugPrint('A Belefér-modell nem tölthető be: $error');
    currentModel = null;
  }
}

Future<String> _versionLabel() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${info.buildNumber})';
  } on Exception {
    return 'ismeretlen';
  }
}

/// A beépített betűkészletek licencének regisztrálása a licencoldalhoz.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Inter', 'Poppins'], text);
  });
}
