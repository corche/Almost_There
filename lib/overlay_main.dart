import 'package:alarm_output/alarm_output.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'core/theme/app_theme.dart';
import 'domain/entities/destination.dart';
import 'presentation/screens/alarm_screen.dart';

/// Shared UI for the Android overlay and the dedicated lock-screen Activity.
/// Each host closes independently of the main app when the alarm is dismissed.
@pragma('vm:entry-point')
Future<void> runAlarmOverlay() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This engine has no Activity/PlatformPlugin to answer SystemChrome calls.
  // Awaiting one here prevents runApp from ever being reached.
  final payload = AlarmOutput.overlayPayload();
  if (payload == null) {
    await AlarmOutput.hideAlarmOverlay();
    return;
  }
  runApp(_AlarmOverlayApp(destination: Destination.fromJson(payload)));
  if (kDebugMode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('AlarmOverlay: first Flutter frame rendered');
    });
  }
}

class _AlarmOverlayApp extends StatelessWidget {
  const _AlarmOverlayApp({required this.destination});
  final Destination destination;

  Future<void> _dismiss() async {
    await AlarmOutput.stop();
    await AlarmOutput.dismissOverlay(destination.id);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    // The initial route carries data only; the overlay has a single screen.
    initialRoute: '/',
    home: Listener(
      onPointerDown: kDebugMode
          ? (_) => debugPrint('AlarmOverlay: Dart pointer down')
          : null,
      onPointerUp: kDebugMode
          ? (_) => debugPrint('AlarmOverlay: Dart pointer up')
          : null,
      child: AlarmScreen(destination: destination, onDismiss: _dismiss),
    ),
  );
}
