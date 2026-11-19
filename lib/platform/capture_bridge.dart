import 'dart:io';

import 'package:flutter/services.dart';

import '../services/platform_services.dart';

/// Az automatikus rögzítés platformoldala a `belefer/capture` csatornán:
/// Androidon a Revolut-értesítések sora, iOS-en az Apple Pay-fizetések sora.
class MethodChannelCaptureBridge implements CaptureBridge {
  static const MethodChannel _channel = MethodChannel('belefer/capture');

  @override
  bool get supportsNotifications => Platform.isAndroid;

  @override
  bool get supportsApplePay => Platform.isIOS;

  @override
  Future<List<Map<Object?, Object?>>> drain() async {
    final result = await _channel.invokeListMethod<Object?>('drain');
    return [
      for (final item in result ?? const <Object?>[])
        if (item is Map) item.cast<Object?, Object?>(),
    ];
  }

  @override
  Future<bool> isNotificationAccessGranted() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('isAccessGranted') ?? false;
  }

  @override
  Future<void> openNotificationAccessSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openAccessSettings');
  }

  @override
  Future<void> setRevolutCaptureEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
  }
}
