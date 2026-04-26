import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/alarm_point.dart';

Marker buildPinMarker({
  required AlarmPoint point,
  required VoidCallback onTap,
}) {
  final isActive = point.isActive;
  final color = isActive ? Colors.red : Colors.grey;
  final label = point.triggerType == TriggerType.distance
      ? _formatDistance(point.radiusMeters)
      : '${point.timeTrigger?.inMinutes ?? 0}min';

  return Marker(
    point: LatLng(point.latitude, point.longitude),
    width: 60,
    height: 60,
    // Pin tip (bottom of 32px icon) is at y=32 in 60px box.
    // Alignment(0, 0.067) places y=32 at the geo coordinate.
    alignment: const Alignment(0, 0.067),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on,
            color: isActive ? color : Colors.grey[400],
            size: 32,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: (isActive ? color : Colors.grey).withOpacity(0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _formatDistance(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }
  return '${meters.round()}m';
}
