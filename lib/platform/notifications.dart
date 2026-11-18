import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/recurring.dart';
import '../services/platform_services.dart';

/// Emlékeztetők a telefon helyi értesítéseivel (internet nélkül).
class LocalReminderScheduler implements ReminderScheduler {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;

  static NotificationDetails _details(String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      'esedekes_tetelek',
      'Esedékes tételek',
      channelDescription:
          'Emlékeztetők az ismétlődő kiadások és bevételek esedékességéről',
      icon: 'ic_stat_belefer',
      color: const Color(0xFF19D3C5),
      styleInformation: BigTextStyleInformation(body),
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
  );

  Future<void> _ensureInitialized() => _initializing ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_belefer'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      )
      .then((_) {});

  @override
  Future<bool> ensurePermission() async {
    await _ensureInitialized();
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (await android?.areNotificationsEnabled() ?? false) return true;
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    await _ensureInitialized();
    await _plugin.cancelAllPendingNotifications();
    for (final reminder in reminders) {
      // A helyi időpont abszolút pillanatként (UTC-ben) ütemezve: a nyári
      // időszámítást a Dart a megadott napra már figyelembe veszi.
      final at = tz.TZDateTime.from(reminder.at, tz.UTC);
      try {
        await _plugin.zonedSchedule(
          id: reminder.id,
          scheduledDate: at,
          notificationDetails: _details(reminder.body),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: reminder.title,
          body: reminder.body,
          payload: 'rule:${reminder.ruleId}',
        );
      } on Object catch (error) {
        debugPrint('Emlékeztető ütemezése sikertelen: $error');
      }
    }
  }

  @override
  Future<void> showNow({required String title, required String body}) async {
    await _ensureInitialized();
    await _plugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: _details(body),
    );
  }
}
