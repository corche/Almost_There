import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';

/// Registered on every Flutter engine, including the Android location service.
class AlarmOutput {
  static const _channel = MethodChannel('almost_there/alarm_output');

  static Future<bool> start({
    String? asset,
    String? filePath,
    required bool earphones,
    required double volume,
    required int fadeSeconds,
    required String owner,
  }) async =>
      await _channel.invokeMethod<bool>('start', {
        'asset': asset,
        'filePath': filePath,
        'earphones': earphones,
        'volume': volume,
        'fadeSeconds': fadeSeconds,
        'owner': owner,
      }) ??
      false;

  static Future<void> stop({String? owner}) =>
      _channel.invokeMethod('stop', {'owner': owner});

  /// Return the activity launched by a real full-screen alarm to the
  /// background after dismissal, instead of exposing the app's home screen.
  static Future<void> hideAlarmTask() => _channel.invokeMethod('hideAlarmTask');

  /// Opens a separate Android system-overlay window for a real arrival.
  static Future<bool> showAlarmOverlay(
    Map<String, dynamic> destination,
  ) async =>
      await _channel.invokeMethod<bool>('showAlarmOverlay', destination) ??
      false;
  static Future<void> hideAlarmOverlay() =>
      _channel.invokeMethod('hideAlarmOverlay');
  static Future<void> showAlarmNotification(Map<String, dynamic> destination) =>
      _channel.invokeMethod('showAlarmNotification', destination);
  static Future<void> dismissOverlay(String id) =>
      _channel.invokeMethod('dismissOverlay', {'id': id});

  static Map<String, dynamic>? overlayPayload() {
    final route = PlatformDispatcher.instance.defaultRouteName;
    final raw = Uri.tryParse(route)?.queryParameters['data'];
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static void setOverlayDismissHandler(
    Future<void> Function(String id) handler,
  ) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'overlayDismiss') throw MissingPluginException();
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      await handler(args['id'] as String);
    });
  }

  static Future<bool> canFullScreen() async =>
      await _channel.invokeMethod<bool>('canFullScreen') ?? false;

  /// Opens Android's document picker and returns an app-owned audio path.
  static Future<String?> pickAudioFile() =>
      _channel.invokeMethod<String>('pickAudioFile');
}
