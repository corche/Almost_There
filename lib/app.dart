import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:alarm_output/alarm_output.dart';

import 'core/theme/app_theme.dart';
import 'data/services/alarm_audio_service.dart';
import 'domain/entities/destination.dart';
import 'presentation/controllers/app_controller.dart';
import 'presentation/screens/alarm_screen.dart';
import 'presentation/screens/destination_editor_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/permissions_screen.dart';
import 'presentation/screens/settings_screen.dart';

class AlmostThereApp extends StatelessWidget {
  const AlmostThereApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: controller,
    child: Consumer<AppController>(
      builder: (context, app, _) => MaterialApp(
        title: '다왔어 · Almost There',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: app.themeMode,
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const _AppShell(),
      ),
    ),
  );
}

class _AppShell extends StatefulWidget {
  const _AppShell();
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  int _tab = 0;
  late final PageController _tabController;
  bool _permissionOpen = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  String? _alarmId;
  bool _alarmPreview = false;
  int _alarmSession = 0;
  ModalRoute<void>? _alarmRoute;
  StreamSubscription<Destination>? _subscription;
  final _previewAudio = AlarmAudioService();

  @override
  void initState() {
    super.initState();
    _tabController = PageController();
    WidgetsBinding.instance.addObserver(this);
    final app = context.read<AppController>();
    _subscription = app.alarmEvents.listen(
      (destination) => _showAlarm(
        destination,
        hideTaskOnDismiss: _lifecycle != AppLifecycleState.resumed,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkStartup(app));
  }

  Future<void> _checkStartup(AppController app) async {
    try {
      final pending = await app.monitor.pendingAlarm();
      if (!mounted) return;
      if (pending != null) {
        _showAlarm(pending, hideTaskOnDismiss: true);
      } else if (!app.onboarded ||
          (app.permissionService.supported &&
              app.permissions?.allGranted != true)) {
        _showPermissions(onboarding: !app.onboarded);
      }
    } catch (_) {
      app.reportError('도착 알림 상태를 불러오지 못했습니다. 권한을 다시 확인해 주세요.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) _resume();
  }

  Future<void> _resume() async {
    final app = context.read<AppController>();
    try {
      await app.refreshPermissions();
      final pending = await app.monitor.pendingAlarm();
      if (!mounted) return;
      if (pending != null) {
        _showAlarm(pending, hideTaskOnDismiss: true);
      } else if (app.permissionService.supported &&
          app.permissions?.allGranted != true) {
        _showPermissions();
      }
    } catch (_) {
      app.reportError('위치 감지 상태를 확인하지 못했습니다. 권한 설정을 확인해 주세요.');
    }
  }

  Future<void> _showPermissions({bool onboarding = false}) async {
    if (_permissionOpen || !mounted) return;
    _permissionOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PermissionsScreen(onboarding: onboarding),
      ),
    );
    _permissionOpen = false;
  }

  Future<void> _edit(Destination? destination) async {
    final app = context.read<AppController>();
    final result = await Navigator.of(context).push<Destination>(
      MaterialPageRoute(
        builder: (_) =>
            DestinationEditorScreen(destination: destination, onSave: app.save),
      ),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${result.name} 목적지를 저장했어요')));
    }
  }

  Future<void> _showAlarm(
    Destination destination, {
    bool preview = false,
    bool hideTaskOnDismiss = false,
  }) async {
    if (!mounted) return;
    if (_alarmId != null) {
      if (preview || !_alarmPreview) return;
      // A real arrival always takes precedence over a settings preview.
      _alarmSession++;
      await _previewAudio.stop();
      final route = _alarmRoute;
      if (route != null && route.isActive && mounted) {
        Navigator.of(context).removeRoute(route);
      }
      _alarmId = null;
      _alarmRoute = null;
    }
    final session = ++_alarmSession;
    _alarmId = destination.id;
    _alarmPreview = preview;
    if (preview) {
      try {
        await _previewAudio.start(destination);
      } catch (_) {
        /* The full-screen preview remains usable without audio output. */
      }
    }
    if (!mounted) return;
    final app = context.read<AppController>();
    late MaterialPageRoute<void> route;
    route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AlarmScreen(
        destination: destination,
        preview: preview,
        onDismiss: () async {
          if (preview) {
            await _previewAudio.stop();
          } else {
            await app.monitor.dismiss(destination.id);
            if (hideTaskOnDismiss) {
              // Hide only alarms that brought this task forward from the
              // background. An in-app arrival must leave the user in the app.
              await AlarmOutput.hideAlarmTask();
            }
          }
          if (mounted && route.isCurrent) Navigator.of(context).pop();
        },
      ),
    );
    _alarmRoute = route;
    await Navigator.of(context).push(route);
    if (preview) await _previewAudio.stop();
    if (session != _alarmSession) return;
    _alarmId = null;
    _alarmPreview = false;
    _alarmRoute = null;
    final pending = await app.monitor.pendingAlarm();
    if (mounted && pending != null) _showAlarm(pending);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _previewAudio.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: PageView(
              controller: _tabController,
              onPageChanged: (value) => setState(() => _tab = value),
              children: [
                HomeScreen(onEdit: _edit, onPermissions: _showPermissions),
                SettingsScreen(
                  onPermissions: _showPermissions,
                  onPreview: () => _showAlarm(
                    app.destinations.firstOrNull ??
                        const Destination(
                          id: 'preview',
                          name: '서울역',
                          latitude: 37.5547,
                          longitude: 126.9707,
                        ),
                    preview: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) {
            if (value == _tab) return;
            _tabController.animateToPage(
              value,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.near_me_outlined),
              selectedIcon: Icon(Icons.near_me_rounded),
              label: '나의 목적지',
            ),
            NavigationDestination(icon: Icon(Icons.tune_rounded), label: '설정'),
          ],
        ),
      ),
    );
  }
}
