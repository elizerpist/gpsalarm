import 'dart:math' as math;
import 'package:flutter/material.dart';

/// L-shaped map scale indicator — shows horizontal and vertical scale bars
/// that are always proportional to the current zoom level.
class ScaleBar extends StatelessWidget {
  final double zoom;
  final double latitude;
  final double? speedKmh;

  const ScaleBar({super.key, required this.zoom, required this.latitude, this.speedKmh});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white.withOpacity(0.8) : Colors.black.withOpacity(0.7);
    final textColor = isDark ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.8);

    // Meters per pixel at this zoom and latitude
    final metersPerPx = 156543.03392 * math.cos(latitude * math.pi / 180) / math.pow(2, zoom);

    // Find a "nice" distance that fits in ~60-150px
    final targetPx = 80.0;
    final targetMeters = targetPx * metersPerPx;
    final niceMeters = _niceDistance(targetMeters);
    final barPx = niceMeters / metersPerPx;
    final label = _formatDistance(niceMeters);

    const strokeWidth = 2.0;

    final shadowStyle = [
      Shadow(color: isDark ? Colors.black : Colors.white, blurRadius: 3),
      Shadow(color: isDark ? Colors.black : Colors.white, blurRadius: 3),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Speed indicator (if available)
        if (speedKmh != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${speedKmh!.round()} km/h',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: speedKmh! > 0 ? Colors.blue[700] : textColor,
                shadows: shadowStyle,
              ),
            ),
          ),
        // Scale bar
        SizedBox(
          width: barPx + 24,
          height: barPx + 20,
          child: CustomPaint(
            painter: _ScaleBarPainter(
              barLength: barPx,
              strokeWidth: strokeWidth,
              color: color,
            ),
            child: Padding(
              padding: EdgeInsets.only(bottom: 4, left: strokeWidth + 4),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(label,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textColor, shadows: shadowStyle),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Pick the nearest "nice" round distance value.
  static double _niceDistance(double meters) {
    const stops = [
      5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0,
      1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 50000.0,
      100000.0, 200000.0, 500000.0,
    ];
    for (final s in stops) {
      if (s >= meters * 0.6) return s;
    }
    return stops.last;
  }

  static String _formatDistance(double meters) {
    if (meters >= 1000) {
      final km = meters / 1000;
      return km == km.roundToDouble() ? '${km.round()} km' : '${km.toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }
}

class _ScaleBarPainter extends CustomPainter {
  final double barLength;
  final double strokeWidth;
  final Color color;

  _ScaleBarPainter({
    required this.barLength,
    required this.strokeWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // L-shape: vertical line going up, horizontal line going right
    // Origin at bottom-left corner of the L
    final originX = strokeWidth / 2;
    final originY = size.height - strokeWidth / 2;

    final path = Path()
      // Vertical bar (going up)
      ..moveTo(originX, originY - barLength)
      ..lineTo(originX, originY)
      // Horizontal bar (going right)
      ..lineTo(originX + barLength, originY);

    // White outline for contrast
    final outlinePaint = Paint()
      ..color = color == Colors.white.withOpacity(0.8)
          ? Colors.black.withOpacity(0.3)
          : Colors.white.withOpacity(0.6)
      ..strokeWidth = strokeWidth + 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, outlinePaint);
    canvas.drawPath(path, paint);

    // Small tick marks at ends
    const tickSize = 4.0;
    // Top of vertical bar
    canvas.drawLine(
      Offset(originX - tickSize / 2, originY - barLength),
      Offset(originX + tickSize / 2, originY - barLength),
      paint,
    );
    // Right end of horizontal bar
    canvas.drawLine(
      Offset(originX + barLength, originY - tickSize / 2),
      Offset(originX + barLength, originY + tickSize / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ScaleBarPainter old) =>
      old.barLength != barLength || old.color != color;
}
