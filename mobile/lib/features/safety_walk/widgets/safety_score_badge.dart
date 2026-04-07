import 'dart:math';
import 'package:flutter/material.dart';

/// Animated safety score badge with progress ring and glow effect.
/// Colors: green (80-100), yellow (60-79), red (0-59)
class SafetyScoreBadge extends StatelessWidget {
  final double score;
  final double size;
  final bool showLabel;

  const SafetyScoreBadge({
    super.key,
    required this.score,
    this.size = 36,
    this.showLabel = false,
  });

  Color get _scoreColor {
    if (score >= 80) return const Color(0xFF00C853);
    if (score >= 60) return const Color(0xFFFFC107);
    return const Color(0xFFE63946);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background ring
              SizedBox(
                width: size,
                height: size,
                child: CustomPaint(
                  painter: _RingPainter(
                    progress: score / 100,
                    color: _scoreColor,
                    strokeWidth: size * 0.08,
                    backgroundColor: _scoreColor.withValues(alpha: 0.12),
                  ),
                ),
              ),
              // Score text
              Text(
                score.toStringAsFixed(0),
                style: TextStyle(
                  color: _scoreColor,
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 4),
          Text(
            'Safety Score',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final Color backgroundColor;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background ring
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress ring
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );

    // Glow dot at the end
    if (progress > 0.05) {
      final dotAngle = -pi / 2 + sweepAngle;
      final dotX = center.dx + radius * cos(dotAngle);
      final dotY = center.dy + radius * sin(dotAngle);

      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawCircle(
        Offset(dotX, dotY),
        strokeWidth * 0.8,
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
