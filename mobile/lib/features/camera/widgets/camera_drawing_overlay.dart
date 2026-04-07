import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'overlay_models.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Drawing Canvas (renders all paths)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class DrawingOverlay extends StatelessWidget {
  final List<DrawingPath> paths;
  final DrawingPath? currentPath;

  const DrawingOverlay({super.key, required this.paths, this.currentPath});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: DrawingPainter(paths: paths, currentPath: currentPath),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawingPath> paths;
  final DrawingPath? currentPath;

  DrawingPainter({required this.paths, this.currentPath});

  @override
  void paint(Canvas canvas, Size size) {
    // Save layer for eraser blend
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final path in paths) {
      _drawPath(canvas, path);
    }
    if (currentPath != null) {
      _drawPath(canvas, currentPath!);
    }
    canvas.restore();
  }

  void _drawPath(Canvas canvas, DrawingPath path) {
    if (path.points.isEmpty) return;

    final paint = Paint()
      ..strokeWidth = path.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (path.tool == DrawingTool.eraser) {
      paint.blendMode = BlendMode.clear;
      paint.color = Colors.transparent;
    } else {
      paint.color = path.color.withValues(alpha: path.tool.opacity);
    }

    if (path.points.length == 1) {
      canvas.drawCircle(
        path.points.first,
        path.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      paint.style = PaintingStyle.stroke;
      return;
    }

    final pathObj = ui.Path();
    pathObj.moveTo(path.points.first.dx, path.points.first.dy);

    for (int i = 1; i < path.points.length - 1; i++) {
      final p0 = path.points[i];
      final p1 = path.points[i + 1];
      pathObj.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    }

    if (path.points.length > 1) {
      pathObj.lineTo(path.points.last.dx, path.points.last.dy);
    }

    canvas.drawPath(pathObj, paint);
  }

  @override
  bool shouldRepaint(covariant DrawingPainter old) =>
      old.paths != paths || old.currentPath != currentPath;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Gesture Detector for Drawing
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class DrawingGestureDetector extends StatelessWidget {
  final Function(Offset) onPanStart;
  final Function(Offset) onPanUpdate;
  final VoidCallback onPanEnd;
  final Widget child;

  const DrawingGestureDetector({
    super.key,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => onPanStart(d.localPosition),
      onPanUpdate: (d) => onPanUpdate(d.localPosition),
      onPanEnd: (_) => onPanEnd(),
      child: child,
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Snapchat-style Drawing HUD (tools, color slider, undo)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class DrawingHUD extends StatelessWidget {
  final DrawingTool selectedTool;
  final Color selectedColor;
  final double selectedStrokeWidth;
  final bool hasDrawings;
  final ValueChanged<DrawingTool> onToolChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final VoidCallback onUndo;
  final VoidCallback onDone;

  const DrawingHUD({
    super.key,
    required this.selectedTool,
    required this.selectedColor,
    required this.selectedStrokeWidth,
    required this.hasDrawings,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onUndo,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Top bar: undo + done
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Undo
                  GestureDetector(
                    onTap: hasDrawings ? onUndo : null,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                      child: Icon(
                        Icons.undo_rounded,
                        color: hasDrawings ? Colors.white : Colors.white30,
                        size: 22,
                      ),
                    ),
                  ),
                  // Done
                  GestureDetector(
                    onTap: onDone,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Right side: vertical rainbow color slider
        Positioned(
          right: 12,
          top: 0,
          bottom: 0,
          child: Center(
            child: _RainbowColorSlider(
              selectedColor: selectedColor,
              onColorChanged: onColorChanged,
            ),
          ),
        ),

        // Left side: brush size slider
        Positioned(
          left: 12,
          top: 0,
          bottom: 0,
          child: Center(
            child: _BrushSizeSlider(
              strokeWidth: selectedStrokeWidth,
              color: selectedTool == DrawingTool.eraser ? Colors.white : selectedColor,
              onChanged: onStrokeWidthChanged,
            ),
          ),
        ),

        // Bottom: tool switcher row
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: DrawingTool.values.map((tool) {
                  final isActive = tool == selectedTool;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onToolChanged(tool);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? Colors.white : Colors.black.withValues(alpha: 0.5),
                        border: Border.all(
                          color: isActive ? Colors.white : Colors.white24,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        tool.icon,
                        color: isActive ? Colors.black : Colors.white,
                        size: 22,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Vertical Rainbow Color Slider (Snapchat-style)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _RainbowColorSlider extends StatefulWidget {
  final Color selectedColor;
  final ValueChanged<Color> onColorChanged;

  const _RainbowColorSlider({required this.selectedColor, required this.onColorChanged});

  @override
  State<_RainbowColorSlider> createState() => _RainbowColorSliderState();
}

class _RainbowColorSliderState extends State<_RainbowColorSlider> {
  double _thumbPosition = 0.0; // 0.0 to 1.0
  bool _isDragging = false;
  static const double _sliderHeight = 260;
  static const double _sliderWidth = 28;

  @override
  void initState() {
    super.initState();
    _thumbPosition = 0.0;
  }

  void _updatePosition(Offset localPosition) {
    final pos = (localPosition.dy / _sliderHeight).clamp(0.0, 1.0);
    setState(() {
      _thumbPosition = pos;
      _isDragging = true;
    });
    widget.onColorChanged(OverlayColors.colorFromPosition(pos));
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = OverlayColors.colorFromPosition(_thumbPosition);
    return GestureDetector(
      onPanStart: (d) => _updatePosition(d.localPosition),
      onPanUpdate: (d) => _updatePosition(d.localPosition),
      onPanEnd: (_) => setState(() => _isDragging = false),
      onTapDown: (d) => _updatePosition(d.localPosition),
      child: SizedBox(
        width: 50,
        height: _sliderHeight,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Rainbow gradient bar
            Container(
              width: _sliderWidth,
              height: _sliderHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_sliderWidth / 2),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: OverlayColors.rainbowGradient,
                ),
                border: Border.all(color: Colors.white24, width: 1.5),
              ),
            ),
            // Thumb indicator
            Positioned(
              top: (_thumbPosition * _sliderHeight) - 14,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: _isDragging ? 34 : 28,
                height: _isDragging ? 34 : 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: currentColor,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
            // White & Black selectors at top/bottom
            Positioned(
              top: -32,
              child: _QuickColorDot(
                color: Colors.white,
                isSelected: widget.selectedColor == Colors.white,
                onTap: () => widget.onColorChanged(Colors.white),
              ),
            ),
            Positioned(
              bottom: -32,
              child: _QuickColorDot(
                color: Colors.black,
                isSelected: widget.selectedColor == Colors.black,
                onTap: () => widget.onColorChanged(Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickColorDot extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickColorDot({required this.color, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: isSelected ? Colors.yellow : Colors.white54,
            width: isSelected ? 3 : 1.5,
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Vertical Brush Size Slider
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _BrushSizeSlider extends StatefulWidget {
  final double strokeWidth;
  final Color color;
  final ValueChanged<double> onChanged;

  const _BrushSizeSlider({required this.strokeWidth, required this.color, required this.onChanged});

  @override
  State<_BrushSizeSlider> createState() => _BrushSizeSliderState();
}

class _BrushSizeSliderState extends State<_BrushSizeSlider> {
  static const double _height = 200;
  static const double _minSize = 2.0;
  static const double _maxSize = 30.0;
  bool _isDragging = false;

  double get _normalizedPosition =>
      1.0 - ((widget.strokeWidth - _minSize) / (_maxSize - _minSize)).clamp(0.0, 1.0);

  void _updateFromPosition(Offset localPos) {
    final norm = (localPos.dy / _height).clamp(0.0, 1.0);
    final size = _minSize + (1.0 - norm) * (_maxSize - _minSize);
    widget.onChanged(size);
    setState(() => _isDragging = true);
  }

  @override
  Widget build(BuildContext context) {
    final thumbY = _normalizedPosition * _height;
    return GestureDetector(
      onPanStart: (d) => _updateFromPosition(d.localPosition),
      onPanUpdate: (d) => _updateFromPosition(d.localPosition),
      onPanEnd: (_) => setState(() => _isDragging = false),
      child: SizedBox(
        width: 50,
        height: _height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Track
            Container(
              width: 4,
              height: _height,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Thumb: circle showing brush size
            Positioned(
              top: thumbY - widget.strokeWidth / 2,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: _isDragging ? widget.strokeWidth + 6 : widget.strokeWidth,
                height: _isDragging ? widget.strokeWidth + 6 : widget.strokeWidth,
                constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
