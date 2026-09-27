import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alarm_output/alarm_output.dart';

import '../../domain/entities/destination.dart';
import '../../domain/services/location_sampling_policy.dart';
import 'alarm_audio_service.dart';
import 'arrival_diagnostics.dart';

const _configKey = 'arrival.destinations.v1';
const _activeKey = 'arrival.active.v1';
const _firedPrefix = 'arrival.fired.';
const _serviceChannel = 'arrival_location';
const _alarmChannel = 'arrival_alarm_silent_v1';
const _alarmNotificationId = 4201;
const _serviceNotificationId = 4200;

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

Future<void> _initNotifications(
  FlutterLocalNotificationsPlugin notifications, {
  void Function(NotificationResponse)? onResponse,
}) async {
  await notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_arrival'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
    onDidReceiveNotificationResponse: onResponse,
  );
  final android = notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      _serviceChannel,
      '목적지 감지',
      description: '이동 중 위치를 확인합니다.',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ),
  );
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      _alarmChannel,
      '도착 알림',
      description: '목적지에 도착하면 알려드립니다.',
      importance: Importance.max,
      playSound: false,
      enableVibration: false,
    ),
  );
}

Future<List<Destination>> _readDestinations(
  SharedPreferencesAsync prefs,
) async {
  final raw = await prefs.getString(_configKey);
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map(
        (item) => Destination.fromJson(Map<String, dynamic>.from(item as Map)),
      )
      .toList();
}

Future<Destination?> _readActive(SharedPreferencesAsync prefs) async {
  final raw = await prefs.getString(_activeKey);
  if (raw == null) return null;
  return Destination.fromJson(
    Map<String, dynamic>.from(jsonDecode(raw) as Map),
  );
}

/// Android uses one foreground service/isolate as the sole GPS/audio owner.
/// iOS uses the main engine's Core Location stream with location background mode.
/// UI Hive storage is never opened from the worker isolate.
class ArrivalMonitor {
  final _prefs = SharedPreferencesAsync();
  final _service = FlutterBackgroundService();
  final _notifications = FlutterLocalNotificationsPlugin();
  final _arrivals = StreamController<Destination>.broadcast();
  final _handledArrivals = StreamController<String>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _audio = AlarmAudioService();
  StreamSubscription<Map<String, dynamic>?>? _arrivalSubscription;
  StreamSubscription<Map<String, dynamic>?>? _handledArrivalSubscription;
  StreamSubscription<Map<String, dynamic>?>? _errorSubscription;
  StreamSubscription<Position>? _positionSubscription;
  bool _checking = false;
  bool _initialized = false;
  List<Destination> _destinations = [];

  Stream<Destination> get arrivals => _arrivals.stream;
  Stream<String> get handledArrivals => _handledArrivals.stream;
  Stream<String> get errors => _errors.stream;

  Future<void> initialize() async {
    if (_initialized || (!_android && !_ios)) return;
    await _initNotifications(
      _notifications,
      onResponse: (_) async {
        final active = await pendingAlarm();
        if (active != null && !_arrivals.isClosed) _arrivals.add(active);
      },
    );
    if (_android) {
      _arrivalSubscription = _service.on('arrival').listen((event) {
        if (event != null) _arrivals.add(Destination.fromJson(event));
      });
      _handledArrivalSubscription = _service.on('arrivalHandled').listen((
        event,
      ) {
        final id = event?['id'] as String?;
        if (id != null) _handledArrivals.add(id);
      });
      _errorSubscription = _service.on('monitorError').listen((event) {
        _errors.add(event?['message'] as String? ?? '위치 감지가 중단되었습니다.');
      });
      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: arrivalServiceEntryPoint,
          isForegroundMode: true,
          autoStart: false,
          autoStartOnBoot: false,
          notificationChannelId: _serviceChannel,
          initialNotificationTitle: '다왔어 · 도착 알림 켜짐',
          initialNotificationContent: '목적지까지의 거리를 확인하고 있어요.',
          foregroundServiceNotificationId: _serviceNotificationId,
          foregroundServiceTypes: [
            AndroidForegroundType.location,
            AndroidForegroundType.mediaPlayback,
          ],
        ),
        iosConfiguration: IosConfiguration(autoStart: false),
      );
    }
    _initialized = true;
  }

  Future<Set<String>> firedIds() async {
    final keys = await _prefs.getKeys();
    return keys
        .where((key) => key.startsWith(_firedPrefix))
        .map((key) => key.substring(_firedPrefix.length))
        .toSet();
  }

  /// Only explicit user activation re-arms an already fired destination.
  Future<void> rearm(String id) => _prefs.remove('$_firedPrefix$id');

  Future<Destination?> pendingAlarm() async {
    if (!_android && !_ios) return null;
    return _readActive(_prefs);
  }

  Future<void> sync(List<Destination> destinations) async {
    _destinations = List.unmodifiable(destinations);
    if (!_android && !_ios) return;
    await initialize();
    await _prefs.setString(
      _configKey,
      jsonEncode(destinations.map((item) => item.toJson()).toList()),
    );
    final fired = await firedIds();
    final hasEnabled = destinations.any(
      (item) => item.enabled && !fired.contains(item.id),
    );
    if (!hasEnabled && await pendingAlarm() == null) {
      if (_android) {
        _service.invoke('sync');
      } else {
        await stop();
      }
      return;
    }
    if (hasEnabled) {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always ||
          !await Geolocator.isLocationServiceEnabled()) {
        await stop();
        throw StateError('백그라운드 위치를 항상 허용하고 기기 위치를 켜주세요.');
      }
    }
    if (_android) {
      if (!await _service.isRunning()) {
        if (!await _service.startService()) {
          throw StateError('백그라운드 위치 서비스를 시작하지 못했어요.');
        }
      }
      _service.invoke('sync');
    } else if (_ios && hasEnabled && _positionSubscription == null) {
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: AppleSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 20,
              activityType: ActivityType.otherNavigation,
              pauseLocationUpdatesAutomatically: false,
              showBackgroundLocationIndicator: true,
              allowBackgroundLocationUpdates: true,
            ),
          ).listen(
            _checkPosition,
            onError: (Object error) {
              _errors.add('위치를 확인할 수 없어요. 위치 권한과 GPS를 확인해주세요.');
              unawaited(_positionSubscription?.cancel());
              _positionSubscription = null;
            },
          );
    }
  }

  Future<void> _checkPosition(Position position) async {
    if (_checking) return;
    _checking = true;
    try {
      final destination = await _findArrival(position, _destinations, _prefs);
      if (destination == null) return;
      await _persistArrival(destination, _prefs);
      await _showAlarm(_notifications, destination);
      try {
        await _audio.start(destination);
      } catch (_) {
        _errors.add('알람 소리를 재생하지 못했어요. 오디오 출력을 확인해주세요.');
      }
      _arrivals.add(destination);
    } catch (_) {
      _errors.add('도착 알림 처리에 실패했어요. 앱을 다시 열어주세요.');
    } finally {
      _checking = false;
    }
  }

  Future<void> dismiss(String id) async {
    final active = await pendingAlarm();
    if (active?.id != id) return;
    // Stop native playback immediately, even before the worker receives IPC.
    await _audio.stop(all: true);
    await _prefs.remove(_activeKey);
    await _notifications.cancel(_alarmNotificationId);
    if (_android) _service.invoke('dismiss', {'id': id});
    if (_ios) await sync(_destinations);
  }

  Future<void> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (_android && _initialized) _service.invoke('stop');
  }

  Future<void> dispose() async {
    await _arrivalSubscription?.cancel();
    await _handledArrivalSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _arrivals.close();
    await _handledArrivals.close();
    await _errors.close();
    // Do not stop Android service/audio when the UI engine goes away.
  }
}

Future<Destination?> _findArrival(
  Position position,
  List<Destination> destinations,
  SharedPreferencesAsync prefs,
) async {
  if (await _readActive(prefs) != null) return null;
  if (DateTime.now().difference(position.timestamp).abs() >
      const Duration(minutes: 2)) {
    return null;
  }
  for (final destination in destinations) {
    if (!destination.enabled ||
        await prefs.getBool('$_firedPrefix${destination.id}') == true) {
      continue;
    }
    // Ignore fixes whose accuracy is wider than the user's detection circle.
    if (!position.accuracy.isFinite || position.accuracy > destination.radius) {
      continue;
    }
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      destination.latitude,
      destination.longitude,
    );
    if (distance <= destination.radius) return destination;
  }
  return null;
}

Future<void> _persistArrival(
  Destination destination,
  SharedPreferencesAsync prefs,
) async {
  await prefs.setBool('$_firedPrefix${destination.id}', true);
  await prefs.setString(_activeKey, jsonEncode(destination.toJson()));
}

Future<void> _showAlarm(
  FlutterLocalNotificationsPlugin notifications,
  Destination destination,
) async {
  if (_android) {
    await AlarmOutput.showAlarmNotification(destination.toJson());
    return;
  }
  await notifications.show(
    _alarmNotificationId,
    '${destination.name}에 다왔어요',
    '목적지에 도착했어요. 알람을 밀어서 종료해주세요.',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _alarmChannel,
        '도착 알림',
        icon: 'ic_stat_arrival',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        playSound: false,
        enableVibration: false,
        ongoing: true,
        autoCancel: false,
        visibility: NotificationVisibility.public,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: false),
    ),
    payload: destination.id,
  );
}

Future<bool> _showAlarmOverlay(Destination destination) async {
  if (!_android) return false;
  try {
    return await AlarmOutput.showAlarmOverlay(destination.toJson());
  } catch (_) {
    // The full-screen notification remains available if an OEM blocks the
    // overlay despite the granted system permission.
    return false;
  }
}

@pragma('vm:entry-point')
Future<void> arrivalServiceEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final worker = _ArrivalWorker(service);
  await worker.start();
}

class _ArrivalWorker {
  _ArrivalWorker(this.service);
  final ServiceInstance service;
  final prefs = SharedPreferencesAsync();
  final notifications = FlutterLocalNotificationsPlugin();
  final audio = AlarmAudioService();
  List<Destination> destinations = [];
  StreamSubscription<Position>? locations;
  Timer? locationRetry;
  Timer? locationWatchdog;
  final diagnostics = ArrivalDiagnostics();
  final watchdogClock = Stopwatch()..start();
  Duration lastFreshAt = Duration.zero;
  DateTime? lastFixTime;
  DateTime? lastDiagnosticAt;
  int silentRecoveries = 0;
  double lastBoundaryDistance = double.infinity;
  double lastTravelSpeed = 0;
  Duration? lastRecoveryAt;
  Duration? recoveryUntil;
  List<Destination> armedDestinations = [];
  int samplingSeconds = 5;
  int locationGeneration = 0;
  DateTime? samplingChangedAt;
  final List<StreamSubscription<Map<String, dynamic>?>> subscriptions = [];
  bool checking = false;
  bool shuttingDown = false;
  int locationRetryAttempt = 0;
  Future<void> _queue = Future.value();

  Future<void> _enqueue(Future<void> Function() action) {
    _queue = _queue.then((_) => action()).catchError((Object error) {
      service.invoke('monitorError', {
        'message': '위치 감지가 중단되었어요. 권한과 GPS를 확인해주세요.',
      });
    });
    return _queue;
  }

  Future<void> _dismissFromOverlay(String id) async {
    final active = await _readActive(prefs);
    // A queued dismiss for the preceding alarm must not stop a newer arrival.
    if (active != null && active.id != id) return;
    await audio.stop();
    await notifications.cancel(_alarmNotificationId);
    await prefs.remove(_activeKey);
    service.invoke('arrivalHandled', {'id': id});
    await reload();
  }

  Future<void> start() async {
    await diagnostics.record('worker_started');
    await _initNotifications(notifications);
    AlarmOutput.setOverlayDismissHandler(
      (id) => _enqueue(() => _dismissFromOverlay(id)),
    );
    subscriptions.add(service.on('sync').listen((_) => _enqueue(reload)));
    subscriptions.add(
      service
          .on('dismiss')
          .listen(
            (event) =>
                _enqueue(() => _dismissFromOverlay(event?['id'] as String)),
          ),
    );
    subscriptions.add(service.on('stop').listen((_) => _enqueue(shutdown)));
    await reload();
    if (!shuttingDown) {
      locationWatchdog = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(_enqueue(_checkLocationSilence));
      });
    }
    final active = await _readActive(prefs);
    if (active != null && !shuttingDown) {
      await _showAlarm(notifications, active);
      final overlayShown = await _showAlarmOverlay(active);
      try {
        await audio.start(active);
      } catch (_) {
        service.invoke('monitorError', {
          'message': '알람 소리를 재생하지 못했어요. 오디오 출력을 확인해주세요.',
        });
      }
      if (!overlayShown) service.invoke('arrival', active.toJson());
    }
  }

  Future<void> reload() async {
    if (shuttingDown) return;
    destinations = await _readDestinations(prefs);
    armedDestinations = [];
    for (final destination in destinations) {
      if (destination.enabled &&
          await prefs.getBool('$_firedPrefix${destination.id}') != true) {
        armedDestinations.add(destination);
      }
    }
    final enabled = armedDestinations.length;
    if (enabled == 0) {
      locationGeneration++;
      locationRetry?.cancel();
      locationRetry = null;
      await locations?.cancel();
      locations = null;
      if (await _readActive(prefs) == null) {
        if (service is AndroidServiceInstance) {
          await (service as AndroidServiceInstance).setAutoStartOnBootMode(
            false,
          );
        }
        await shutdown();
      }
      return;
    }
    if (service is AndroidServiceInstance) {
      final androidService = service as AndroidServiceInstance;
      // Continue a deliberately armed trip after a reboot or package update.
      await androidService.setAutoStartOnBootMode(true);
      await androidService.setForegroundNotificationInfo(
        title: '다왔어 · $enabled개 목적지 감지 중',
        content: '목적지에 도착하면 알려드릴게요.',
      );
    }
    // A newly enabled/edited destination may be nearby. Re-evaluate at 5s.
    await _setSampling(5);
  }

  Future<void> _setSampling(int seconds, {bool reconnect = false}) async {
    if (shuttingDown) return;
    if (!reconnect && locations != null && samplingSeconds == seconds) return;
    final token = ++locationGeneration;
    locationRetry?.cancel();
    locationRetry = null;
    await locations?.cancel();
    locations = null;
    samplingSeconds = seconds;
    samplingChangedAt = DateTime.now();
    lastFreshAt = watchdogClock.elapsed;
    await diagnostics.record(
      'location_request interval=$seconds provider=fused',
    );
    try {
      locations =
          Geolocator.getPositionStream(
            locationSettings: AndroidSettings(
              forceLocationManager: false,
              accuracy: LocationAccuracy.high,
              // Let time-based updates report departure even after a stop.
              distanceFilter: 0,
              intervalDuration: Duration(seconds: seconds),
            ),
          ).listen(
            (position) => _enqueue(() async {
              if (token == locationGeneration) await check(position);
            }),
            onError: (Object error) {
              _enqueue(() async {
                if (token == locationGeneration) {
                  await _retryLocationStream(error);
                }
              });
            },
            onDone: () => _enqueue(() async {
              if (token == locationGeneration) {
                await _retryLocationStream(
                  StateError('Location stream closed'),
                );
              }
            }),
          );
    } catch (error) {
      await _retryLocationStream(error);
    }
  }

  Future<void> _adaptSampling(Position position) async {
    var nearest = double.infinity;
    for (final destination in armedDestinations) {
      final distance =
          Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            destination.latitude,
            destination.longitude,
          ) -
          destination.radius;
      if (distance < nearest) nearest = distance;
    }
    final seconds = LocationSamplingPolicy.intervalSeconds(
      distanceToBoundary: nearest,
      speed: position.speed,
      accuracy: position.accuracy,
      fixAge: DateTime.now().difference(position.timestamp),
    );
    lastBoundaryDistance = nearest;
    if (position.speed.isFinite && position.speed >= 0) {
      lastTravelSpeed = position.speed;
    }
    if (recoveryUntil != null && watchdogClock.elapsed < recoveryUntil!) {
      await _setSampling(5);
      return;
    }
    // Speed up immediately; delay slowing down to avoid restarting the GPS
    // stream repeatedly near a distance threshold.
    if (seconds > samplingSeconds &&
        samplingChangedAt != null &&
        DateTime.now().difference(samplingChangedAt!) <
            const Duration(seconds: 30)) {
      return;
    }
    await _setSampling(seconds);
  }

  Future<void> _checkLocationSilence() async {
    if (shuttingDown ||
        armedDestinations.isEmpty ||
        locations == null ||
        locationRetry != null) {
      return;
    }
    final silence = watchdogClock.elapsed - lastFreshAt;
    final approaching = LocationSamplingPolicy.approachingDuringSilence(
      distanceToBoundary: lastBoundaryDistance,
      speed: lastTravelSpeed,
      silence: silence,
    );
    if (!LocationSamplingPolicy.needsReconnect(
          requestedSeconds: samplingSeconds,
          silence: silence,
        ) &&
        !(approaching &&
            samplingSeconds > 5 &&
            silence >= const Duration(seconds: 15))) {
      return;
    }
    // Give the provider time to reacquire a fix after a tunnel.
    if (lastRecoveryAt != null &&
        watchdogClock.elapsed - lastRecoveryAt! < const Duration(seconds: 90)) {
      return;
    }
    lastRecoveryAt = watchdogClock.elapsed;
    recoveryUntil = watchdogClock.elapsed + const Duration(minutes: 2);
    silentRecoveries++;
    // Keep fused GPS/Wi-Fi/cell positioning during satellite signal loss.
    await diagnostics.record(
      'location_silent elapsed=${(watchdogClock.elapsed - lastFreshAt).inSeconds}s recovery=$silentRecoveries',
    );
    if (service is AndroidServiceInstance) {
      await (service as AndroidServiceInstance).setForegroundNotificationInfo(
        title: '다왔어 · 위치 신호 재연결 중',
        content: '새 위치를 받지 못하고 있어요. 도착 감지가 지연될 수 있어요.',
      );
    }
    await _setSampling(5, reconnect: true);
  }

  /// Location providers can briefly fail while a device enters Doze, changes
  /// networks, or reconnects to GPS. Keep the foreground service alive and
  /// reconnect instead of treating that transient failure as a user stop.
  Future<void> _retryLocationStream(Object error) async {
    if (shuttingDown) return;
    await diagnostics.record('location_error type=${error.runtimeType}');
    locationGeneration++;
    await locations?.cancel();
    locations = null;
    locationRetry?.cancel();
    final attempt = locationRetryAttempt++;
    final seconds = (15 * (attempt + 1)).clamp(15, 120).toInt();
    service.invoke('monitorError', {
      'message': '위치 신호를 다시 연결하고 있어요. $seconds 초 뒤 재시도합니다.',
    });
    locationRetry = Timer(Duration(seconds: seconds), () {
      locationRetry = null;
      unawaited(_enqueue(reload));
    });
  }

  Future<void> check(Position position) async {
    if (checking || shuttingDown) return;
    locationRetryAttempt = 0;
    checking = true;
    try {
      final now = DateTime.now();
      final age = now.difference(position.timestamp).abs();
      if (age <= const Duration(seconds: 30) &&
          (lastFixTime == null || position.timestamp.isAfter(lastFixTime!))) {
        lastFreshAt = watchdogClock.elapsed;
        lastFixTime = position.timestamp;
        if (silentRecoveries > 0 && service is AndroidServiceInstance) {
          await (service as AndroidServiceInstance)
              .setForegroundNotificationInfo(
                title: '다왔어 · ${armedDestinations.length}개 목적지 감지 중',
                content: '목적지에 도착하면 알려드릴게요.',
              );
        }
        silentRecoveries = 0;
      }
      final destination = await _findArrival(position, destinations, prefs);
      if (destination == null) {
        if (lastDiagnosticAt == null ||
            now.difference(lastDiagnosticAt!) >= const Duration(seconds: 30)) {
          lastDiagnosticAt = now;
          final distances = armedDestinations
              .map((d) {
                final distance = Geolocator.distanceBetween(
                  position.latitude,
                  position.longitude,
                  d.latitude,
                  d.longitude,
                );
                final reason = age > const Duration(minutes: 2)
                    ? 'stale'
                    : !position.accuracy.isFinite ||
                          position.accuracy > d.radius
                    ? 'accuracy'
                    : distance > d.radius
                    ? 'outside'
                    : 'inside';
                return 'distance=${distance.round()}m radius=${d.radius.round()}m $reason';
              })
              .join('; ');
          await diagnostics.record(
            'fix age=${age.inSeconds}s accuracy=${position.accuracy}m speed=${position.speed}m/s $distances',
          );
        }
        await _adaptSampling(position);
        return;
      }
      await _persistArrival(destination, prefs);
      await _showAlarm(notifications, destination);
      final overlayShown = await _showAlarmOverlay(destination);
      try {
        await audio.start(destination);
        await diagnostics.record('alarm_audio_started');
      } catch (_) {
        await diagnostics.record('alarm_audio_failed');
        service.invoke('monitorError', {
          'message': '알람 소리를 재생하지 못했어요. 오디오 출력을 확인해주세요.',
        });
      }
      if (!overlayShown) service.invoke('arrival', destination.toJson());
      await diagnostics.record('arrival_committed notification_posted');
      await reload();
    } finally {
      checking = false;
    }
  }

  Future<void> shutdown() async {
    if (shuttingDown) return;
    shuttingDown = true;
    locationWatchdog?.cancel();
    locationWatchdog = null;
    await diagnostics.record('worker_stopped');
    locationGeneration++;
    locationRetry?.cancel();
    locationRetry = null;
    await locations?.cancel();
    locations = null;
    await audio.dispose();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await service.stopSelf();
  }
}
