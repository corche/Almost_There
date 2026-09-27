import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../../data/services/arrival_monitor.dart';
import '../../data/services/permission_service.dart';
import '../../domain/entities/destination.dart';
import '../../domain/repositories/destination_repository.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.settings,
    required this.monitor,
    required this.permissionService,
  });
  final DestinationRepository repository;
  final SettingsRepository settings;
  final ArrivalMonitor monitor;
  final PermissionService permissionService;
  List<Destination> _destinations = [];
  List<Destination> get destinations => List.unmodifiable(_destinations);
  PermissionSnapshot? permissions;
  ThemeMode themeMode = ThemeMode.system;
  bool busy = false;
  String? error;
  StreamSubscription<Destination>? _arrivalSubscription;
  StreamSubscription<String>? _handledArrivalSubscription;
  StreamSubscription<String>? _errorSubscription;
  Future<void> _mutationQueue = Future<void>.value();
  final _alarmEvents = StreamController<Destination>.broadcast();
  Stream<Destination> get alarmEvents => _alarmEvents.stream;
  int get activeCount => _destinations.where((d) => d.enabled).length;
  bool get onboarded => settings.onboardingComplete;

  Future<void> initialize() async {
    _destinations = await repository.load();
    themeMode = ThemeMode.values.firstWhere(
      (t) => t.name == settings.theme,
      orElse: () => ThemeMode.system,
    );
    await monitor.initialize();
    _arrivalSubscription = monitor.arrivals.listen(_handleArrival);
    _handledArrivalSubscription = monitor.handledArrivals.listen(
      (id) => _enqueue(() => _recordArrival(id)),
    );
    _errorSubscription = monitor.errors.listen(reportError);
    await refreshPermissions(sync: false);
    await reconcileArrivals();
    await _sync();
  }

  Future<void> _handleArrival(Destination destination) => _enqueue(() async {
    try {
      await _recordArrival(destination.id);
    } catch (_) {
      reportError('도착 기록을 저장하지 못했습니다.');
    } finally {
      // The platform alarm is already persistent. A local storage failure must
      // never prevent the user from seeing its dismissal screen.
      if (!_alarmEvents.isClosed) _alarmEvents.add(destination);
    }
  });

  Future<void> _recordArrival(String id) async {
    _destinations = _destinations
        .map((d) => d.id == id ? d.copyWith(enabled: false) : d)
        .toList();
    await repository.saveAll(_destinations);
    notifyListeners();
  }

  Future<void> reconcileArrivals() => _enqueue(() async {
    final fired = await monitor.firedIds();
    if (_destinations.any((d) => d.enabled && fired.contains(d.id))) {
      _destinations = _destinations
          .map((d) => fired.contains(d.id) ? d.copyWith(enabled: false) : d)
          .toList();
      await repository.saveAll(_destinations);
      notifyListeners();
    }
  });

  Future<void> refreshPermissions({bool sync = true}) async {
    permissions = await permissionService.inspect();
    notifyListeners();
    if (sync) {
      await reconcileArrivals();
      await _sync();
    }
  }

  Future<void> _sync() async {
    try {
      await monitor.sync(_destinations);
    } catch (_) {
      reportError('도착 감지를 시작하지 못했습니다. 위치 권한과 기기 설정을 확인해 주세요.');
    }
  }

  Future<void> save(Destination destination) {
    var needsRearm = false;
    return _mutate(
      () async {
        final index = _destinations.indexWhere((d) => d.id == destination.id);
        needsRearm =
            destination.enabled && (index < 0 || !_destinations[index].enabled);
        if (index < 0) {
          _destinations.insert(0, destination);
        } else {
          _destinations[index] = destination;
        }
      },
      afterCommit: () async {
        if (needsRearm) await monitor.rearm(destination.id);
      },
    );
  }

  Future<void> setEnabled(Set<String> ids, bool enabled) => _mutate(
    () async {
      _destinations = _destinations
          .map((d) => ids.contains(d.id) ? d.copyWith(enabled: enabled) : d)
          .toList();
    },
    afterCommit: () async {
      if (enabled) {
        for (final id in ids) {
          await monitor.rearm(id);
        }
      }
    },
  );

  Future<void> delete(Set<String> ids) => _mutate(() async {
    _destinations.removeWhere((d) => ids.contains(d.id));
  });

  Future<void> _mutate(
    Future<void> Function() action, {
    Future<void> Function()? afterCommit,
  }) => _enqueue(() async {
    busy = true;
    error = null;
    final previous = List<Destination>.of(_destinations);
    notifyListeners();
    try {
      await action();
      // Reflect a switch tap before disk I/O and geofence rearming. Waiting
      // for those platform calls makes the Material switch appear to stutter.
      notifyListeners();
      await repository.saveAll(_destinations);
      await afterCommit?.call();
      await _sync();
    } catch (_) {
      _destinations = previous;
      error = '저장하지 못했습니다. 잠시 후 다시 시도해 주세요.';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  });

  /// Destination writes and background arrivals share a single commit lane so
  /// a late GPS event cannot overwrite a user's latest edit.
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final operation = _mutationQueue.then((_) => action());
    _mutationQueue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<void> setTheme(ThemeMode value) async {
    await settings.setTheme(value.name);
    themeMode = value;
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    await settings.completeOnboarding();
    notifyListeners();
  }

  void reportError(String message) {
    error = message;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _arrivalSubscription?.cancel();
    _handledArrivalSubscription?.cancel();
    _errorSubscription?.cancel();
    _alarmEvents.close();
    monitor.dispose();
    super.dispose();
  }
}
