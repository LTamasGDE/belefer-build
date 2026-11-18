import 'package:flutter/widgets.dart';

import 'app.dart';
import 'bootstrap.dart';
import 'platform/home_widget_service.dart';
import 'platform/notifications.dart';
import 'platform/receipt_ocr.dart';
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
  );
  runApp(BeleferApp(state: state));
}
