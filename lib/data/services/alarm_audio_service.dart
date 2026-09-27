import 'dart:async';

import 'package:alarm_output/alarm_output.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';

import '../../domain/entities/destination.dart';

class AlarmAudioService {
  AudioPlayer? _previewPlayer;
  Timer? _vibrationTimer;
  int _generation = 0;
  late final String _owner =
      '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
  bool _ownsVibration = false;
  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static const sounds = {
    'gentle': '부드러운 아침',
    'bell': '맑은 종소리',
    'chime': '포근한 차임',
  };

  /// The slider is a listener-facing percentage, not a raw speaker gain.
  /// A squared curve keeps the low end usable: 15% becomes ~2.25% signal
  /// gain, while 100% still reaches the device's app-level maximum.
  double _alarmGain(double setting) {
    final normalized = setting.clamp(0.0, 1.0);
    return normalized * normalized;
  }

  Future<void> start(Destination destination) async {
    await stop();
    final generation = _generation;
    final shouldVibrate =
        destination.alarmType == AlarmType.vibration ||
        destination.vibrateWithSound;
    if (shouldVibrate) await _startVibration(destination, generation);
    if (destination.alarmType == AlarmType.vibration) return;
    final customFile = destination.soundId == 'custom'
        ? destination.customSoundPath
        : null;
    final id = sounds.containsKey(destination.soundId)
        ? destination.soundId
        : 'gentle';
    // Earphone playback has its own native gain and temporary media-volume
    // boost. Keep the user's slider linear there so quiet settings remain
    // audible, while speaker mode retains the gentler squared curve.
    final gain = destination.alarmType == AlarmType.earphones
        ? destination.volume.clamp(0.0, 1.0)
        : _alarmGain(destination.volume);
    if (_mobile) {
      final started = await AlarmOutput.start(
        asset: customFile == null ? 'assets/audio/$id.wav' : null,
        filePath: customFile,
        earphones: destination.alarmType == AlarmType.earphones,
        volume: gain,
        fadeSeconds: destination.fadeInSeconds,
        owner: _owner,
      );
      if (!started) {
        throw StateError('선택한 출력 장치에서 소리를 재생할 수 없습니다.');
      }
      return;
    }
    // Browser/desktop preview cannot enforce an output route. Earphone-only
    // alarms therefore stay silent instead of falling back to a speaker.
    if (destination.alarmType == AlarmType.earphones) return;
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.macOS) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    final player = _previewPlayer ??= AudioPlayer();
    if (customFile != null) {
      await player.setAudioSource(AudioSource.file(customFile));
    } else {
      await player.setAsset('assets/audio/$id.wav');
    }
    if (generation != _generation) return;
    await player.setVolume(gain);
    await player.setLoopMode(LoopMode.one);
    unawaited(player.play());
  }

  Future<void> _startVibration(Destination destination, int generation) async {
    if (!_mobile || !await Vibration.hasVibrator()) return;
    final hasAmplitude = await Vibration.hasAmplitudeControl();
    if (generation != _generation) return;
    _ownsVibration = true;
    Future<void> pulse() async {
      if (generation != _generation || destination.vibrationIntensity == 0) {
        return;
      }
      await Vibration.vibrate(
        duration: 600,
        amplitude: hasAmplitude
            ? (destination.vibrationIntensity * 255).round().clamp(1, 255)
            : -1,
      );
    }

    await pulse();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      unawaited(pulse());
    });
  }

  Future<void> preview(Destination destination) async {
    await start(destination.copyWith(fadeInSeconds: 0));
  }

  Future<void> stop({bool all = false}) async {
    _generation++;
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    if (_mobile) {
      await AlarmOutput.stop(owner: all ? null : _owner);
      if (_ownsVibration || all) await Vibration.cancel();
      _ownsVibration = false;
    }
    await _previewPlayer?.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _previewPlayer?.dispose();
    _previewPlayer = null;
  }
}
