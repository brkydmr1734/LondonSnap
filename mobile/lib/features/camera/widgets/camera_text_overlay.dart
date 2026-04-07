import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'overlay_models.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Snapchat-style Text Input Overlay
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class TextInputOverlay extends StatefulWidget {
  final TextOverlayItem? editingItem;
  final Function(TextOverlayItem) onDone;
  final VoidCallback onCancel;

  const TextInputOverlay({
    super.key,
    this.editingItem,
    required this.onDone,
    required this.onCancel,
  });

  @override
  State<TextInputOverlay> createState() => _TextInputOverlayState();
}

class _TextInputOverlayState extends State<TextInputOverlay> {
  late TextEditingController _controller;
  late TextOverlayFont _selectedFont;
  late Color _selectedColor;
  late double _fontSize;
  late TextBackgroundStyle _bgStyle;

  @override
  void initState() {
    super.initState();
    final item = widget.editingItem;
    _controller = TextEditingController(text: item?.text ?? '');
    _selectedFont = item?.font ?? TextOverlayFont.defaultFont;
    _selectedColor = item?.color ?? Colors.white;
    _fontSize = item?.fontSize ?? 32.0;
    _bgStyle = item?.backgroundStyle ?? TextBackgroundStyle.none;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDone() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      widget.onCancel();
      return;
    }
    final item = TextOverlayItem(
      id: widget.editingItem?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      position: widget.editingItem?.position ?? const Offset(0.5, 0.5),
      rotation: widget.editingItem?.rotation ?? 0.0,
      scale: widget.editingItem?.scale ?? 1.0,
      font: _selectedFont,
      color: _selectedColor,
      fontSize: _fontSize,
      backgroundStyle: _bgStyle,
    );
    widget.onDone(item);
  }

  void _cycleBackgroundStyle() {
    HapticFeedback.selectionClick();
    setState(() => _bgStyle = _bgStyle.next);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: widget.onCancel,
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: GestureDetector(
          onTap: () {},
          child: Stack(
            children: [
              // Main content (keyboard-aware)
              Positioned.fill(
                bottom: bottomInset,
                child: Column(
                  children: [
                    // Top bar
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            // Cancel
                            GestureDetector(
                              onTap: widget.onCancel,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.5),
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 22),
                              ),
                            ),
                            const Spacer(),
                            // Style toggle (T button)
                            GestureDetector(
                              onTap: _cycleBackgroundStyle,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _bgStyle != TextBackgroundStyle.none
                                      ? Colors.white
                                      : Colors.black.withValues(alpha: 0.5),
                                ),
                                child: Center(
                                  child: Text(
                                    'T',
                                    style: TextStyle(
                                      color: _bgStyle != TextBackgroundStyle.none
                                          ? Colors.black
                                          : Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Done
                            GestureDetector(
                              onTap: _handleDone,
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

                    // Centered text input with live style preview
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: _buildStyledTextField(),
                        ),
                      ),
                    ),

                    // Font picker
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: TextOverlayFont.values.map((font) {
                          final isSelected = font == _selectedFont;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedFont = font);
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Text(
                                  font.displayName,
                                  style: TextStyle(
                                    color: isSelected ? Colors.black : Colors.white,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Color row (compact horizontal)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            ...OverlayColors.palette.map((color) {
                              final isSelected = _selectedColor.toARGB32() == color.toARGB32();
                              return GestureDetector(
                                onTap: () => setState(() => _selectedColor = color),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? Colors.white : Colors.white24,
                                      width: isSelected ? 3 : 1,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),

                    // Font size slider (minimal)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Row(
                        children: [
                          const Text('A', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: _fontSize,
                                min: 16,
                                max: 72,
                                onChanged: (v) => setState(() => _fontSize = v),
                              ),
                            ),
                          ),
                          const Text('A', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStyledTextField() {
    final textStyle = _selectedFont.toTextStyle(_fontSize, _selectedColor).copyWith(
      shadows: _bgStyle == TextBackgroundStyle.none
          ? [
              Shadow(color: Colors.black.withValues(alpha: 0.6), offset: const Offset(1, 1), blurRadius: 4),
            ]
          : null,
    );

    Widget textField = TextField(
      controller: _controller,
      autofocus: true,
      textAlign: TextAlign.center,
      maxLines: null,
      style: textStyle,
      cursorColor: _selectedColor,
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: 'Type here...',
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: _fontSize),
        filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (_) => setState(() {}),
    );

    // Apply background style to the text field
    switch (_bgStyle) {
      case TextBackgroundStyle.none:
        return textField;
      case TextBackgroundStyle.solidFill:
        return Container(
          decoration: BoxDecoration(
            color: _selectedColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: _contrastColor(_selectedColor)),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.center,
              maxLines: null,
              style: _selectedFont.toTextStyle(_fontSize, _contrastColor(_selectedColor)),
              cursorColor: _contrastColor(_selectedColor),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Type here...',
                hintStyle: TextStyle(color: _contrastColor(_selectedColor).withValues(alpha: 0.5), fontSize: _fontSize),
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        );
      case TextBackgroundStyle.outlined:
        return textField;
      case TextBackgroundStyle.glow:
        return textField;
    }
  }

  Color _contrastColor(Color bg) {
    return bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Draggable Text Item (with trash zone support)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class DraggableTextItem extends StatefulWidget {
  final TextOverlayItem item;
  final Size containerSize;
  final Function(TextOverlayItem) onUpdate;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onDragStateChanged;

  const DraggableTextItem({
    super.key,
    required this.item,
    required this.containerSize,
    required this.onUpdate,
    required this.onTap,
    this.onDelete,
    this.onDragStateChanged,
  });

  @override
  State<DraggableTextItem> createState() => _DraggableTextItemState();
}

class _DraggableTextItemState extends State<DraggableTextItem> {
  late Offset _position;
  late double _scale;
  late double _rotation;
  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _position = widget.item.position;
    _scale = widget.item.scale;
    _rotation = widget.item.rotation;
  }

  @override
  void didUpdateWidget(DraggableTextItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _position = widget.item.position;
      _scale = widget.item.scale;
      _rotation = widget.item.rotation;
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    _baseRotation = _rotation;
    _isDragging = true;
    widget.onDragStateChanged?.call(true);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      final dx = details.focalPointDelta.dx / widget.containerSize.width;
      final dy = details.focalPointDelta.dy / widget.containerSize.height;
      _position = Offset(
        (_position.dx + dx).clamp(0.0, 1.0),
        (_position.dy + dy).clamp(0.0, 1.0),
      );
      if (details.scale != 1.0) {
        _scale = (_baseScale * details.scale).clamp(0.3, 4.0);
      }
      if (details.rotation != 0.0) {
        _rotation = _baseRotation + details.rotation;
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _isDragging = false;
    widget.onDragStateChanged?.call(false);

    // Check if in trash zone (bottom 15%)
    if (_position.dy > 0.85 && widget.onDelete != null) {
      HapticFeedback.heavyImpact();
      widget.onDelete!();
      return;
    }

    widget.onUpdate(widget.item.copyWith(
      position: _position,
      scale: _scale,
      rotation: _rotation,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final x = _position.dx * widget.containerSize.width;
    final y = _position.dy * widget.containerSize.height;

    return Positioned(
      left: x,
      top: y,
      child: GestureDetector(
        onTap: widget.onTap,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: AnimatedScale(
          scale: _isDragging ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Transform.rotate(
            angle: _rotation,
            child: Transform.scale(
              scale: _scale,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: _buildStyledText(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyledText() {
    final item = widget.item;
    final style = item.font.toTextStyle(item.fontSize, item.color);

    switch (item.backgroundStyle) {
      case TextBackgroundStyle.none:
        return Text(
          item.text,
          textAlign: TextAlign.center,
          style: style.copyWith(
            shadows: [
              Shadow(color: Colors.black.withValues(alpha: 0.7), offset: const Offset(2, 2), blurRadius: 4),
              Shadow(color: Colors.black.withValues(alpha: 0.3), offset: const Offset(-1, -1), blurRadius: 2),
            ],
          ),
        );
      case TextBackgroundStyle.solidFill:
        final contrastColor = item.color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: item.color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            item.text,
            textAlign: TextAlign.center,
            style: item.font.toTextStyle(item.fontSize, contrastColor),
          ),
        );
      case TextBackgroundStyle.outlined:
        return Stack(
          children: [
            // Stroke
            Text(
              item.text,
              textAlign: TextAlign.center,
              style: style.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 3
                  ..color = item.color,
              ),
            ),
            // Fill (transparent or contrasting)
            Text(
              item.text,
              textAlign: TextAlign.center,
              style: style.copyWith(
                color: Colors.transparent,
              ),
            ),
          ],
        );
      case TextBackgroundStyle.glow:
        return Text(
          item.text,
          textAlign: TextAlign.center,
          style: style.copyWith(
            shadows: [
              Shadow(color: item.color.withValues(alpha: 0.9), blurRadius: 20),
              Shadow(color: item.color.withValues(alpha: 0.7), blurRadius: 40),
              Shadow(color: item.color.withValues(alpha: 0.4), blurRadius: 60),
            ],
          ),
        );
    }
  }
}
