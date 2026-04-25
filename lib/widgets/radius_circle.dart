import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/alarm_point.dart';

CircleMarker buildRadiusCircle(AlarmPoint point) {
  final isActive = point.isActive;
  final color = isActive ? Colors.red : Colors.grey;

  return CircleMarker(
    point: LatLng(point.latitude, point.longitude),
    radius: point.radiusMeters,
    useRadiusInMeter: true,
    color: color.withOpacity(isActive ? 0.12 : 0.05),
    borderColor: color.withOpacity(isActive ? 0.6 : 0.3),
    borderStrokeWidth: isActive ? 2 : 1,
  );
}
