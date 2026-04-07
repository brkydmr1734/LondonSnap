import 'package:flutter/material.dart';

/// GTA5-inspired map pin marker.
/// Draws a 3D-looking glossy pin with a category icon inside,
/// glowing drop shadow, and a sharp pointer at the bottom.
class Gta5PinPainter extends CustomPainter {
  final Color color;
  final IconData icon;

  Gta5PinPainter({required this.color, required this.icon});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // ── Pin body dimensions ──
    final pinTop = h * 0.04;
    final pinBodyH = h * 0.62;
    final pinR = w * 0.38;
    final pointerTip = h * 0.92;

    // ── Drop shadow (glow) ──
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(cx, pinTop + pinBodyH / 2), pinR + 4, glowPaint);

    // ── Pin pointer (triangle) ──
    final pointerPath = Path()
      ..moveTo(cx - pinR * 0.42, pinTop + pinBodyH * 0.78)
      ..lineTo(cx, pointerTip)
      ..lineTo(cx + pinR * 0.42, pinTop + pinBodyH * 0.78)
      ..close();
    canvas.drawPath(
      pointerPath,
      Paint()..color = _darken(color, 0.2),
    );

    // ── Pin body circle ──
    final center = Offset(cx, pinTop + pinBodyH / 2);
    // Outer dark ring
    canvas.drawCircle(
      center,
      pinR + 2,
      Paint()..color = _darken(color, 0.35),
    );
    // Main fill with gradient
    final bodyGrad = RadialGradient(
      center: const Alignment(-0.3, -0.4),
      radius: 1.0,
      colors: [
        _lighten(color, 0.15),
        color,
        _darken(color, 0.18),
      ],
      stops: const [0.0, 0.55, 1.0],
    );
    canvas.drawCircle(
      center,
      pinR,
      Paint()..shader = bodyGrad.createShader(
        Rect.fromCircle(center: center, radius: pinR),
      ),
    );

    // ── Inner white disc (icon background) ──
    final innerR = pinR * 0.62;
    canvas.drawCircle(
      center,
      innerR,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    // ── Glossy highlight on top ──
    final hlRect = Rect.fromLTWH(
      cx - pinR * 0.55,
      pinTop + pinBodyH * 0.08,
      pinR * 1.1,
      pinBodyH * 0.32,
    );
    final hlGrad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: 0.50),
        Colors.white.withValues(alpha: 0.0),
      ],
    );
    canvas.drawOval(
      hlRect,
      Paint()..shader = hlGrad.createShader(hlRect),
    );

    // ── Icon ──
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: innerR * 1.15,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(
        center.dx - iconPainter.width / 2,
        center.dy - iconPainter.height / 2,
      ),
    );

    // ── Ground shadow ellipse ──
    final shadowRect = Rect.fromCenter(
      center: Offset(cx, h * 0.96),
      width: pinR * 1.1,
      height: pinR * 0.22,
    );
    canvas.drawOval(
      shadowRect,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant Gta5PinPainter old) =>
      old.color != color || old.icon != icon;

  Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color _lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }
}
