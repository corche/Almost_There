import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, this.onboarding = false});
  final bool onboarding;
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      await context.read<AppController>().refreshPermissions();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('권한 상태를 확인하지 못했습니다. 다시 시도해 주세요.')),
        );
      }
    }
  }

  Future<void> _request(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기기 설정에서 권한을 직접 확인해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final service = app.permissionService;
    final p = app.permissions;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onboarding ? '다왔어에 오신 걸 환영해요' : '도착 알림을 위한 권한'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.notifications_active_outlined,
                    size: 32,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '편안한 이동을 위한\n작은 준비',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(
                '화면이 꺼져 있어도 도착을 알려드릴 수 있도록\n아래 설정을 차례로 확인해 주세요.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              if (!service.supported)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      '이 기기에서는 화면과 목적지 설정을 사용할 수 있어요. 백그라운드 도착 알림은 Android 또는 iOS 기기에서 설정해 주세요.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              else ...[
                _permission(
                  Icons.location_on_outlined,
                  '위치 · 항상 허용',
                  '앱을 사용하지 않을 때도 목적지까지의 거리를 확인해요. 먼저 앱 사용 중 위치를 허용한 뒤 항상 허용을 선택해 주세요.',
                  p?.location ?? false,
                  service.requestLocation,
                ),
                _permission(
                  Icons.gps_fixed_rounded,
                  '기기 위치 서비스',
                  'GPS를 켜 두어야 도착을 감지할 수 있어요.',
                  p?.locationServices ?? false,
                  service.openLocationSettings,
                ),
                _permission(
                  Icons.notifications_none_rounded,
                  '알림 허용',
                  '도착 알림과 감지 중 상태를 표시해요.',
                  p?.notifications ?? false,
                  service.requestNotifications,
                ),
                if (service.isAndroid) ...[
                  _permission(
                    Icons.fullscreen_rounded,
                    '전체 화면 알림',
                    '잠금 화면에서 도착 알람을 표시할 수 있도록 허용해 주세요.',
                    p?.fullScreen ?? false,
                    service.requestFullScreen,
                  ),
                  _permission(
                    Icons.layers_outlined,
                    '다른 앱 위에 표시',
                    '다른 앱을 사용하는 동안의 알림 표시를 위한 보조 설정이에요.',
                    p?.overlay ?? false,
                    service.requestOverlay,
                  ),
                  _permission(
                    Icons.battery_charging_full_rounded,
                    '배터리 사용 제한 해제',
                    '절전 기능으로 위치 감지가 멈추지 않도록 앱의 배터리 사용을 제한 없음으로 설정해 주세요.',
                    p?.battery ?? false,
                    service.requestBatteryExemption,
                  ),
                ],
                if (service.isIOS)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'iOS에서는 도착 알림을 누르면 알람 화면이 열려요. 앱을 강제 종료하면 위치 감지가 중단될 수 있어요.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await app.completeOnboarding();
                        if (context.mounted) Navigator.pop(context);
                      },
                child: Text(p?.isReady == true ? '준비됐어요' : '지금 설정으로 시작하기'),
              ),
              const SizedBox(height: 12),
              Text(
                '권한은 설정에서 언제든 변경할 수 있어요.\n필수 권한이 없으면 도착 감지가 실행되지 않아요.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permission(
    IconData icon,
    String title,
    String description,
    bool granted,
    Future<void> Function() action,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    color: granted ? const Color(0xFF7D9463) : scheme.primary,
                    size: 23,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (granted)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF7D9463),
                      size: 22,
                    )
                  else
                    TextButton(
                      onPressed: _busy ? null : () => _request(action),
                      child: const Text('설정'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
