import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../data/services/alarm_audio_service.dart';
import '../../data/services/alarm_media_service.dart';
import '../../data/services/place_search_service.dart';
import '../../domain/entities/destination.dart';
import 'alarm_screen.dart';
import 'alarm_sound_library_screen.dart';

class DestinationEditorScreen extends StatefulWidget {
  const DestinationEditorScreen({super.key, this.destination, this.onSave});
  final Destination? destination;
  final Future<void> Function(Destination)? onSave;

  @override
  State<DestinationEditorScreen> createState() =>
      _DestinationEditorScreenState();
}

class _DestinationEditorScreenState extends State<DestinationEditorScreen> {
  static const _radii = <double>[100, 200, 300, 500, 750, 1000, 1500, 2000];
  static const _presets = <List<int>>[
    [0xFF384838, 0xFF94744B, 0xFFE68A4D],
    [0xFF203548, 0xFF587D97, 0xFFABBDBC],
    [0xFF4B3454, 0xFFAD708A, 0xFFE9C6BA],
    [0xFF162F2C, 0xFF47705C, 0xFFB8C5A0],
  ];
  static const _soundNames = {
    'gentle': '포근한 아침',
    'chime': '맑은 차임',
    'bell': '작은 종소리',
  };
  final _map = MapController();
  final _name = TextEditingController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();
  final _places = PlaceSearchService();
  final _media = AlarmMediaService();
  final _audio = AlarmAudioService();
  final _stagedPaths = <String>[];
  late Destination _draft;
  late String _initialJson;
  List<PlaceResult> _results = [];
  List<PlaceResult> _recentSearches = [];
  List<PlaceResult> _nearbyPlaces = [];
  List<SavedAlarmMedia> _recentBackgrounds = [];
  String? _searchMessage;
  bool _showDiscover = false;
  bool _searching = false;
  bool _locating = false;
  bool _pickingMedia = false;
  bool _pickingSound = false;
  bool _previewing = false;
  bool _leaving = false;
  bool _guardOpen = false;
  bool _saving = false;

  bool get _editing => widget.destination != null;
  bool get _dirty => jsonEncode(_value.toJson()) != _initialJson;
  Destination get _value => _draft.copyWith(name: _name.text.trim());
  LatLng get _point => LatLng(_draft.latitude, _draft.longitude);
  ColorScheme get _colors => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    _draft =
        widget.destination ??
        Destination(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: '',
          latitude: 37.5547,
          longitude: 126.9707,
          address: '서울역 · 지도에서 목적지를 선택해 주세요',
          enabled: true,
        );
    _name.text = _draft.name;
    _initialJson = jsonEncode(_value.toJson());
    _name.addListener(_rebuild);
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus && _search.text.trim().isEmpty) {
        setState(() => _showDiscover = true);
        _loadDiscovery();
      }
    });
    unawaited(_hydrateBackgroundHistory());
    if (!_editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initialLocation());
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _audio.dispose();
    _map.dispose();
    _name.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _update(Destination value) => setState(() => _draft = value);

  Future<void> _loadRecentBackgrounds() async {
    final items = await _media.recentBackgrounds();
    if (mounted) setState(() => _recentBackgrounds = items);
  }

  Future<void> _hydrateBackgroundHistory() async {
    final path = _draft.mediaPath;
    if (path != null && _draft.background != AlarmBackground.gradient) {
      await _media.rememberBackground(
        path: path,
        video: _draft.background == AlarmBackground.video,
      );
    }
    await _loadRecentBackgrounds();
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _findPlace() async {
    if (_searching) return;
    if (_search.text.trim().isEmpty) {
      FocusScope.of(context).unfocus();
      setState(() => _showDiscover = true);
      await _loadDiscovery();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchMessage = null;
      _results = [];
      _showDiscover = false;
    });
    try {
      final results = await _places.search(_search.text);
      if (!mounted) return;
      setState(() {
        _results = results;
        if (results.isEmpty) _searchMessage = '검색 결과가 없어요. 다른 장소 이름으로 찾아보세요.';
      });
    } on PlaceSearchException catch (error) {
      if (mounted) setState(() => _searchMessage = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectPlace(PlaceResult place) {
    _map.move(LatLng(place.latitude, place.longitude), 16);
    setState(() {
      _draft = _draft.copyWith(
        latitude: place.latitude,
        longitude: place.longitude,
        address: place.address,
      );
      if (_name.text.trim().isEmpty) _name.text = place.name;
      _search.text = place.name;
      _results = [];
      _searchMessage = null;
      _showDiscover = false;
    });
    unawaited(_places.remember(place));
  }

  Future<void> _loadDiscovery() async {
    final recent = await _places.recentSearches();
    if (!mounted) return;
    setState(() {
      _recentSearches = recent;
      _nearbyPlaces = _nearbyFromRecent(recent);
    });
    if (_nearbyPlaces.isNotEmpty) return;
    try {
      final highlights = await _places.nearbyHighlights(
        latitude: _draft.latitude,
        longitude: _draft.longitude,
      );
      if (mounted) setState(() => _nearbyPlaces = highlights.take(4).toList());
    } catch (_) {
      // Search history remains useful while the network is unavailable.
    }
  }

  List<PlaceResult> _nearbyFromRecent(List<PlaceResult> places) {
    final candidates = List<PlaceResult>.of(places)
      ..sort(
        (a, b) =>
            Geolocator.distanceBetween(
              _draft.latitude,
              _draft.longitude,
              a.latitude,
              a.longitude,
            ).compareTo(
              Geolocator.distanceBetween(
                _draft.latitude,
                _draft.longitude,
                b.latitude,
                b.longitude,
              ),
            ),
      );
    return candidates.take(4).toList();
  }

  Future<void> _initialLocation() async {
    if (_editing || !await Geolocator.isLocationServiceEnabled()) return;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      _map.move(point, 16);
      setState(() {
        _draft = _draft.copyWith(
          latitude: point.latitude,
          longitude: point.longitude,
          address: '현재 위치 근처 · 지도에서 목적지를 조정해 주세요',
        );
        _nearbyPlaces = _nearbyFromRecent(_recentSearches);
      });
    } catch (_) {
      // 서울역 기본 중심은 위치를 얻을 수 없는 경우의 안전한 대체값이다.
    }
  }

  Future<void> _myLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _notify('기기의 위치 서비스를 켜 주세요.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _notify('현재 위치를 보려면 위치 권한을 허용해 주세요.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      _map.move(LatLng(position.latitude, position.longitude), 16);
      _update(
        _draft.copyWith(
          latitude: position.latitude,
          longitude: position.longitude,
          address: '현재 위치',
        ),
      );
    } catch (_) {
      _notify('현재 위치를 가져오지 못했어요. 지도에서 직접 선택해 주세요.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _preview() async {
    if (_previewing) {
      await _audio.stop();
      if (mounted) setState(() => _previewing = false);
      return;
    }
    try {
      await _audio.preview(_value);
      if (!mounted) return;
      setState(() => _previewing = true);
    } catch (_) {
      _notify('미리듣기를 시작하지 못했어요. 오디오 연결을 확인해 주세요.');
    }
  }

  Future<void> _previewAlarmScreen() async {
    if (_previewing) return;
    final destination = _value;
    try {
      await _audio.start(destination);
    } catch (_) {
      _notify('알람 소리를 시작하지 못했어요. 기기 음량을 확인해 주세요.');
    }
    if (!mounted) return;
    late MaterialPageRoute<void> route;
    route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AlarmScreen(
        destination: destination,
        preview: true,
        onDismiss: () async {
          await _audio.stop();
          if (mounted && route.isCurrent) Navigator.of(context).pop();
        },
      ),
    );
    await Navigator.of(context).push(route);
    await _audio.stop();
  }

  Future<void> _pickMedia(bool video) async {
    setState(() => _pickingMedia = true);
    try {
      final path = await _media.pickAndStore(video: video);
      if (path == null) return;
      if (!mounted) {
        await _media.removeStaged(path);
        return;
      }
      _stagedPaths.add(path);
      await _media.rememberBackground(path: path, video: video);
      await _loadRecentBackgrounds();
      _update(
        _draft.copyWith(
          background: video ? AlarmBackground.video : AlarmBackground.image,
          mediaPath: path,
        ),
      );
    } on UnsupportedError catch (error) {
      _notify(error.message ?? '이 기기에서는 미디어를 선택할 수 없어요.');
    } catch (_) {
      _notify('사진이나 동영상을 불러오지 못했어요. 갤러리 접근 권한을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _pickingMedia = false);
    }
  }

  Future<void> _pickAlarmSound() async {
    if (_pickingSound) return;
    setState(() => _pickingSound = true);
    try {
      final path = await _media.pickAndStoreAudio();
      if (path == null) return;
      if (!mounted) {
        await _media.removeStaged(path);
        return;
      }
      _stagedPaths.add(path);
      await _media.rememberSound(path);
      _update(_draft.copyWith(soundId: 'custom', customSoundPath: path));
    } on UnsupportedError catch (error) {
      _notify(error.message ?? '이 기기에서는 알람 소리를 선택할 수 없어요.');
    } catch (_) {
      _notify('알람 소리를 불러오지 못했어요. 다른 오디오 파일을 선택해 주세요.');
    } finally {
      if (mounted) setState(() => _pickingSound = false);
    }
  }

  Future<void> _openSoundLibrary() async {
    await _audio.stop();
    if (mounted) setState(() => _previewing = false);
    final selected = await Navigator.of(context).push<Destination>(
      MaterialPageRoute(
        builder: (_) => AlarmSoundLibraryScreen(current: _value),
      ),
    );
    if (selected != null && mounted) _update(selected);
  }

  void _useRecentBackground(SavedAlarmMedia media) {
    _update(
      _draft.copyWith(
        background: media.video ? AlarmBackground.video : AlarmBackground.image,
        mediaPath: media.path,
      ),
    );
  }

  Future<void> _cleanup({Set<String> keep = const {}}) async {
    for (final path in _stagedPaths.where((path) => !keep.contains(path))) {
      try {
        await _media.removeStaged(path);
      } catch (_) {
        /* Retry can be handled by app cache maintenance. */
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _pickingMedia || _pickingSound) return;
    if (!_formKey.currentState!.validate()) {
      _notify('목적지 이름을 입력해 주세요.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _audio.stop();
      final value = _value.background == AlarmBackground.gradient
          ? _value.copyWith(clearMedia: true)
          : _value;
      // Keep the complete draft and staged media until persistence succeeds.
      await widget.onSave?.call(value);
      await _cleanup(
        keep: {
          if (value.mediaPath != null) value.mediaPath!,
          if (value.customSoundPath != null) value.customSoundPath!,
        },
      );
      if (!mounted) return;
      setState(() => _leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(value);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _notify('저장하지 못했어요. 입력한 내용은 그대로 있으니 다시 시도해 주세요.');
    }
  }

  Future<void> _leave() async {
    if (_guardOpen || _saving || _pickingMedia || _pickingSound) return;
    if (_dirty) {
      _guardOpen = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('저장하지 않고 나갈까요?'),
          content: const Text('입력한 내용이 저장되지 않습니다. 나가시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('저장 안함'),
            ),
          ],
        ),
      );
      _guardOpen = false;
      if (discard != true || !mounted) return;
    }
    await _audio.stop();
    await _cleanup();
    if (!mounted) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _customColors() async {
    final before = List<int>.of(_draft.gradientColors);
    final selected = await showDialog<List<int>>(
      context: context,
      builder: (context) => _GradientPicker(
        colors: before,
        onChanged: (colors) => _update(
          _draft.copyWith(
            background: AlarmBackground.gradient,
            gradientColors: colors,
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      _update(
        _draft.copyWith(
          background: AlarmBackground.gradient,
          gradientColors: selected,
        ),
      );
    } else if (mounted) {
      _update(_draft.copyWith(gradientColors: before));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Destination>(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 74,
          leading: TextButton(onPressed: _leave, child: const Text('취소')),
          title: Text(_editing ? '목적지 수정' : '새 목적지'),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton(
                onPressed: _saving || _pickingMedia || _pickingSound
                    ? null
                    : _save,
                child: const Text(
                  '저장',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                    children: [
                      _intro(),
                      const SizedBox(height: 24),
                      _mapSection(),
                      const SizedBox(height: 24),
                      _destinationCard(),
                      const SizedBox(height: 20),
                      _alarmCard(),
                      const SizedBox(height: 20),
                      _backgroundCard(),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: _saving || _pickingMedia || _pickingSound
                            ? null
                            : _save,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(
                          _editing ? '변경사항 저장' : '이 목적지로 알람 설정',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '설정한 반경에 들어오면 도착을 알려드려요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: _colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _intro() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _editing ? '조금 더 내게 맞게' : '어디에서 깨워드릴까요?',
        style: const TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        '목적지를 고르고, 편안하게 이동하세요.',
        style: TextStyle(color: _colors.onSurfaceVariant, fontSize: 14),
      ),
    ],
  );

  Widget _searchDiscovery() {
    if (_recentSearches.isEmpty && _nearbyPlaces.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: _card(
          child: Row(
            children: [
              Icon(Icons.history_rounded, color: _colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '검색한 장소가 여기에 쌓여요.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _card(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_nearbyPlaces.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 15, 16, 5),
                child: Text(
                  '현재 위치 주변',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
              ..._nearbyPlaces.map(
                (place) =>
                    _discoverPlaceTile(place, icon: Icons.near_me_outlined),
              ),
            ],
            if (_recentSearches.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 5),
                child: Text(
                  '최근 검색',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _colors.onSurface,
                  ),
                ),
              ),
              ..._recentSearches
                  .take(6)
                  .map(
                    (place) =>
                        _discoverPlaceTile(place, icon: Icons.history_rounded),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _discoverPlaceTile(PlaceResult place, {required IconData icon}) =>
      ListTile(
        dense: true,
        leading: Icon(icon, size: 20, color: _colors.onSurfaceVariant),
        title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          place.address,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _selectPlace(place),
      );

  Widget _mapSection() => Column(
    children: [
      TextField(
        controller: _search,
        focusNode: _searchFocus,
        maxLength: 120,
        textInputAction: TextInputAction.search,
        onChanged: (value) {
          if (value.trim().isEmpty) {
            setState(() => _showDiscover = true);
            _loadDiscovery();
          }
        },
        onSubmitted: (_) => _findPlace(),
        decoration: InputDecoration(
          hintText: '장소, 역 이름으로 검색',
          counterText: '',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: '장소 검색',
                  onPressed: _findPlace,
                  icon: Icon(
                    Icons.arrow_forward_rounded,
                    color: _colors.primary,
                  ),
                ),
        ),
      ),
      if (_showDiscover && _results.isEmpty) _searchDiscovery(),
      if (_searchMessage != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Text(
            _searchMessage!,
            style: TextStyle(color: _colors.onSurfaceVariant, fontSize: 13),
          ),
        ),
      if (_results.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: _card(
            padding: EdgeInsets.zero,
            child: Column(
              children: _results
                  .map(
                    (place) => Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: Icon(
                          Icons.location_on_outlined,
                          color: _colors.primary,
                        ),
                        title: Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          place.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectPlace(place),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 278,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: _point,
                  initialZoom: 15,
                  minZoom: 3,
                  maxZoom: 18,
                  onTap: (_, point) => _update(
                    _draft.copyWith(
                      latitude: point.latitude,
                      longitude: point.longitude,
                      address: '지도에서 선택한 위치',
                    ),
                  ),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.almostthere.almost_there',
                    // Loads the next zoom's raster tiles on high-density
                    // screens rather than stretching 256px images.
                    retinaMode: true,
                    maxZoom: 19,
                    tileBuilder: Theme.of(context).brightness == Brightness.dark
                        ? darkModeTileBuilder
                        : null,
                  ),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _point,
                        radius: _draft.radius,
                        useRadiusInMeter: true,
                        color: _colors.primary.withValues(alpha: .12),
                        borderColor: _colors.primary.withValues(alpha: .6),
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _point,
                        width: 60,
                        height: 68,
                        alignment: Alignment.topCenter,
                        child: Column(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: _colors.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .2),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.notifications_active_rounded,
                                color: Colors.white,
                                size: 23,
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              color: _colors.primary,
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        'OpenStreetMap contributors',
                        onTap: () => launchUrl(
                          Uri.parse('https://www.openstreetmap.org/copyright'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                top: 12,
                left: 12,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _colors.surface.withValues(alpha: .95),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app_outlined, size: 15),
                        SizedBox(width: 5),
                        Text(
                          '지도를 눌러 위치 선택',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 38,
                child: Material(
                  color: _colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  elevation: 2,
                  child: IconButton(
                    tooltip: '현재 위치로 설정',
                    onPressed: _locating ? null : _myLocation,
                    icon: _locating
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on_rounded, size: 16, color: _colors.primary),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                _draft.address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: _colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _destinationCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          Icons.location_on_outlined,
          '목적지 설정',
          '매번 찾기 쉽도록 별명을 붙여주세요',
        ),
        const SizedBox(height: 20),
        _fieldLabel('목적지 이름'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _name,
          maxLength: 30,
          decoration: const InputDecoration(hintText: '예: 우리 집, 서울역'),
          validator: (value) =>
              value == null || value.trim().isEmpty ? '목적지 이름을 입력해 주세요.' : null,
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            const Expanded(
              child: Text(
                '도착 감지 반경',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _valueBadge(_draft.radiusLabel),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context)
              .copyWith(showValueIndicator: ShowValueIndicator.onlyForDiscrete),
          child: Slider(
            value: _nearestRadiusIndex().toDouble(),
            max: (_radii.length - 1).toDouble(),
            divisions: _radii.length - 1,
            label: _draft.radiusLabel,
            onChanged: (value) =>
                _update(_draft.copyWith(radius: _radii[value.round()])),
          ),
        ),
        _sliderEnds('100m · 도착 직전', '2km · 여유 있게'),
        const SizedBox(height: 14),
        _hint(Icons.info_outline_rounded, '넓은 반경을 설정하면 하차를 준비할 시간이 생겨요.'),
      ],
    ),
  );

  int _nearestRadiusIndex() {
    var closest = 0;
    for (var i = 1; i < _radii.length; i++) {
      if ((_radii[i] - _draft.radius).abs() <
          (_radii[closest] - _draft.radius).abs()) {
        closest = i;
      }
    }
    return closest;
  }

  Widget _alarmCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          Icons.notifications_none_rounded,
          '나만의 알람',
          '어떤 방식으로 알려드릴까요?',
        ),
        const SizedBox(height: 20),
        Row(
          children: AlarmType.values
              .map(
                (type) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: type == AlarmType.earphones ? 0 : 8,
                    ),
                    child: _typeTile(type),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        _hint(Icons.info_outline_rounded, switch (_draft.alarmType) {
          AlarmType.sound => '이어폰을 연결해도 기기 스피커로 알람을 울려요.',
          AlarmType.vibration => '소리 없이 진동으로 도착을 알려드려요.',
          AlarmType.earphones => '이어폰이 연결되어 있을 때만 소리가 나요.',
        }),
        const SizedBox(height: 20),
        Divider(color: _colors.outlineVariant.withValues(alpha: .4), height: 1),
        const SizedBox(height: 20),
        if (_draft.alarmType != AlarmType.vibration) ...[
          _fieldLabel('알람 소리'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openSoundLibrary,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    alignment: Alignment.centerLeft,
                  ),
                  icon: const Icon(Icons.library_music_rounded),
                  label: Text(
                    _draft.soundId == 'custom' && _draft.customSoundPath != null
                        ? _draft.customSoundPath!
                              .split(Platform.pathSeparator)
                              .last
                        : _soundNames[_draft.soundId] ?? '포근한 아침',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                height: 56,
                child: IconButton.filledTonal(
                  tooltip: _previewing ? '미리듣기 정지' : '알람 소리 미리듣기',
                  onPressed: _preview,
                  icon: Icon(
                    _previewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '탭하면 추가했던 음악을 듣고 선택하거나 새 파일을 추가할 수 있어요.',
            style: TextStyle(fontSize: 12, color: _colors.onSurfaceVariant),
          ),
          const SizedBox(height: 23),
          _levelSlider(
            '소리 크기',
            Icons.volume_up_outlined,
            _draft.volume,
            (value) => _update(_draft.copyWith(volume: value)),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '소리와 함께 진동',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '소리가 울릴 때 기기도 함께 진동해요.',
                style: TextStyle(fontSize: 11),
              ),
              value: _draft.vibrateWithSound,
              onChanged: (value) =>
                  _update(_draft.copyWith(vibrateWithSound: value)),
            ),
          ),
          if (_draft.vibrateWithSound) ...[
            const SizedBox(height: 10),
            _levelSlider(
              '진동 세기',
              Icons.vibration_rounded,
              _draft.vibrationIntensity,
              (value) => _update(_draft.copyWith(vibrationIntensity: value)),
            ),
          ],
          const SizedBox(height: 17),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '서서히 커지는 알람',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              _valueBadge('${_draft.fadeInSeconds}초'),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '작은 소리로 시작해 편안하게 깨워드려요.',
            style: TextStyle(color: _colors.onSurfaceVariant, fontSize: 12),
          ),
          Slider(
            value: _draft.fadeInSeconds.toDouble(),
            min: 3,
            max: 120,
            divisions: 117,
            label: '${_draft.fadeInSeconds}초',
            onChanged: (value) =>
                _update(_draft.copyWith(fadeInSeconds: value.round())),
          ),
          _sliderEnds('3초', '2분'),
        ] else ...[
          _levelSlider(
            '진동 세기',
            Icons.vibration_rounded,
            _draft.vibrationIntensity,
            (value) => _update(_draft.copyWith(vibrationIntensity: value)),
          ),
          const SizedBox(height: 8),
          Text(
            '기기가 지원하는 범위에서 진동 세기를 적용해요.',
            style: TextStyle(fontSize: 12, color: _colors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _preview,
            icon: Icon(
              _previewing ? Icons.stop_rounded : Icons.vibration_rounded,
              size: 18,
            ),
            label: Text(_previewing ? '진동 멈추기' : '진동 미리 체험'),
          ),
        ],
      ],
    ),
  );

  Widget _typeTile(AlarmType type) {
    final selected = _draft.alarmType == type;
    final icon = switch (type) {
      AlarmType.sound => Icons.volume_up_rounded,
      AlarmType.vibration => Icons.vibration_rounded,
      AlarmType.earphones => Icons.headphones_rounded,
    };
    final label = switch (type) {
      AlarmType.sound => '소리',
      AlarmType.vibration => '진동',
      AlarmType.earphones => '이어폰',
    };
    return Semantics(
      selected: selected,
      button: true,
      label: '$label 알람',
      child: Material(
        color: selected
            ? _colors.primary.withValues(alpha: .12)
            : _colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            unawaited(_audio.stop());
            setState(() {
              _previewing = false;
              _draft = _draft.copyWith(alarmType: type);
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 17),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? _colors.primary : Colors.transparent,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  color: selected ? _colors.primary : _colors.onSurfaceVariant,
                  size: 25,
                ),
                const SizedBox(height: 9),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? _colors.primary
                        : _colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _backgroundCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(Icons.palette_outlined, '알람 배경', '도착의 순간도 내 취향대로'),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 156,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _draft.gradientColors.map(Color.new).toList(),
                    ),
                  ),
                ),
                if (_draft.background == AlarmBackground.image &&
                    _draft.mediaPath != null &&
                    !kIsWeb)
                  Image.file(
                    File(_draft.mediaPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                if (_draft.background == AlarmBackground.video)
                  const Center(
                    child: Icon(
                      Icons.play_circle_outline_rounded,
                      color: Colors.white70,
                      size: 72,
                    ),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x55000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name.text.trim().isEmpty
                            ? '다왔어요'
                            : '${_name.text.trim()}에 다왔어요',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _draft.background == AlarmBackground.video
                            ? '선택한 동영상을 알람 화면에서 재생해요'
                            : '잠시 후, 기분 좋은 도착',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 17),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('그라데이션'),
              selected: _draft.background == AlarmBackground.gradient,
              onSelected: (_) => _update(
                _draft.copyWith(background: AlarmBackground.gradient),
              ),
            ),
            ChoiceChip(
              label: const Text('사진 · 동영상'),
              selected: _draft.background != AlarmBackground.gradient,
              onSelected: (_) =>
                  _update(_draft.copyWith(background: AlarmBackground.image)),
            ),
          ],
        ),
        if (_draft.background == AlarmBackground.gradient) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              ..._presets.map(
                (preset) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Semantics(
                      button: true,
                      label: '그라데이션 프리셋 ${_presets.indexOf(preset) + 1}',
                      selected: listEquals(preset, _draft.gradientColors),
                      child: InkWell(
                        onTap: () => _update(
                          _draft.copyWith(gradientColors: List.of(preset)),
                        ),
                        borderRadius: BorderRadius.circular(13),
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            gradient: LinearGradient(
                              colors: preset.map(Color.new).toList(),
                            ),
                            border: Border.all(
                              color: listEquals(preset, _draft.gradientColors)
                                  ? _colors.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: listEquals(preset, _draft.gradientColors)
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 21,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton.outlined(
                tooltip: '그라데이션 색상 직접 선택',
                onPressed: _customColors,
                icon: const Icon(Icons.colorize_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '부드럽게 움직이는 그라데이션으로 표시돼요.',
            style: TextStyle(fontSize: 12, color: _colors.onSurfaceVariant),
          ),
        ] else ...[
          const SizedBox(height: 16),
          Text(
            '최근 선택한 배경',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 82,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._recentBackgrounds.map(_recentBackgroundTile),
                _addBackgroundTile(),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Divider(color: _colors.outlineVariant.withValues(alpha: .4), height: 1),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _previewing ? null : _previewAlarmScreen,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          icon: const Icon(Icons.slideshow_rounded, size: 19),
          label: const Text('알람 화면 미리보기'),
        ),
      ],
    ),
  );

  Widget _recentBackgroundTile(SavedAlarmMedia media) {
    final selected =
        _draft.mediaPath == media.path &&
        _draft.background != AlarmBackground.gradient;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${media.video ? '동영상' : '사진'} 배경 ${media.name}',
        child: InkWell(
          onTap: () => _useRecentBackground(media),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 82,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _colors.primary : _colors.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!media.video && !kIsWeb)
                    Image.file(
                      File(media.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Color(0xFF2B2B22)),
                    )
                  else if (media.video && !kIsWeb)
                    _VideoThumbnail(path: media.path)
                  else
                    const ColoredBox(color: Color(0xFF2B2B22)),
                  if (media.video)
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  if (selected)
                    const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: CircleAvatar(
                          radius: 11,
                          child: Icon(Icons.check_rounded, size: 14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _addBackgroundTile() => Semantics(
    button: true,
    label: '다른 배경 선택',
    child: InkWell(
      onTap: _pickingMedia ? null : _showMediaOptions,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 82,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: _colors.surfaceContainerHighest,
          border: Border.all(color: _colors.outlineVariant),
        ),
        child: _pickingMedia
            ? const Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined),
                  SizedBox(height: 4),
                  Text('다른 배경', style: TextStyle(fontSize: 11)),
                ],
              ),
      ),
    ),
  );

  Future<void> _showMediaOptions() async {
    if (_pickingMedia) return;
    final video = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '어떤 배경으로 꾸밀까요?',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: const Text('갤러리에서 사진 선택'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, false),
              ),
              ListTile(
                leading: const Icon(Icons.movie_outlined),
                title: const Text('갤러리에서 동영상 선택'),
                subtitle: const Text('동영상 소리는 알람과 함께 재생되지 않아요.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (video != null && mounted) await _pickMedia(video);
  }

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
  }) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: _colors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _colors.outlineVariant.withValues(alpha: .35)),
    ),
    child: child,
  );

  Widget _sectionHeading(IconData icon, String title, String subtitle) => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _colors.primary.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: _colors.primary, size: 22),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: _colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _fieldLabel(String text) => Text(
    text,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
  );

  Widget _valueBadge(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: _colors.primary.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      value,
      style: TextStyle(
        color: _colors.primary,
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
    ),
  );

  Widget _sliderEnds(String left, String right) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            left,
            style: TextStyle(fontSize: 11, color: _colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            right,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 11, color: _colors.onSurfaceVariant),
          ),
        ),
      ],
    ),
  );

  Widget _hint(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: _colors.onSurfaceVariant),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: _colors.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );

  Widget _levelSlider(
    String title,
    IconData icon,
    double value,
    ValueChanged<double> onChanged, {
    bool enabled = true,
    String? disabledLabel,
  }) => Opacity(
    opacity: enabled ? 1 : .48,
    child: Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: _colors.onSurfaceVariant),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _valueBadge(disabledLabel ?? '${(value * 100).round()}%'),
          ],
        ),
        Slider(
          value: value,
          divisions: 20,
          label: '${(value * 100).round()}%',
          onChanged: enabled ? onChanged : null,
        ),
        _sliderEnds('조용하게', '확실하게'),
      ],
    ),
  );
}

class _VideoThumbnail extends StatefulWidget {
  const _VideoThumbnail({required this.path});
  final String path;

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller = VideoPlayerController.file(File(widget.path));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.pause();
      await controller.seekTo(Duration.zero);
      if (mounted && _controller == controller) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Color(0xFF2B2B22));
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _GradientPicker extends StatefulWidget {
  const _GradientPicker({required this.colors, required this.onChanged});
  final List<int> colors;
  final ValueChanged<List<int>> onChanged;

  @override
  State<_GradientPicker> createState() => _GradientPickerState();
}

class _GradientPickerState extends State<_GradientPicker> {
  late final List<Color> _colors;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _colors = widget.colors.map(Color.new).toList();
  }

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(_colors[_selected]);
    return AlertDialog(
      title: const Text('나만의 그라데이션'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(colors: _colors),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _colors.length,
                  (index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Semantics(
                      button: true,
                      label: '${index + 1}번째 색상',
                      selected: _selected == index,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => setState(() => _selected = index),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _colors[index],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selected == index
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: _selected == index
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _colorSlider(
                '색상',
                hsv.hue / 360,
                (value) => hsv.withHue(value * 360),
              ),
              _colorSlider(
                '채도',
                hsv.saturation,
                (value) => hsv.withSaturation(value),
              ),
              _colorSlider('밝기', hsv.value, (value) => hsv.withValue(value)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _colors.map((color) => color.toARGB32()).toList(),
          ),
          child: const Text('이 색상으로 적용'),
        ),
      ],
    );
  }

  Widget _colorSlider(
    String label,
    double value,
    HSVColor Function(double) update,
  ) => Row(
    children: [
      SizedBox(
        width: 32,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
      Expanded(
        child: Slider(
          value: value,
          onChanged: (value) {
            setState(() => _colors[_selected] = update(value).toColor());
            widget.onChanged(_colors.map((color) => color.toARGB32()).toList());
          },
        ),
      ),
    ],
  );
}
