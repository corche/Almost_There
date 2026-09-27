import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/destination.dart';
import '../controllers/app_controller.dart';
import '../widgets/journey_illustration.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onEdit,
    required this.onPermissions,
  });
  final void Function(Destination?) onEdit;
  final VoidCallback onPermissions;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Set<String> _selected = {};
  bool _activeOnly = false;
  _DestinationSort _sort = _DestinationSort.added;
  bool _sortingByDistance = false;
  Map<String, double> _distances = const {};
  bool get _selecting => _selected.isNotEmpty;

  Future<void> _batch(bool? enabled) async {
    final app = context.read<AppController>();
    if (enabled == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${_selected.length}개 목적지를 삭제할까요?'),
          content: const Text('저장한 위치와 알람 설정이 함께 삭제됩니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      if (enabled == null) {
        await app.delete(Set.of(_selected));
      } else {
        await app.setEnabled(Set.of(_selected), enabled);
      }
      if (mounted) setState(_selected.clear);
    } catch (_) {
      /* Persistent error banner is supplied by AppController. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final visible = app.destinations
        .where((d) => !_activeOnly || d.enabled)
        .toList();
    _sortDestinations(visible);
    final active = app.destinations.where((d) => d.enabled);
    final recent = active.isNotEmpty
        ? active.first
        : app.destinations.firstOrNull;
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) setState(_selected.clear);
      },
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 130),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/icon.png',
                          width: 38,
                          height: 38,
                          semanticLabel: '다왔어 로고',
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '다왔어',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 6,
                                color:
                                    app.activeCount > 0 &&
                                        app.permissions?.isReady == true
                                    ? const Color(0xFF7A9B5C)
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                app.activeCount > 0
                                    ? '알람 ${app.activeCount}개 켜짐'
                                    : '편안한 이동의 시작',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Text(
                      '마음 놓고, 다녀오세요',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '도착은 우리가 챙길게요.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    _JourneyBanner(destination: recent),
                    const SizedBox(height: 16),
                    if (app.permissions != null && !app.permissions!.isReady)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Material(
                          color: scheme.primary.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: widget.onPermissions,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 21,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '안심하고 도착하려면 권한을 확인해 주세요',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: scheme.onSurface),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (app.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    app.error!,
                                    style: TextStyle(color: scheme.error),
                                  ),
                                ),
                                IconButton(
                                  onPressed: app.clearError,
                                  tooltip: '메시지 닫기',
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '나의 목적지',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          '${app.destinations.length}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                        const Spacer(),
                        if (_selecting)
                          TextButton(
                            onPressed: () => setState(_selected.clear),
                            child: const Text('선택 취소'),
                          )
                        else if (app.destinations.isNotEmpty)
                          Text(
                            '꾹 눌러 여러 개 선택',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (app.destinations.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Row(
                          children: [
                            _FilterChip(
                              label: '전체',
                              count: app.destinations.length,
                              selected: !_activeOnly,
                              onTap: () => setState(() => _activeOnly = false),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: '알람 켜짐',
                              count: app.activeCount,
                              selected: _activeOnly,
                              onTap: () => setState(() => _activeOnly = true),
                            ),
                            const Spacer(),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<_DestinationSort>(
                                value: _sort,
                                borderRadius: BorderRadius.circular(14),
                                icon: const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(Icons.sort_rounded, size: 19),
                                ),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _sort = value);
                                  if (value == _DestinationSort.nextAlarm) {
                                    _loadDistances();
                                  }
                                },
                                items: const [
                                  DropdownMenuItem(
                                    value: _DestinationSort.added,
                                    child: Text('최근 추가한 순'),
                                  ),
                                  DropdownMenuItem(
                                    value: _DestinationSort.nextAlarm,
                                    child: Text('다음에 울릴 순'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_sortingByDistance)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (visible.isEmpty)
                      _EmptyDestinations(
                        filtered: _activeOnly,
                        onAdd: () => widget.onEdit(null),
                      )
                    else
                      ...visible.map(
                        (destination) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _DestinationCard(
                            destination: destination,
                            selecting: _selecting,
                            selected: _selected.contains(destination.id),
                            onTap: () {
                              if (_selecting) {
                                _toggleSelection(destination.id);
                              } else {
                                widget.onEdit(destination);
                              }
                            },
                            onLongPress: () => _toggleSelection(destination.id),
                            onToggle: app.busy
                                ? null
                                : (value) async {
                                    try {
                                      await app.setEnabled({
                                        destination.id,
                                      }, value);
                                    } catch (_) {}
                                  },
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '목적지와 알람 설정은 내 기기에만 저장돼요',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 18,
            child: SafeArea(
              top: false,
              child: _selecting
                  ? Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: scheme.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .1),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${_selected.length}개 선택',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: app.busy ? null : () => _batch(true),
                            tooltip: '선택한 알람 모두 켜기',
                            icon: const Icon(
                              Icons.notifications_active_outlined,
                            ),
                          ),
                          IconButton(
                            onPressed: app.busy ? null : () => _batch(false),
                            tooltip: '선택한 알람 모두 끄기',
                            icon: const Icon(Icons.notifications_off_outlined),
                          ),
                          IconButton(
                            onPressed: app.busy ? null : () => _batch(null),
                            tooltip: '선택한 목적지 삭제',
                            icon: Icon(
                              Icons.delete_outline,
                              color: scheme.error,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () => widget.onEdit(null),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('목적지 추가'),
                        style: FilledButton.styleFrom(
                          elevation: 4,
                          shadowColor: scheme.primary.withValues(alpha: .3),
                          minimumSize: const Size(172, 58),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(String id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });

  void _sortDestinations(List<Destination> values) {
    if (_sort == _DestinationSort.added) {
      values.sort((a, b) => b.id.compareTo(a.id));
      return;
    }
    values.sort((a, b) {
      // Enabled and closest destinations are the most likely next alarms.
      final active = (b.enabled ? 1 : 0).compareTo(a.enabled ? 1 : 0);
      if (active != 0) return active;
      return (_distances[a.id] ?? double.infinity).compareTo(
        _distances[b.id] ?? double.infinity,
      );
    });
  }

  Future<void> _loadDistances() async {
    if (_sortingByDistance) return;
    setState(() => _sortingByDistance = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      final values = <String, double>{
        for (final item in context.read<AppController>().destinations)
          item.id: Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            item.latitude,
            item.longitude,
          ),
      };
      setState(() => _distances = values);
    } catch (_) {
      // Keep a stable added-order fallback if the device location is absent.
    } finally {
      if (mounted) setState(() => _sortingByDistance = false);
    }
  }
}

enum _DestinationSort { added, nextAlarm }

class _JourneyBanner extends StatelessWidget {
  const _JourneyBanner({this.destination});
  final Destination? destination;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hasActiveAlarm = destination?.enabled == true;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF242A20) : const Color(0xFFE6EAD9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 380;
          return Stack(
            children: [
              Positioned(
                right: -7,
                bottom: -4,
                child: Opacity(
                  opacity: compact ? .6 : 1,
                  child: const JourneyIllustration(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFF39412F)
                            : const Color(0xFFD4DDC1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        hasActiveAlarm ? '이번 여정의 도착 알림' : '편안한 이동의 시작',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: dark
                              ? const Color(0xFFCDD5B7)
                              : const Color(0xFF525C3E),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: constraints.maxWidth - (compact ? 80 : 135),
                      child: Text(
                        hasActiveAlarm
                            ? '${destination!.name}에 도착하면\n깨워드릴게요.'
                            : '잠깐 눈을 붙여도,\n괜찮아요.',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontSize: 23, height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      hasActiveAlarm
                          ? '도착 ${destination!.radiusLabel} 전 · ${destination!.alarmLabel} 알림'
                          : '목적지를 설정하면 도착 전에 알려드려요',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.destination,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onToggle,
  });
  final Destination destination;
  final bool selecting, selected;
  final VoidCallback onTap, onLongPress;
  final ValueChanged<bool>? onToggle;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (destination.category) {
      'home' => Icons.home_rounded,
      'work' => Icons.business_center_rounded,
      'station' => Icons.train_rounded,
      _ => Icons.place_rounded,
    };
    return Semantics(
      selected: selected,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        color: destination.enabled
                            ? scheme.primary.withValues(alpha: .1)
                            : scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        selecting
                            ? (selected
                                  ? Icons.check_rounded
                                  : Icons.circle_outlined)
                            : icon,
                        color: destination.enabled || selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            destination.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            destination.address.isEmpty
                                ? '지도에 저장한 위치'
                                : destination.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (!selecting)
                      Semantics(
                        label: '${destination.name} 알람',
                        child: Switch(
                          value: destination.enabled,
                          onChanged: onToggle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 17),
                Divider(color: scheme.outlineVariant.withValues(alpha: .6)),
                const SizedBox(height: 13),
                Row(
                  children: [
                    Icon(
                      Icons.radar_rounded,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${destination.radiusLabel} 전',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      switch (destination.alarmType) {
                        AlarmType.sound => Icons.volume_up_outlined,
                        AlarmType.vibration => Icons.vibration_rounded,
                        AlarmType.earphones => Icons.headphones_rounded,
                      },
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      destination.alarmLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Text(
                      destination.enabled ? '알람 켜짐' : '알람 꺼짐',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: destination.enabled
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text('$label $count'),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    selectedColor: Theme.of(context).colorScheme.onSurface,
    labelStyle: TextStyle(
      color: selected
          ? Theme.of(context).colorScheme.surface
          : Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    side: BorderSide.none,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}

class _EmptyDestinations extends StatelessWidget {
  const _EmptyDestinations({required this.filtered, required this.onAdd});
  final bool filtered;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              filtered
                  ? Icons.notifications_none_rounded
                  : Icons.add_location_alt_outlined,
              size: 30,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            filtered ? '켜진 알람이 없어요' : '어디로 떠나시나요?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            filtered
                ? '목적지의 스위치를 켜면 도착을 알려드려요.'
                : '집, 회사, 자주 가는 역까지.\n목적지를 저장하고 편안하게 이동하세요.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!filtered) ...[
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('첫 목적지 등록하기'),
            ),
          ],
        ],
      ),
    ),
  );
}
