import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// A deliberate, thumb-only dismissal gesture. Screen readers and keyboard
/// users receive an explicit action that does not require a drag gesture.
class AlarmDismissSlider extends StatefulWidget {
  const AlarmDismissSlider({super.key, required this.onDismiss});

  final Future<void> Function() onDismiss;

  @override
  State<AlarmDismissSlider> createState() => _AlarmDismissSliderState();
}

class _AlarmDismissSliderState extends State<AlarmDismissSlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _returnAnimation;
  double _progress = 0;
  double _returnStart = 0;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _returnAnimation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 280),
        )..addListener(() {
          setState(() {
            _progress =
                _returnStart *
                (1 - Curves.easeOutCubic.transform(_returnAnimation.value));
          });
        });
  }

  @override
  void dispose() {
    _returnAnimation.dispose();
    super.dispose();
  }

  void _snapBack() {
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _progress = 0);
      return;
    }
    _returnStart = _progress;
    _returnAnimation.forward(from: 0);
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _returnAnimation.stop();
    setState(() {
      _dismissing = true;
      _progress = 1;
    });
    try {
      await widget.onDismiss();
      // Keep the control locked while the owner completes route removal.
    } catch (_) {
      if (!mounted) return;
      setState(() => _dismissing = false);
      _snapBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '알람 종료',
      hint: '오른쪽으로 밀거나 두 번 탭하여 알람을 종료합니다',
      button: true,
      enabled: !_dismissing,
      onTap: _dismissing ? null : _dismiss,
      child: ExcludeSemantics(
        child: FocusableActionDetector(
          enabled: !_dismissing,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _dismiss();
                return null;
              },
            ),
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              const inset = 7.0;
              const thumbSize = 62.0;
              final travel = (constraints.maxWidth - thumbSize - inset * 2)
                  .clamp(1.0, double.infinity);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Count movement from pointer-down, including the distance
                // travelled before Flutter recognizes the horizontal drag.
                dragStartBehavior: DragStartBehavior.down,
                // On a system overlay it is easy to start a drag slightly
                // outside the thumb. Let the whole track receive it, and
                // leave a tap fallback so the alarm can always be closed.
                onTap: _dismissing ? null : _dismiss,
                onHorizontalDragStart: _dismissing
                    ? null
                    : (_) => _returnAnimation.stop(),
                onHorizontalDragUpdate: _dismissing
                    ? null
                    : (details) => setState(() {
                        _progress =
                            (_progress + details.delta.dx / travel).clamp(0, 1);
                      }),
                onHorizontalDragCancel: _dismissing ? null : _snapBack,
                onHorizontalDragEnd: _dismissing
                    ? null
                    : (_) => _progress >= .85 ? _dismiss() : _snapBack(),
                child: Container(
                  key: const Key('alarm-dismiss-track'),
                  height: thumbSize + inset * 2,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .23),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .18),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        left: thumbSize + 10,
                        right: 18,
                        child: Center(
                          child: Opacity(
                            opacity: (1 - _progress * 1.7).clamp(0, 1),
                            child: Text(
                              '밀어서 알람 종료',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: inset + _progress * travel,
                        top: inset - 1,
                        child: Container(
                          key: const Key('alarm-dismiss-thumb'),
                          width: thumbSize,
                          height: thumbSize,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6900),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x30000000),
                                blurRadius: 14,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: _dismissing
                              ? const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
