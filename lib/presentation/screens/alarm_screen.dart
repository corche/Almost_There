import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/entities/destination.dart';
import '../widgets/alarm_dismiss_slider.dart';
import '../widgets/alarm_media.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({
    super.key,
    required this.destination,
    required this.onDismiss,
    this.preview = false,
  });

  final Destination destination;
  final Future<void> Function() onDismiss;
  final bool preview;

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _gradient;
  late final Timer _clock;
  DateTime _now = DateTime.now();
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _gradient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (now.minute != _now.minute) setState(() => _now = now);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _gradient.stop();
    } else if (!_gradient.isAnimating) {
      _gradient.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _clock.cancel();
    _gradient.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    setState(() => _dismissing = true);
    try {
      await widget.onDismiss();
    } catch (_) {
      if (mounted) {
        setState(() => _dismissing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알람을 종료하지 못했어요. 다시 시도해 주세요.')),
        );
      }
      rethrow;
    }
  }

  Future<void> _dismissFromControl() async {
    try {
      await _dismiss();
    } catch (_) {
      // The error is already displayed; keep the alarm available for retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = widget.destination;
    final colors = destination.gradientColors.length >= 2
        ? destination.gradientColors.map(Color.new).toList()
        : const [Color(0xFF384838), Color(0xFF94744B), Color(0xFFE68A4D)];
    final time =
        '${_now.hour.toString().padLeft(2, '0')}:'
        '${_now.minute.toString().padLeft(2, '0')}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.preview) _dismissFromControl();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1D1D16),
        body: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _gradient,
              builder: (context, child) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1, -1 + _gradient.value * .65),
                    end: Alignment(.5 + _gradient.value * .5, 1),
                    colors: colors,
                    transform: GradientRotation(_gradient.value * .3),
                  ),
                ),
              ),
            ),
            if (destination.background != AlarmBackground.gradient)
              buildAlarmMedia(destination),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x5510110C), Color(0x9910110C)],
                ),
              ),
            ),
            const IgnorePointer(
              child: CustomPaint(painter: _ArrivalContours()),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: math.max(
                                0,
                                constraints.maxHeight - 46,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.near_me_rounded,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 9),
                                    const Expanded(
                                      child: Text(
                                        '다왔어',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (widget.preview)
                                      IconButton(
                                        tooltip: '미리보기 닫기',
                                        onPressed: _dismissing
                                            ? null
                                            : _dismissFromControl,
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          color: Colors.white,
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: .12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                        ),
                                        child: const Text(
                                          '도착 알림',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 32,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 88,
                                        height: 88,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: .12,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: .24,
                                            ),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.notifications_active_rounded,
                                          size: 38,
                                          color: Color(0xFFFFC99E),
                                        ),
                                      ),
                                      const SizedBox(height: 28),
                                      Text(
                                        widget.preview
                                            ? '이렇게 깨워드릴게요'
                                            : '눈 떠요, 거의 다왔어요',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFFE4E3D8),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Semantics(
                                        header: true,
                                        child: Text(
                                          destination.name,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: constraints.maxWidth < 360
                                                ? 44
                                                : 54,
                                            fontWeight: FontWeight.w800,
                                            height: 1.2,
                                            letterSpacing: -1.8,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 15),
                                      Text(
                                        widget.preview
                                            ? '감지 반경 ${destination.radiusLabel}'
                                            : '${destination.radiusLabel} 안에 도착했어요',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFFE4E3D8),
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 28),
                                      Text(
                                        time,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 27,
                                          fontWeight: FontWeight.w300,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AlarmDismissSlider(onDismiss: _dismiss),
                                    const SizedBox(height: 18),
                                    Text(
                                      widget.preview
                                          ? '도착했을 때 만날 화면이에요'
                                          : '내리기 전, 소지품도 챙겨 주세요',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: .7,
                                        ),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrivalContours extends CustomPainter {
  const _ArrivalContours();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .5, size.height * .38);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final scale in [.45, .72, 1.02, 1.34, 1.7]) {
      canvas.drawCircle(center, size.width * scale, paint);
    }
    final dot = Paint()..color = const Color(0xFFEDB27F).withValues(alpha: .5);
    canvas.drawCircle(Offset(size.width * .14, size.height * .27), 3, dot);
    canvas.drawCircle(Offset(size.width * .87, size.height * .55), 2, dot);
  }

  @override
  bool shouldRepaint(_ArrivalContours oldDelegate) => false;
}
