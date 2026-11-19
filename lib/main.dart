import 'package:flutter/widgets.dart';

import 'app.dart';
import 'bootstrap.dart';
import 'platform/capture_bridge.dart';
import 'platform/home_widget_service.dart';
import 'platform/notifications.dart';
import 'platform/receipt_ocr.dart';
import 'services/exchange_rates.dart';
import 'services/platform_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final widget = HomeWidgetService();
  Services.receiptScanner = MlKitReceiptScanner();
  Services.appLinks = widget;
  final state = await openAppState(
    reminders: LocalReminderScheduler(),
    widget: widget,
    capture: MethodChannelCaptureBridge(),
    rates: FrankfurterRates(),
  );
  runApp(BeleferApp(state: state));
}
