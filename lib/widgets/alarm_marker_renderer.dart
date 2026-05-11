import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared design spec for alarm pin + distance chip.
/// Used by both raster (Flutter widget) and vector (MapLibre bitmap).
class AlarmMarkerSpec {
  static const double pinSize = 32;
  static const double chipFontSize = 9;
  static const double chipPaddingX = 4;
  static const double chipPaddingY = 1;
  static const double chipRadius = 4;
  static const double chipGap = 0; // gap between pin bottom and chip top
}

/// Renders a composite pin + chip image as PNG bytes for MapLibre icon-image.
/// Matches the raster Flutter widget design pixel-for-pixel.
class AlarmMarkerRenderer {
  static String formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)}km';
    return '${meters.round()}m';
  }

  static Size measureLogicalSize(String label) {
    final chipTp = TextPainter(textDirection: ui.TextDirection.ltr)
      ..text = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: AlarmMarkerSpec.chipFontSize,
          fontWeight: FontWeight.bold,
        ),
      )
      ..layout();

    final chipW = chipTp.width + AlarmMarkerSpec.chipPaddingX * 2;
    final chipH = chipTp.height + AlarmMarkerSpec.chipPaddingY * 2;
    return Size(
      math.max(AlarmMarkerSpec.pinSize, chipW),
      AlarmMarkerSpec.pinSize + AlarmMarkerSpec.chipGap + chipH,
    );
  }

  /// Render pin + chip composite to PNG bytes.
  /// [dpr] is devicePixelRatio — the image is rendered at dpr scale for crisp display.
  static Future<Uint8List> render({
    required String label,
    required Color color,
    required double dpr,
  }) async {
    const pinSize = AlarmMarkerSpec.pinSize;
    const chipFontSize = AlarmMarkerSpec.chipFontSize;
    const chipPaddingX = AlarmMarkerSpec.chipPaddingX;
    const chipPaddingY = AlarmMarkerSpec.chipPaddingY;
    const chipRadius = AlarmMarkerSpec.chipRadius;
    const chipGap = AlarmMarkerSpec.chipGap;

    // Measure chip text
    final chipTp = TextPainter(textDirection: ui.TextDirection.ltr)
      ..text = TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: chipFontSize * dpr,
          fontWeight: FontWeight.bold,
        ),
      )
      ..layout();

    final chipW = chipTp.width + chipPaddingX * 2 * dpr;
    final chipH = chipTp.height + chipPaddingY * 2 * dpr;

    // Canvas dimensions
    final totalW = (pinSize * dpr).clamp(chipW, double.infinity);
    final totalH = pinSize * dpr + chipGap * dpr + chipH;
    final canvasW = totalW.ceil().toDouble();
    final canvasH = totalH.ceil().toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, canvasW, canvasH));

    // Pin icon (Icons.location_on)
    final pinTp = TextPainter(textDirection: ui.TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(Icons.location_on.codePoint),
        style: TextStyle(
          fontSize: pinSize * dpr,
          fontFamily: Icons.location_on.fontFamily,
          package: Icons.location_on.fontPackage,
          color: color,
        ),
      )
      ..layout();
    pinTp.paint(canvas, Offset((canvasW - pinTp.width) / 2, 0));

    // Chip background (rounded rect)
    final chipTop = pinSize * dpr + chipGap * dpr;
    final chipRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(canvasW / 2, chipTop + chipH / 2),
        width: chipW,
        height: chipH,
      ),
      Radius.circular(chipRadius * dpr),
    );
    canvas.drawRRect(chipRect, Paint()..color = color.withOpacity(0.8));

    // Chip text (centered)
    chipTp.paint(
      canvas,
      Offset(
        (canvasW - chipTp.width) / 2,
        chipTop + (chipH - chipTp.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(canvasW.ceil(), canvasH.ceil());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
