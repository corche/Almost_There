import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/hive_destination_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/arrival_monitor.dart';
import 'data/services/permission_service.dart';
import 'presentation/controllers/app_controller.dart';
import 'overlay_main.dart';

@pragma('vm:entry-point')
Future<void> overlayMain() => runAlarmOverlay();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final controller = AppController(
      repository: await HiveDestinationRepository.open(),
      settings: SettingsRepository(await SharedPreferences.getInstance()),
      monitor: ArrivalMonitor(),
      permissionService: PermissionService(),
    );
    await controller.initialize();
    runApp(AlmostThereApp(controller: controller));
  } catch (error, stack) {
    debugPrint('App initialization failed: $error\n$stack');
    runApp(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.storage_rounded,
                      size: 42,
                      color: AppTheme.orange,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '저장된 설정을 불러오지 못했어요.\n앱을 다시 실행해 주세요.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: main, child: const Text('다시 시도')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
