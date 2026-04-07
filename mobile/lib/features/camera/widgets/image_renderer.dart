import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'overlay_models.dart';

/// Utility class to render overlays onto an image
class ImageRenderer {
  /// Renders all overlays onto the original image and returns a new file
  static Future<File> renderOverlaysToImage({
    required File originalImage,
    required Size previewSize,
    required List<DrawingPath> drawingPaths,
    required List<TextOverlayItem> textOverlays,
    required List<StickerItem> stickers,
  }) async {
    // 1. Decode original image
    final bytes = await originalImage.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final originalUiImage = frame.image;

    final imageWidth = originalUiImage.width.toDouble();
    final imageHeight = originalUiImage.height.toDouble();

    // 2. Create a canvas the same size as the image
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 3. Draw original image
    canvas.drawImage(originalUiImage, Offset.zero, Paint());

    // 4. Calculate scale factors: preview size vs actual image size
    final scaleX = imageWidth / previewSize.width;
    final scaleY = imageHeight / previewSize.height;

    // 5. Draw all drawing paths (scaled)
    _drawPaths(canvas, drawingPaths, scaleX, scaleY);

    // 6. Draw all text overlays (scaled)
    _drawTextOverlays(canvas, textOverlays, imageWidth, imageHeight, scaleX, scaleY);

    // 7. Draw all stickers (scaled)
    _drawStickers(canvas, stickers, imageWidth, imageHeight, scaleX, scaleY);

    // 8. Convert to image
    final picture = recorder.endRecording();
    final img = await picture.toImage(originalUiImage.width, originalUiImage.height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) {
      throw Exception('Failed to convert image to bytes');
    }
    
    final pngBytes = byteData.buffer.asUint8List();

    // 9. Write to temp file
    final tempDir = await getTemporaryDirectory();
    final outputFile = File('${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.png');
    await outputFile.writeAsBytes(pngBytes);

    // Clean up
    originalUiImage.dispose();
    img.dispose();

    return outputFile;
  }

  /// Draw all drawing paths onto canvas
  static void _drawPaths(
    Canvas canvas,
    List<DrawingPath> paths,
    double scaleX,
    double scaleY,
  ) {
    // Use saveLayer so eraser (BlendMode.clear) works correctly
    final hasEraser = paths.any((p) => p.tool == DrawingTool.eraser);
    if (hasEraser) {
      canvas.saveLayer(null, Paint());
    }

    for (final path in paths) {
      if (path.points.isEmpty) continue;

      final avgScale = (scaleX + scaleY) / 2;
      final paint = Paint()
        ..strokeWidth = path.strokeWidth * avgScale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      // Configure paint based on tool type
      if (path.tool == DrawingTool.eraser) {
        paint.blendMode = BlendMode.clear;
        paint.color = Colors.transparent;
      } else {
        paint.color = path.color.withValues(alpha: path.tool.opacity);
      }

      if (path.points.length == 1) {
        final point = Offset(
          path.points.first.dx * scaleX,
          path.points.first.dy * scaleY,
        );
        canvas.drawCircle(point, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }

      // Draw smooth path using quadratic bezier curves
      final pathObj = ui.Path();
      final scaledPoints = path.points.map((p) => Offset(p.dx * scaleX, p.dy * scaleY)).toList();
      
      pathObj.moveTo(scaledPoints.first.dx, scaledPoints.first.dy);

      for (int i = 1; i < scaledPoints.length - 1; i++) {
        final p0 = scaledPoints[i];
        final p1 = scaledPoints[i + 1];
        final midX = (p0.dx + p1.dx) / 2;
        final midY = (p0.dy + p1.dy) / 2;
        pathObj.quadraticBezierTo(p0.dx, p0.dy, midX, midY);
      }

      if (scaledPoints.length > 1) {
        final last = scaledPoints.last;
        pathObj.lineTo(last.dx, last.dy);
      }

      canvas.drawPath(pathObj, paint);
    }

    if (hasEraser) {
      canvas.restore();
    }
  }

  /// Draw all text overlays onto canvas
  static void _drawTextOverlays(
    Canvas canvas,
    List<TextOverlayItem> textOverlays,
    double imageWidth,
    double imageHeight,
    double scaleX,
    double scaleY,
  ) {
    final avgScale = (scaleX + scaleY) / 2;

    for (final item in textOverlays) {
      final scaledFontSize = item.fontSize * avgScale;

      // Build base text style from font
      TextStyle textStyle = item.font.toTextStyle(scaledFontSize, item.color);

      // Apply background-style-specific text styling
      switch (item.backgroundStyle) {
        case TextBackgroundStyle.none:
          textStyle = textStyle.copyWith(
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.7),
                offset: Offset(2 * scaleX, 2 * scaleY),
                blurRadius: 4 * avgScale,
              ),
              Shadow(
                color: Colors.black.withValues(alpha: 0.3),
                offset: Offset(-1 * scaleX, -1 * scaleY),
                blurRadius: 2 * avgScale,
              ),
            ],
          );
          break;
        case TextBackgroundStyle.solidFill:
          // White text on colored background
          textStyle = textStyle.copyWith(color: Colors.white);
          break;
        case TextBackgroundStyle.outlined:
          // We draw outline separately via foreground paint
          textStyle = textStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0 * avgScale
              ..color = item.color,
          );
          break;
        case TextBackgroundStyle.glow:
          textStyle = textStyle.copyWith(
            shadows: [
              Shadow(color: item.color.withValues(alpha: 0.9), blurRadius: 12 * avgScale),
              Shadow(color: item.color.withValues(alpha: 0.6), blurRadius: 24 * avgScale),
              Shadow(color: item.color.withValues(alpha: 0.3), blurRadius: 40 * avgScale),
            ],
          );
          break;
      }

      final textSpan = TextSpan(text: item.text, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout();

      final x = item.position.dx * imageWidth;
      final y = item.position.dy * imageHeight;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(item.rotation);
      canvas.scale(item.scale);
      canvas.translate(-textPainter.width / 2, -textPainter.height / 2);

      // Draw solid fill background rect if needed
      if (item.backgroundStyle == TextBackgroundStyle.solidFill) {
        final bgPaint = Paint()..color = item.color;
        final padding = 8.0 * avgScale;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(-padding, -padding,
                textPainter.width + padding * 2, textPainter.height + padding * 2),
            Radius.circular(6 * avgScale),
          ),
          bgPaint,
        );
      }

      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  /// Draw all stickers onto canvas
  static void _drawStickers(
    Canvas canvas,
    List<StickerItem> stickers,
    double imageWidth,
    double imageHeight,
    double scaleX,
    double scaleY,
  ) {
    for (final item in stickers) {
      final baseFontSize = 64.0;
      final scaledFontSize = baseFontSize * ((scaleX + scaleY) / 2);

      final textSpan = TextSpan(
        text: item.emoji,
        style: TextStyle(fontSize: scaledFontSize),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Calculate position (centered)
      final x = item.position.dx * imageWidth;
      final y = item.position.dy * imageHeight;

      // Apply transformations
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(item.rotation);
      canvas.scale(item.scale);
      canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
      
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  /// Check if there are any overlays to render
  static bool hasOverlays({
    required List<DrawingPath> drawingPaths,
    required List<TextOverlayItem> textOverlays,
    required List<StickerItem> stickers,
  }) {
    return drawingPaths.isNotEmpty || textOverlays.isNotEmpty || stickers.isNotEmpty;
  }
}
