part of '../maplibre_new_view.dart';

/// Flutter-side circle painter driven by ValueNotifier for 60fps updates
/// without widget rebuilds. Dashed border for time-based triggers.
class _RadiusOverlayPainter extends CustomPainter {
  final Offset center;
  final ValueNotifier<double> radiusNotifier;
  final bool isTime;
  final bool isLeave;
  final bool active;

  _RadiusOverlayPainter({
    required this.center,
    required this.radiusNotifier,
    required this.isTime,
    this.isLeave = false,
    this.active = true,
  }) : super(repaint: radiusNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    final radiusPx = radiusNotifier.value;
    final fillColor = !active
        ? const Color(0x149E9E9E)
        : (isTime ? const Color(0x1AFF9800) : const Color(0x1FFF0000));
    final strokeColor = !active
        ? const Color(0xB39E9E9E)
        : (isTime ? const Color(0xB3FF9800) : const Color(0x99FF0000));

    if (isLeave && active) {
      final veilPath = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addOval(Rect.fromCircle(center: center, radius: radiusPx));
      canvas.drawPath(veilPath, Paint()..color = const Color(0x26FF0000));
    }

    if (!isLeave) {
      canvas.drawCircle(center, radiusPx, Paint()..color = fillColor);
    }

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    if (isTime) {
      final path = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radiusPx));
      final dashed = dashPath(
        path,
        dashArray: CircularIntervalList<double>([8.0, 4.0]),
      );
      canvas.drawPath(dashed, strokePaint);
    } else {
      canvas.drawCircle(center, radiusPx, strokePaint);
    }
  }

  @override
  bool shouldRepaint(_RadiusOverlayPainter oldDelegate) => true;
}
