import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../services/platform_services.dart';

/// A kezdőképernyő-widget adatai és a widgetről érkező megnyitások.
///
/// Androidon a widget az alkalmazás saját tárolójából olvas. iOS-en a
/// widget-bővítmény és az alkalmazás egy közös App Groupon osztozik; mivel
/// az ingyenes telepítés (SideStore) átnevezheti a csoportot, a tényleges
/// azonosítót a telepítéskor kapott profilból olvassuk ki.
class HomeWidgetService implements WidgetPublisher, AppLinks {
  static const String fallbackAppGroup = 'group.com.ventyh1.belefer';
  static const String androidProvider =
      'com.ventyh1.belefer.BeleferWidgetProvider';
  static const String iosKind = 'BeleferWidget';

  Future<void>? _setup;

  Future<void> _ensureSetup() => _setup ??= () async {
    if (Platform.isIOS) {
      await HomeWidget.setAppGroupId(discoverAppGroup() ?? fallbackAppGroup);
    }
  }();

  @override
  Future<void> publish(HomeWidgetData data) async {
    await _ensureSetup();
    for (final entry in data.toMap().entries) {
      await HomeWidget.saveWidgetData<String>(
        'belefer_${entry.key}',
        entry.value,
      );
    }
    await HomeWidget.updateWidget(
      qualifiedAndroidName: androidProvider,
      iOSName: iosKind,
    );
  }

  @override
  Future<Uri?> initialLink() async {
    try {
      await _ensureSetup();
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } on Object catch (error) {
      debugPrint('Widget-indítás nem olvasható: $error');
      return null;
    }
  }

  @override
  Stream<Uri> get links => HomeWidget.widgetClicked
      .where((uri) => uri != null && uri.host.isNotEmpty)
      .cast<Uri>();
}

/// Az alkalmazás App Group azonosítója a beágyazott telepítési profilból
/// (`embedded.mobileprovision`), vagy `null`, ha nincs ilyen.
String? discoverAppGroup() {
  try {
    final appDirectory = File(Platform.resolvedExecutable).parent;
    final profile = File('${appDirectory.path}/embedded.mobileprovision');
    if (!profile.existsSync()) return null;
    return appGroupFromProfile(latin1.decode(profile.readAsBytesSync()));
  } on Object {
    return null;
  }
}

/// Az első `com.apple.security.application-groups` elem a profil
/// szövegéből.
@visibleForTesting
String? appGroupFromProfile(String profile) {
  final match = RegExp(
    r'<key>com\.apple\.security\.application-groups</key>\s*<array>\s*'
    r'<string>([^<]+)</string>',
  ).firstMatch(profile);
  return match?.group(1)?.trim();
}
