import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/alarm_audio_service.dart';
import '../../data/services/alarm_media_service.dart';
import '../../domain/entities/destination.dart';

/// A reusable, app-owned library of user-picked alarm audio files.
class AlarmSoundLibraryScreen extends StatefulWidget {
  const AlarmSoundLibraryScreen({super.key, required this.current});
  final Destination current;

  @override
  State<AlarmSoundLibraryScreen> createState() =>
      _AlarmSoundLibraryScreenState();
}

class _AlarmSoundLibraryScreenState extends State<AlarmSoundLibraryScreen> {
  final _media = AlarmMediaService();
  final _audio = AlarmAudioService();
  final _selected = <String>{};
  List<SavedAlarmMedia> _sounds = [];
  Map<String, Duration?> _durations = const {};
  String? _playing;
  bool _loading = true;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sounds = await _media.savedSounds();
    if (!mounted) return;
    setState(() {
      _sounds = sounds;
      _loading = false;
    });
    final lengths = <String, Duration?>{};
    for (final sound in sounds) {
      lengths[sound.path] = await _media.audioDuration(sound.path);
    }
    if (mounted) setState(() => _durations = lengths);
  }

  Future<void> _add() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final path = await _media.pickAndStoreAudio();
      if (path == null) return;
      await _media.rememberSound(path);
      if (!mounted) return;
      Navigator.pop(
        context,
        widget.current.copyWith(soundId: 'custom', customSoundPath: path),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('알람 소리를 불러오지 못했어요.')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _play(SavedAlarmMedia sound) async {
    if (_playing == sound.path) {
      await _audio.stop();
      if (mounted) setState(() => _playing = null);
      return;
    }
    await _audio.stop();
    try {
      await _audio.preview(
        widget.current.copyWith(soundId: 'custom', customSoundPath: sound.path),
      );
      if (mounted) setState(() => _playing = sound.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('이 파일을 재생하지 못했어요.')));
      }
    }
  }

  Future<void> _delete() async {
    final deleting = _sounds
        .where((sound) => _selected.contains(sound.path))
        .toList();
    await _audio.stop();
    await _media.removeSounds(deleting);
    if (mounted) {
      setState(() {
        _sounds.removeWhere((sound) => _selected.contains(sound.path));
        _selected.clear();
        _playing = null;
      });
    }
  }

  String _durationLabel(Duration? value) {
    if (value == null) return '길이 확인 중';
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selecting = _selected.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(selecting ? '${_selected.length}개 선택됨' : '내 알람 소리'),
        actions: [
          if (selecting)
            IconButton(
              tooltip: '선택 삭제',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _picking ? null : _add,
        icon: _picking
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_rounded),
        label: Text(_picking ? '불러오는 중' : '새 소리 추가'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              children: [
                _sectionLabel('기본 벨소리'),
                _builtInTile('gentle', '포근한 아침', selecting),
                _builtInTile('chime', '맑은 차임', selecting),
                _builtInTile('bell', '작은 종소리', selecting),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Divider(),
                ),
                _sectionLabel('추가한 벨소리'),
                if (_sounds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      '추가한 알람 소리가 없어요.\n아래 버튼으로 음악 파일을 골라 주세요.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ..._sounds.map((sound) => _customTile(sound, selecting)),
              ],
            ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    ),
  );

  Widget _builtInTile(String id, String name, bool selecting) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _soundTile(
      name: name,
      subtitle: '기본 알람',
      playing: _playing == id,
      onPlay: selecting ? null : () => _playBuiltIn(id),
      onTap: selecting
          ? null
          : () => Navigator.pop(
              context,
              widget.current.copyWith(soundId: id, clearCustomSound: true),
            ),
    ),
  );

  Widget _customTile(SavedAlarmMedia sound, bool selecting) {
    final chosen = _selected.contains(sound.path);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _soundTile(
        name: sound.name,
        subtitle: _durationLabel(_durations[sound.path]),
        selected: chosen,
        playing: _playing == sound.path,
        onPlay: selecting ? null : () => _play(sound),
        onLongPress: () => setState(() => _selected.add(sound.path)),
        onTap: () {
          if (selecting) {
            setState(
              () => chosen
                  ? _selected.remove(sound.path)
                  : _selected.add(sound.path),
            );
          } else {
            Navigator.pop(
              context,
              widget.current.copyWith(
                soundId: 'custom',
                customSoundPath: sound.path,
              ),
            );
          }
        },
      ),
    );
  }

  Widget _soundTile({
    required String name,
    required String subtitle,
    required bool playing,
    required VoidCallback? onPlay,
    required VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool selected = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? Colors.white.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? .13
                  : .85,
            )
          : scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        overlayColor: WidgetStatePropertyAll(
          Colors.white.withValues(alpha: .12),
        ),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: ListTile(
            leading: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.notifications_active_outlined,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(subtitle),
            trailing: IconButton(
              tooltip: playing ? '미리듣기 정지' : '미리듣기',
              onPressed: onPlay,
              icon: Icon(
                playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playBuiltIn(String id) async {
    if (_playing == id) {
      await _audio.stop();
      if (mounted) setState(() => _playing = null);
      return;
    }
    await _audio.stop();
    await _audio.preview(
      widget.current.copyWith(soundId: id, clearCustomSound: true),
    );
    if (mounted) setState(() => _playing = id);
  }
}
