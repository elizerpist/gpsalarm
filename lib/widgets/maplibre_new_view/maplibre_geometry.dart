part of '../maplibre_new_view.dart';

const _emptyGeoJson = '{"type":"FeatureCollection","features":[]}';

String _pointGeoJson(
  double lng,
  double lat, {
  Map<String, Object?> properties = const {},
}) {
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [lng, lat],
        },
        'properties': properties,
      },
    ],
  });
}

Map<String, Object> _circleProps({
  required bool isTime,
  required bool isLeave,
  required bool active,
}) {
  return {'isTime': isTime, 'isLeave': isLeave, 'active': active};
}

/// Meters per pixel for MapLibre vector tiles (512px effective tile size).
/// Standard slippy-map formula uses 256px; MapLibre vector renders at 512px
/// scale, so zoom+1 gives the correct conversion.
double _vectorMetersPerPx(double lat, double zoom) {
  return 156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom + 1);
}

/// Polygon ring for veil holes only. Radius circles must stay CircleStyleLayer.
List<List<double>> _geoCircle(double lng, double lat, double radiusMeters) {
  const segments = 128;
  final coords = <List<double>>[];
  final angDist = radiusMeters / 6371000.0;
  final latR = lat * math.pi / 180;
  final lngR = lng * math.pi / 180;
  final sinLat = math.sin(latR);
  final cosLat = math.cos(latR);
  final sinAng = math.sin(angDist);
  final cosAng = math.cos(angDist);
  for (int i = 0; i <= segments; i++) {
    final bearing = 2 * math.pi * i / segments;
    final pLat = math.asin(
      sinLat * cosAng + cosLat * sinAng * math.cos(bearing),
    );
    final pLng =
        lngR +
        math.atan2(
          math.sin(bearing) * sinAng * cosLat,
          cosAng - sinLat * math.sin(pLat),
        );
    coords.add([pLng * 180 / math.pi, pLat * 180 / math.pi]);
  }
  return coords;
}

/// Render a Material icon to PNG bytes using PictureRecorder.
Future<Uint8List> _renderIconToPng(IconData icon, Color color, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
  );
  final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
  textPainter.text = TextSpan(
    text: String.fromCharCode(icon.codePoint),
    style: TextStyle(
      fontSize: size.toDouble(),
      fontFamily: icon.fontFamily,
      package: icon.fontPackage,
      color: color,
    ),
  );
  textPainter.layout();
  textPainter.paint(canvas, Offset.zero);
  final picture = recorder.endRecording();
  final img = await picture.toImage(size, size);
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
