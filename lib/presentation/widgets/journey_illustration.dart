import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A code-native, resolution-independent illustration for the journey banner.
class JourneyIllustration extends StatelessWidget {
  const JourneyIllustration({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '목적지를 향해 달리는 작은 열차',
    image: true,
    child: SizedBox(
      width: 164,
      height: 158,
      child: CustomPaint(painter: _JourneyPainter()),
    ),
  );
}

class _JourneyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 164, size.height / 158);
    final p = Paint();
    canvas.drawCircle(
      const Offset(88, 80),
      62,
      p..color = const Color(0xFFB6BD93).withValues(alpha: .16),
    );
    canvas.drawCircle(
      const Offset(88, 80),
      49,
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFB6BD93).withValues(alpha: .25),
    );
    p.style = PaintingStyle.fill;
    canvas.save();
    canvas.translate(28, 99);
    canvas.rotate(-.16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4, 17, 116, 8),
        const Radius.circular(4),
      ),
      p..color = const Color(0xFF87926A),
    );
    for (var x = 4.0; x < 111; x += 15) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 12, 5, 18),
          const Radius.circular(2),
        ),
        p..color = const Color(0xFF87926A),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, -49, 90, 61),
        const Radius.circular(18),
      ),
      p..color = const Color(0xFFF9F8EB),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(16, -40, 34, 27),
        const Radius.circular(8),
      ),
      p..color = const Color(0xFF81958A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(56, -40, 30, 27),
        const Radius.circular(8),
      ),
      p..color = const Color(0xFFA6B7A5),
    );
    canvas.drawRect(
      const Rect.fromLTWH(6, -4, 90, 8),
      p..color = const Color(0xFFFF6900),
    );
    canvas.drawCircle(
      const Offset(27, 13),
      8,
      p..color = const Color(0xFF353D30),
    );
    canvas.drawCircle(const Offset(76, 13), 8, p);
    canvas.drawCircle(
      const Offset(27, 13),
      3,
      p..color = const Color(0xFFA6B7A5),
    );
    canvas.drawCircle(const Offset(76, 13), 3, p);
    canvas.restore();
    final pin = Path()
      ..moveTo(129, 22)
      ..cubicTo(100, 22, 109, 49, 129, 63)
      ..cubicTo(149, 49, 158, 22, 129, 22);
    canvas.drawPath(pin, p..color = const Color(0xFFFF6900));
    canvas.drawCircle(
      const Offset(129, 37),
      6,
      p..color = const Color(0xFFFFE5CD),
    );
    for (final point in [
      const Offset(29, 42),
      const Offset(149, 106),
      const Offset(16, 81),
    ]) {
      canvas.drawCircle(point, 2.5, p..color = const Color(0xFFB6BD93));
    }
    canvas.drawArc(
      const Rect.fromLTWH(4, 10, 64, 35),
      math.pi / 3,
      1.3,
      false,
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFB6BD93).withValues(alpha: .5),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
