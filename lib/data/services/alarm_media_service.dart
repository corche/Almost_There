import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alarm_output/alarm_output.dart';

/// Copies gallery selections into app-owned storage so later alarms do not
/// depend on temporary picker paths or expiring gallery permissions.
class AlarmMediaService {
  static const _backgroundHistoryKey = 'alarm_background_history_v1';
  static const _soundLibraryKey = 'alarm_sound_library_v1';
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickAndStore({required bool video}) async {
    if (kIsWeb ||
        !(Platform.isAndroid ||
            Platform.isIOS ||
            Platform.isMacOS ||
            Platform.isWindows ||
            Platform.isLinux)) {
      throw UnsupportedError('사진과 동영상 배경은 설치된 앱에서 설정할 수 있어요.');
    }
    final selected = video
        ? await _picker.pickVideo(source: ImageSource.gallery)
        : await _picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 2400,
            maxHeight: 2400,
            imageQuality: 92,
          );
    if (selected == null) return null;
    final documents = await getApplicationDocumentsDirectory();
    final mediaDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}alarm_media',
    );
    await mediaDirectory.create(recursive: true);
    final pieces = selected.name.split('.');
    final candidate = pieces.length > 1 ? pieces.last.toLowerCase() : '';
    final extension = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(candidate)
        ? candidate
        : (video ? 'mp4' : 'jpg');
    final path =
        '${mediaDirectory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}.$extension';
    await selected.saveTo(path);
    return path;
  }

  /// Copies a user-picked alarm sound into app-owned storage. The original
  /// download or cloud-provider URI may otherwise disappear before arrival.
  Future<String?> pickAndStoreAudio() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      throw UnsupportedError('나만의 알람 소리는 휴대폰에서 설정할 수 있어요.');
    }
    // The Android plugin uses ACTION_OPEN_DOCUMENT and copies the selected
    // file immediately, so alarms remain available after a reboot.
    return AlarmOutput.pickAudioFile();
  }

  Future<List<SavedAlarmMedia>> recentBackgrounds() =>
      _load(_backgroundHistoryKey, limit: 4);

  Future<void> rememberBackground({required String path, required bool video}) =>
      _remember(
        _backgroundHistoryKey,
        SavedAlarmMedia(path: path, name: _fileName(path), video: video),
        limit: 4,
      );

  Future<List<SavedAlarmMedia>> savedSounds() => _load(_soundLibraryKey);

  Future<void> rememberSound(String path) => _remember(
        _soundLibraryKey,
        SavedAlarmMedia(path: path, name: _fileName(path)),
      );

  /// Removing a library entry never deletes its file: an already-saved
  /// destination may still be using that sound.
  Future<void> removeSounds(Iterable<SavedAlarmMedia> sounds) async {
    final removed = sounds.map((sound) => sound.path).toSet();
    final current = await _load(_soundLibraryKey);
    await _write(_soundLibraryKey, current.where((item) => !removed.contains(item.path)));
  }

  Future<Duration?> audioDuration(String path) async {
    final player = AudioPlayer();
    try {
      return await player.setFilePath(path);
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  String _fileName(String path) => path.split(Platform.pathSeparator).last;

  Future<List<SavedAlarmMedia>> _load(String key, {int? limit}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(key) ?? const [];
    final result = <SavedAlarmMedia>[];
    for (final item in raw) {
      try {
        final saved = SavedAlarmMedia.fromJson(jsonDecode(item) as Map<String, dynamic>);
        if (kIsWeb || await File(saved.path).exists()) result.add(saved);
      } catch (_) {}
    }
    return limit == null ? result : result.take(limit).toList();
  }

  Future<void> _remember(String key, SavedAlarmMedia item, {int? limit}) async {
    final current = await _load(key);
    current.removeWhere((saved) => saved.path == item.path);
    current.insert(0, item);
    await _write(key, limit == null ? current : current.take(limit));
  }

  Future<void> _write(String key, Iterable<SavedAlarmMedia> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, value.map((item) => jsonEncode(item.toJson())).toList());
  }

  /// Only the editor's newly copied files are passed here, never user originals.
  Future<void> removeStaged(String path) async {
    if (kIsWeb) return;
    final documents = await getApplicationDocumentsDirectory();
    final allowed = Directory(
      '${documents.path}${Platform.pathSeparator}alarm_media',
    ).absolute;
    final file = File(path).absolute;
    if (file.parent.path != allowed.path) return;
    if (await file.exists()) await file.delete();
  }
}

class SavedAlarmMedia {
  const SavedAlarmMedia({required this.path, required this.name, this.video = false});
  final String path;
  final String name;
  final bool video;

  Map<String, dynamic> toJson() => {'path': path, 'name': name, 'video': video};
  factory SavedAlarmMedia.fromJson(Map<String, dynamic> json) => SavedAlarmMedia(
    path: json['path'] as String,
    name: json['name'] as String? ?? (json['path'] as String).split(Platform.pathSeparator).last,
    video: json['video'] as bool? ?? false,
  );
}
