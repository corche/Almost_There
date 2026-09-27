import 'package:alarm_output/alarm_output.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionSnapshot {
  const PermissionSnapshot({
    this.location = false,
    this.notifications = false,
    this.overlay = false,
    this.battery = false,
    this.fullScreen = false,
    this.locationServices = false,
    this.supported = true,
  });
  final bool location, notifications, overlay, battery, fullScreen;
  final bool locationServices, supported;

  /// Overlay and battery exemptions improve availability but do not gate GPS.
  bool get isReady =>
      supported && location && notifications && locationServices;
  bool get allGranted => isReady && overlay && battery && fullScreen;
}

class PermissionService {
  bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get supported => isAndroid || isIOS;

  Future<PermissionSnapshot> inspect() async {
    if (!supported) return const PermissionSnapshot(supported: false);
    return PermissionSnapshot(
      location: await Geolocator.checkPermission() == LocationPermission.always,
      notifications: await Permission.notification.isGranted,
      overlay: !isAndroid || await Permission.systemAlertWindow.isGranted,
      battery:
          !isAndroid || await Permission.ignoreBatteryOptimizations.isGranted,
      fullScreen: !isAndroid || await AlarmOutput.canFullScreen(),
      locationServices: await Geolocator.isLocationServiceEnabled(),
    );
  }

  Future<void> requestLocation() async {
    if (!supported) return;
    var permission = await Permission.locationWhenInUse.request();
    if (permission.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    if (permission.isGranted) {
      permission = await Permission.locationAlways.request();
      if (permission.isPermanentlyDenied) await openAppSettings();
    }
  }

  Future<void> requestNotifications() async {
    if (!supported) return;
    if ((await Permission.notification.request()).isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Future<void> requestOverlay() async {
    if (isAndroid) await Permission.systemAlertWindow.request();
  }

  Future<void> requestBatteryExemption() async {
    if (isAndroid) await Permission.ignoreBatteryOptimizations.request();
  }

  Future<void> requestFullScreen() async {
    if (isAndroid) {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestFullScreenIntentPermission();
    }
  }

  Future<void> openSettings() async {
    if (supported) await openAppSettings();
  }

  Future<void> openLocationSettings() async {
    if (supported) await Geolocator.openLocationSettings();
  }
}
