part of '../maplibre_new_view.dart';

extension _MaplibreVeilLayer on _MaplibreNewViewState {
  void _updateVeil(StyleController style, AlarmProvider alarmProv, {bool ignoreAssign = false}) {
    final useLiveAssignHole = !ignoreAssign &&
        _isAssigning &&
        _assignZoneTrigger == ZoneTrigger.onLeave &&
        (_showAssignOverlay || _useNativeExistingAssignLayer);
    final leaveAlarms = alarmProv.alarmPoints
        .where(
          (p) =>
              p.zoneTrigger == ZoneTrigger.onLeave &&
              !(!ignoreAssign && _isAssigning && _assignNativeHidden && _assignExisting?.id == p.id),
        )
        .where(
          (p) =>
              !(useLiveAssignHole &&
                  _assignExisting != null &&
                  _assignExisting!.id == p.id),
        )
        .toList();
    final hasFastLeave = useLiveAssignHole;

    if (leaveAlarms.isEmpty && !hasFastLeave) {
      try { style.updateGeoJsonSource(id: 'veil-src', data: _emptyGeoJson); } catch (_) {}
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

    try {
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
    } catch (_) {}
  }
}
