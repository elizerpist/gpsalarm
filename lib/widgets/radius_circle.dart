import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/alarm_point.dart';

/// Calculate the effective radius for a point, considering time-based triggers.
double effectiveRadius(AlarmPoint point, double speedKmh) {
  if (point.triggerType == TriggerType.time && point.timeTrigger != null) {
    final speedMs = speedKmh / 3.6;
    final timeSeconds = point.timeTrigger!.inSeconds.toDouble();
    return math.max(200.0, speedMs * timeSeconds);
  }
  return point.radiusMeters;
}

CircleMarker buildRadiusCircle(AlarmPoint point, {double speedKmh = 0}) {
  final isActive = point.isActive;
  final isTime = point.triggerType == TriggerType.time;
  final color = isTime ? Colors.orange : (isActive ? Colors.red : Colors.grey);
  final radius = effectiveRadius(point, speedKmh);

  return CircleMarker(
    point: LatLng(point.latitude, point.longitude),
    radius: radius,
    useRadiusInMeter: true,
    color: color.withOpacity(isActive ? 0.12 : 0.05),
    borderColor: color.withOpacity(isActive ? 0.6 : 0.3),
    borderStrokeWidth: isActive ? 2 : 1,
  );
}

/// Build a dashed circle polygon for time-based triggers.
Polygon buildTimeTriggerCircle(LatLng center, double radiusMeters, {bool isActive = true}) {
  final points = buildCirclePoints(center, radiusMeters, segments: 64);
  return Polygon(
    points: points,
    color: Colors.orange.withOpacity(isActive ? 0.10 : 0.05),
    borderColor: Colors.orange.withOpacity(isActive ? 0.85 : 0.4),
    borderStrokeWidth: isActive ? 3.0 : 2.0,
    pattern: StrokePattern.dashed(segments: const [12.0, 6.0]),
    isFilled: true,
  );
}

/// Build an inverted polygon: the entire map is covered with a translucent
/// veil EXCEPT a circle hole. Used for "on leave" zone triggers.
Polygon buildInvertedRadiusPolygon(LatLng center, double radiusMeters, {
  bool isActive = true,
  Color? color,
}) {
  final fillColor = color ?? (isActive ? Colors.red : Colors.grey);
  // Circle as polygon points (64 segments is enough for flutter_map)
  final holePoints = buildCirclePoints(center, radiusMeters, segments: 64);
  // Outer bounds: cover the whole world
  final outerPoints = [
    const LatLng(-85, -180),
    const LatLng(-85, 180),
    const LatLng(85, 180),
    const LatLng(85, -180),
  ];

  return Polygon(
    points: outerPoints,
    holePointsList: [holePoints],
    color: fillColor.withOpacity(isActive ? 0.15 : 0.08),
    borderColor: fillColor.withOpacity(isActive ? 0.6 : 0.3),
    borderStrokeWidth: isActive ? 2 : 1,
    isFilled: true,
  );
}

/// Generate circle polygon points using Haversine destination formula.
List<LatLng> buildCirclePoints(LatLng center, double radiusMeters, {int segments = 64}) {
  final points = <LatLng>[];
  final angDist = radiusMeters / 6371000.0;
  final latR = center.latitude * math.pi / 180;
  final lngR = center.longitude * math.pi / 180;
  final sinLat = math.sin(latR);
  final cosLat = math.cos(latR);
  final sinAng = math.sin(angDist);
  final cosAng = math.cos(angDist);

  for (int i = 0; i <= segments; i++) {
    final bearing = 2 * math.pi * i / segments;
    final pLat = math.asin(sinLat * cosAng + cosLat * sinAng * math.cos(bearing));
    final pLng = lngR + math.atan2(
      math.sin(bearing) * sinAng * cosLat,
      cosAng - sinLat * math.sin(pLat),
    );
    points.add(LatLng(pLat * 180 / math.pi, pLng * 180 / math.pi));
  }
  return points;
}
