part of '../maplibre_new_view.dart';

extension _MaplibreVeilLayer on _MaplibreNewViewState {
  void _updateVeil(StyleController style, AlarmProvider alarmProv, {bool ignoreAssign = false}) {
    final sw = Stopwatch()..start();
    final seq = ++_veilUpdateSeq;
    final useLiveAssignHole = !ignoreAssign &&
        _isAssigning &&
        _assignActive &&
        _assignZoneTrigger == ZoneTrigger.onLeave &&
        (_showAssignOverlay || _useNativeExistingAssignLayer);
    final leaveAlarms = alarmProv.alarmPoints
        .where(
          (p) =>
              p.isActive &&
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
      if (_lastVeilGeoJson != _emptyGeoJson) {
        try {
          style.updateGeoJsonSource(id: 'veil-src', data: _emptyGeoJson);
          _lastVeilGeoJson = _emptyGeoJson;
        } catch (_) {}
      }
      sw.stop();
      if (_isAssigning &&
          (_shouldLogAssignFrame(_assignSyncSeq) || sw.elapsedMilliseconds > 8)) {
        DebugConsole.log(
          'VEIL_SYNC: seq=$seq empty=true ms=${sw.elapsedMilliseconds} '
          'ignore=$ignoreAssign live=$useLiveAssignHole leaves=0 ${_assignDebugState()}',
        );
      }
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

    final veilGeoJson = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {'type': 'Polygon', 'coordinates': coords},
          'properties': {},
        },
      ],
    });

    try {
      if (_lastVeilGeoJson != veilGeoJson) {
        style.updateGeoJsonSource(id: 'veil-src', data: veilGeoJson);
        _lastVeilGeoJson = veilGeoJson;
      }
    } catch (_) {}
    sw.stop();
    if ((_isAssigning && _shouldLogAssignFrame(_assignSyncSeq)) ||
        sw.elapsedMilliseconds > 8) {
      DebugConsole.log(
        'VEIL_SYNC: seq=$seq empty=false ms=${sw.elapsedMilliseconds} '
        'ignore=$ignoreAssign live=$useLiveAssignHole leaves=${leaveAlarms.length} '
        'fastLeave=$hasFastLeave holes=${holes.length} ${_assignDebugState()}',
      );
    }
  }
}
