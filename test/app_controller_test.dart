import 'dart:async';

import 'package:almost_there/data/repositories/settings_repository.dart';
import 'package:almost_there/data/services/arrival_monitor.dart';
import 'package:almost_there/data/services/permission_service.dart';
import 'package:almost_there/domain/entities/destination.dart';
import 'package:almost_there/domain/repositories/destination_repository.dart';
import 'package:almost_there/presentation/controllers/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _seoul = Destination(
  id: 'seoul',
  name: '서울역',
  latitude: 37.5547,
  longitude: 126.9706,
);
const _home = Destination(
  id: 'home',
  name: '우리 집',
  latitude: 37.511,
  longitude: 127.001,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryRepository repository;
  late _FakeMonitor monitor;
  late AppController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'theme': 'dark'});
    repository = _MemoryRepository();
    monitor = _FakeMonitor();
    controller = AppController(
      repository: repository,
      settings: SettingsRepository(await SharedPreferences.getInstance()),
      monitor: monitor,
      permissionService: _FakePermissions(),
    );
  });

  tearDown(() => controller.dispose());

  test(
    'cold start reconciles alarms fired by the worker before syncing',
    () async {
      repository.saved = [_seoul.copyWith(enabled: true), _home];
      monitor.fired.add(_seoul.id);

      await controller.initialize();

      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.activeCount, 0);
      expect(repository.saved.first.enabled, isFalse);
      expect(monitor.synced.last.first.enabled, isFalse);
      expect(monitor.rearmed, isEmpty);
    },
  );

  test(
    'failed save preserves the last stored destinations and permits retry',
    () async {
      repository.saved = [_seoul];
      await controller.initialize();
      repository.failNextSave = true;

      await expectLater(
        controller.save(_seoul.copyWith(name: '저장되지 않은 이름')),
        throwsStateError,
      );

      expect(controller.destinations.single.name, '서울역');
      expect(repository.saved.single.name, '서울역');
      expect(controller.busy, isFalse);
      expect(controller.error, isNotNull);

      await controller.save(_seoul.copyWith(name: '출근길 서울역'));
      expect(repository.saved.single.name, '출근길 서울역');
      expect(controller.error, isNull);
    },
  );

  test(
    'overlapping saves are queued without losing the second destination',
    () async {
      await controller.initialize();
      final firstWrite = Completer<void>();
      repository.blockNextSave = firstWrite;
      final first = controller.save(_seoul);
      await _flush();
      final second = controller.save(_home);
      var secondCompleted = false;
      second.then((_) => secondCompleted = true);
      await _flush();

      expect(secondCompleted, isFalse);
      firstWrite.complete();
      await Future.wait([first, second]);

      expect(
        controller.destinations.map((d) => d.id),
        containsAll(['seoul', 'home']),
      );
      expect(repository.saved.map((d) => d.id), containsAll(['seoul', 'home']));
      expect(controller.busy, isFalse);
    },
  );

  test(
    'arrival during a save retains edits and then disables that alarm',
    () async {
      repository.saved = [_seoul.copyWith(enabled: true)];
      await controller.initialize();
      final firstWrite = Completer<void>();
      repository.blockNextSave = firstWrite;
      final save = controller.save(
        _seoul.copyWith(name: '공항철도 서울역', enabled: true),
      );
      await _flush();
      final received = controller.alarmEvents.first.timeout(
        const Duration(seconds: 2),
      );
      monitor.emit(_seoul.copyWith(enabled: true));
      firstWrite.complete();
      await save;
      await received;
      await _flush();

      expect(controller.destinations.single.name, '공항철도 서울역');
      expect(controller.destinations.single.enabled, isFalse);
      expect(repository.saved.single.name, '공항철도 서울역');
      expect(repository.saved.single.enabled, isFalse);
    },
  );

  test(
    'arrival still reaches the alarm screen when storing its record fails',
    () async {
      repository.saved = [_seoul.copyWith(enabled: true)];
      await controller.initialize();
      repository.failNextSave = true;
      final received = controller.alarmEvents.first.timeout(
        const Duration(seconds: 2),
      );

      monitor.emit(_seoul.copyWith(enabled: true));

      expect((await received).id, _seoul.id);
      await _flush();
      expect(controller.error, isNotNull);
    },
  );

  test(
    'failed activation storage does not rearm a previously fired alarm',
    () async {
      repository.saved = [_seoul];
      monitor.fired.add(_seoul.id);
      await controller.initialize();
      repository.failNextSave = true;

      await expectLater(
        controller.setEnabled({_seoul.id}, true),
        throwsStateError,
      );

      expect(controller.destinations.single.enabled, isFalse);
      expect(monitor.fired, contains(_seoul.id));
      expect(monitor.rearmed, isEmpty);
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _MemoryRepository implements DestinationRepository {
  List<Destination> saved = [];
  bool failNextSave = false;
  Completer<void>? blockNextSave;

  @override
  Future<List<Destination>> load() async => List.of(saved);

  @override
  Future<void> saveAll(List<Destination> destinations) async {
    final snapshot = List<Destination>.of(destinations);
    final barrier = blockNextSave;
    blockNextSave = null;
    if (barrier != null) await barrier.future;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('disk write failed');
    }
    saved = snapshot;
  }
}

class _FakePermissions extends PermissionService {
  @override
  bool get supported => true;

  @override
  Future<PermissionSnapshot> inspect() async => const PermissionSnapshot(
    location: true,
    notifications: true,
    overlay: true,
    battery: true,
    fullScreen: true,
    locationServices: true,
  );
}

class _FakeMonitor implements ArrivalMonitor {
  final _arrivals = StreamController<Destination>.broadcast(sync: true);
  final _errors = StreamController<String>.broadcast(sync: true);
  final Set<String> fired = {};
  final List<String> rearmed = [];
  final List<List<Destination>> synced = [];
  Destination? active;

  void emit(Destination destination) {
    fired.add(destination.id);
    active = destination;
    _arrivals.add(destination);
  }

  @override
  Stream<Destination> get arrivals => _arrivals.stream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<Set<String>> firedIds() async => Set.of(fired);
  @override
  Future<Destination?> pendingAlarm() async => active;
  @override
  Future<void> rearm(String id) async {
    rearmed.add(id);
    fired.remove(id);
  }

  @override
  Future<void> sync(List<Destination> destinations) async {
    synced.add(List.of(destinations));
  }

  @override
  Future<void> dismiss(String id) async {
    if (active?.id == id) active = null;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    await _arrivals.close();
    await _errors.close();
  }
}
