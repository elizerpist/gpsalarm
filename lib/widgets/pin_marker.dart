import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/alarm_point.dart';

Marker buildPinMarker({
  required AlarmPoint point,
  required VoidCallback onTap,
}) {
  return Marker(
    point: LatLng(point.latitude, point.longitude),
    width: 40,
    height: 40,
    child: GestureDetector(
      onTap: onTap,
      child: const Icon(Icons.location_on, color: Colors.red, size: 32),
    ),
  );
}
