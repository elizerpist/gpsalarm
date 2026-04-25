import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/alarm_point.dart';

CircleMarker buildRadiusCircle(AlarmPoint point) {
  return CircleMarker(
    point: LatLng(point.latitude, point.longitude),
    radius: point.radiusMeters,
    useRadiusInMeter: true,
    color: Colors.red.withOpacity(0.1),
    borderColor: Colors.red.withOpacity(0.5),
    borderStrokeWidth: 2,
  );
}
