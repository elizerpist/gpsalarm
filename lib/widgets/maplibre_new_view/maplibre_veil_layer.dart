part of '../maplibre_new_view.dart';

extension _MaplibreVeilLayer on _MaplibreNewViewState {
  void _updateVeil(StyleController style, AlarmProvider alarmProv, {bool ignoreAssign = false}) {
    final leaveAlarms = alarmProv.alarmPoints
        .where(
          (p) =>
              p.zoneTrigger == ZoneTrigger.onLeave &&
              !(ignoreAssign == false && _isAssigning && _assignExisting?.id == p.id),
        )
        .toList();
    final hasFastLeave = ignoreAssign == false && _isAssigning && _assignZoneTrigger == ZoneTrigger.onLeave;

    if (leaveAlarms.isEmpty && !hasFastLeave) {
      style.updateGeoJsonSource(id: 'veil-src', data: _emptyGeoJson);
      return;
    }

    final holes = <List<List<double>>>[];
    for (final p in leaveAlarms) {
      double r = p.radiusMeters;
      if (p.triggerType == TriggerType.time && p.timeTrigger != null) {
        r = math.max(200.0, (_speedKmh / 3.6) * p.timeTrigger!.inSeconds.toDouble());
      }
      holes.add(_geoCircle(p.longitude, p.latitude, r));
    }
    if (hasFastLeave) {
      final r = _assignTriggerType == TriggerType.time
          ? math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60)
          : _assignRadius;
      holes.add(_geoCircle(_assignLng, _assignLat, r));
    }

    final coords = <List<List<double>>>[
      [
        [-180, -85],
        [180, -85],
        [180, 85],
        [-180, 85],
        [-180, -85],
      ],
      ...holes,
    ];

    style.updateGeoJsonSource(
      id: 'veil-src',
      data: jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {'type': 'Polygon', 'coordinates': coords},
            'properties': {},
          },
        ],
      }),
    );
  }
}
