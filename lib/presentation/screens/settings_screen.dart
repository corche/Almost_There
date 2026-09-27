import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../data/services/arrival_diagnostics.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.onPermissions,
    required this.onPreview,
  });
  final VoidCallback onPermissions, onPreview;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 40),
      children: [
        Text('설정', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        Text('나에게 맞는 편안한 여정', style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 32),
        Text('화면 스타일', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                for (final mode in ThemeMode.values)
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onTap: () async {
                      try {
                        await app.setTheme(mode);
                      } catch (_) {
                        app.reportError('테마 설정을 저장하지 못했습니다.');
                      }
                    },
                    leading: Icon(switch (mode) {
                      ThemeMode.system => Icons.brightness_auto_outlined,
                      ThemeMode.light => Icons.light_mode_outlined,
                      ThemeMode.dark => Icons.dark_mode_outlined,
                    }),
                    title: Text(switch (mode) {
                      ThemeMode.system => '시스템 설정에 맞추기',
                      ThemeMode.light => '라이트 모드',
                      ThemeMode.dark => '다크 모드',
                    }),
                    trailing: Icon(
                      mode == app.themeMode
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: mode == app.themeMode
                          ? scheme.primary
                          : scheme.outlineVariant,
                    ),
                    selected: mode == app.themeMode,
                    selectedTileColor: scheme.primary.withValues(alpha: .06),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 30),
        Text('도착 알림', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        Card(
          child: Column(
            children: [
              _row(
                context,
                Icons.shield_outlined,
                '권한 및 백그라운드 실행',
                app.permissions?.allGranted == true
                    ? '알림을 위한 준비가 완료됐어요'
                    : '위치 · 알림 · 배터리 설정 확인',
                onPermissions,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(),
              ),
              _row(
                context,
                Icons.play_circle_outline_rounded,
                '도착 알림 테스트',
                '저장한 목적지의 전체 화면·소리·진동을 지금 확인해요',
                onPreview,
              ),
              _row(
                context,
                Icons.history_rounded,
                '위치 감지 기록',
                '위치 수신과 알람 지연 원인 확인',
                () async {
                  try {
                    final log = await ArrivalDiagnostics().read();
                    if (!context.mounted) return;
                    await showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('위치 감지 기록'),
                        content: SizedBox(
                          width: 600,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              log.isEmpty
                                  ? '아직 기록이 없어요. 목적지 알림을 켜면 기록을 시작해요.'
                                  : log,
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('닫기'),
                          ),
                        ],
                      ),
                    );
                  } catch (_) {
                    app.reportError('위치 감지 기록을 불러오지 못했어요.');
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Text('다왔어 안내', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.near_me_rounded, color: scheme.primary),
                    const SizedBox(width: 9),
                    Text('다왔어', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    Text('1.0.1', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '목적지에 가까워지면, 부드럽게 알려드려요.\n알림이 울린 목적지는 자동으로 꺼집니다. 다음 여정에서 다시 켜 주세요.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  '목적지는 기기에 저장됩니다. 지도 조회 시 지도 서비스에 접속하며, 장소 검색을 사용하면 검색어가 검색 제공자에게 전달됩니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: Text(
            'ALMOST THERE  /  A LITTLE PEACE OF MIND',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.7,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback tap,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: tap,
  );
}
