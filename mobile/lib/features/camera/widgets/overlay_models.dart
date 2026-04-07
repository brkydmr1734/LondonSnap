import 'package:flutter/material.dart';

// ── Drawing Tool Types ──

enum DrawingTool { pen, marker, highlighter, eraser }

extension DrawingToolExtension on DrawingTool {
  String get label {
    switch (this) {
      case DrawingTool.pen:
        return 'Pen';
      case DrawingTool.marker:
        return 'Marker';
      case DrawingTool.highlighter:
        return 'Highlighter';
      case DrawingTool.eraser:
        return 'Eraser';
    }
  }

  IconData get icon {
    switch (this) {
      case DrawingTool.pen:
        return Icons.edit;
      case DrawingTool.marker:
        return Icons.brush;
      case DrawingTool.highlighter:
        return Icons.highlight;
      case DrawingTool.eraser:
        return Icons.auto_fix_high;
    }
  }

  double get defaultStrokeWidth {
    switch (this) {
      case DrawingTool.pen:
        return 4.0;
      case DrawingTool.marker:
        return 12.0;
      case DrawingTool.highlighter:
        return 24.0;
      case DrawingTool.eraser:
        return 20.0;
    }
  }

  double get opacity {
    switch (this) {
      case DrawingTool.pen:
        return 1.0;
      case DrawingTool.marker:
        return 0.6;
      case DrawingTool.highlighter:
        return 0.35;
      case DrawingTool.eraser:
        return 1.0;
    }
  }
}

// ── Text Background Styles ──

enum TextBackgroundStyle { none, solidFill, outlined, glow }

extension TextBackgroundStyleExtension on TextBackgroundStyle {
  String get label {
    switch (this) {
      case TextBackgroundStyle.none:
        return 'Plain';
      case TextBackgroundStyle.solidFill:
        return 'Fill';
      case TextBackgroundStyle.outlined:
        return 'Outline';
      case TextBackgroundStyle.glow:
        return 'Glow';
    }
  }

  TextBackgroundStyle get next {
    final vals = TextBackgroundStyle.values;
    return vals[(index + 1) % vals.length];
  }
}

// ── Font Styles ──

enum TextOverlayFont {
  defaultFont,
  serif,
  mono,
  handwriting,
  bold,
  condensed,
}

extension TextOverlayFontExtension on TextOverlayFont {
  String get displayName {
    switch (this) {
      case TextOverlayFont.defaultFont:
        return 'Classic';
      case TextOverlayFont.serif:
        return 'Serif';
      case TextOverlayFont.mono:
        return 'Mono';
      case TextOverlayFont.handwriting:
        return 'Script';
      case TextOverlayFont.bold:
        return 'Bold';
      case TextOverlayFont.condensed:
        return 'Narrow';
    }
  }

  TextStyle toTextStyle(double fontSize, Color color) {
    switch (this) {
      case TextOverlayFont.defaultFont:
        return TextStyle(fontSize: fontSize, color: color, fontWeight: FontWeight.w500);
      case TextOverlayFont.serif:
        return TextStyle(fontSize: fontSize, color: color, fontFamily: 'serif', fontWeight: FontWeight.normal);
      case TextOverlayFont.mono:
        return TextStyle(fontSize: fontSize, color: color, fontFamily: 'monospace', fontWeight: FontWeight.w500);
      case TextOverlayFont.handwriting:
        return TextStyle(fontSize: fontSize, color: color, fontStyle: FontStyle.italic, fontWeight: FontWeight.w300);
      case TextOverlayFont.bold:
        return TextStyle(fontSize: fontSize, color: color, fontWeight: FontWeight.w900);
      case TextOverlayFont.condensed:
        return TextStyle(fontSize: fontSize, color: color, fontWeight: FontWeight.w600, letterSpacing: -0.5);
    }
  }
}

// ── Text Overlay Item ──

class TextOverlayItem {
  final String id;
  String text;
  Offset position;
  double rotation;
  double scale;
  TextOverlayFont font;
  Color color;
  double fontSize;
  TextBackgroundStyle backgroundStyle;

  TextOverlayItem({
    required this.id,
    required this.text,
    required this.position,
    this.rotation = 0.0,
    this.scale = 1.0,
    this.font = TextOverlayFont.defaultFont,
    this.color = Colors.white,
    this.fontSize = 32.0,
    this.backgroundStyle = TextBackgroundStyle.none,
  });

  TextOverlayItem copyWith({
    String? id,
    String? text,
    Offset? position,
    double? rotation,
    double? scale,
    TextOverlayFont? font,
    Color? color,
    double? fontSize,
    TextBackgroundStyle? backgroundStyle,
  }) {
    return TextOverlayItem(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      font: font ?? this.font,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
    );
  }
}

// ── Drawing Path ──

class DrawingPath {
  final String id;
  final Color color;
  final double strokeWidth;
  final List<Offset> points;
  final DrawingTool tool;

  DrawingPath({
    required this.id,
    required this.color,
    required this.strokeWidth,
    required this.points,
    this.tool = DrawingTool.pen,
  });

  DrawingPath copyWith({
    String? id,
    Color? color,
    double? strokeWidth,
    List<Offset>? points,
    DrawingTool? tool,
  }) {
    return DrawingPath(
      id: id ?? this.id,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      points: points ?? List.from(this.points),
      tool: tool ?? this.tool,
    );
  }
}

// ── Sticker Item ──

class StickerItem {
  final String id;
  final String emoji;
  Offset position;
  double scale;
  double rotation;

  StickerItem({
    required this.id,
    required this.emoji,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  StickerItem copyWith({
    String? id,
    String? emoji,
    Offset? position,
    double? scale,
    double? rotation,
  }) {
    return StickerItem(
      id: id ?? this.id,
      emoji: emoji ?? this.emoji,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }
}

// ── Colors ──

class OverlayColors {
  static const List<Color> palette = [
    Colors.white,
    Colors.black,
    Color(0xFFEF4444),
    Color(0xFF3B82F6),
    Color(0xFF22C55E),
    Color(0xFFEAB308),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFFF97316),
    Color(0xFF06B6D4),
    Color(0xFF84CC16),
    Color(0xFFF59E0B),
  ];

  /// Full rainbow gradient stops for vertical color slider
  static const List<Color> rainbowGradient = [
    Color(0xFFFF0000), // Red
    Color(0xFFFF7F00), // Orange
    Color(0xFFFFFF00), // Yellow
    Color(0xFF00FF00), // Green
    Color(0xFF00FFFF), // Cyan
    Color(0xFF0000FF), // Blue
    Color(0xFF8B00FF), // Violet
    Color(0xFFFF00FF), // Magenta
    Color(0xFFFF0000), // Red (loop)
  ];

  /// Pick a color from the rainbow at a normalized position (0.0 - 1.0)
  static Color colorFromPosition(double position) {
    final p = position.clamp(0.0, 1.0);
    final stops = rainbowGradient;
    final segment = p * (stops.length - 1);
    final index = segment.floor().clamp(0, stops.length - 2);
    final t = segment - index;
    return Color.lerp(stops[index], stops[index + 1], t) ?? stops[index];
  }
}

// ── Sticker Categories ──

class StickerCategories {
  static const Map<String, List<String>> categories = {
    'Smileys': [
      '😀', '😂', '🥹', '😍', '🥰', '😎', '🤩', '😜', '🤪', '😏',
      '🥺', '😢', '😭', '😤', '🤯', '🫠', '😈', '💀', '🤡', '👻',
      '🙄', '😴', '🤮', '🥶', '🥵', '😇', '🫡', '🤫', '🫢', '🤭',
    ],
    'Love': [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💖', '💝',
      '💗', '💓', '💞', '💕', '❤️‍🔥', '💋', '😘', '🥰', '😍', '🫶',
    ],
    'Gestures': [
      '👍', '👎', '✌️', '🤞', '🫰', '🤙', '👋', '🙌', '👏', '🤝',
      '💪', '🫵', '☝️', '👆', '👇', '👈', '👉', '🖕', '✋', '🤘',
    ],
    'Animals': [
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🦁',
      '🐮', '🐷', '🐸', '🐵', '🐔', '🦄', '🐝', '🦋', '🐙', '🦈',
    ],
    'Food': [
      '🍕', '🍔', '🌮', '🍟', '🍣', '🍩', '🧁', '🍰', '☕', '🍺',
      '🍷', '🥂', '🍾', '🧋', '🥤', '🍿', '🌶️', '🍪', '🍫', '🍦',
    ],
    'Activity': [
      '⚽', '🏀', '🏈', '🎾', '🎮', '🎯', '🎲', '🎭', '🎨', '🎬',
      '🎤', '🎧', '🎵', '🎸', '🏆', '🥇', '🎪', '🎢', '🏂', '🎳',
    ],
    'Travel': [
      '✈️', '🚗', '🚀', '🚇', '🚢', '🏠', '🏰', '🗼', '🗽', '🎡',
      '⛱️', '🏖️', '🌅', '🌄', '🗺️', '🧭', '🌍', '🌎', '🌏', '⛰️',
    ],
    'London': [
      '🇬🇧', '🏰', '👑', '🎡', '☕', '🚇', '🏙️', '🌧️', '💂', '🎓',
      '🫖', '🍺', '⚽', '🎭', '📸', '🌉', '🏛️', '🎪', '🚕', '☂️',
    ],
    'Symbols': [
      '✨', '🔥', '💯', '⭐', '🌟', '💫', '⚡', '🌈', '☀️', '🌙',
      '❄️', '💧', '🎉', '🎊', '🎁', '💰', '💎', '🔔', '📣', '💡',
    ],
  };
}
