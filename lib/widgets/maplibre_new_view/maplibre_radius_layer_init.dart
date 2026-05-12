part of '../maplibre_new_view.dart';

extension _MaplibreRadiusLayerInit on _MaplibreNewViewState {
  Future<void> _initRadiusLayer(StyleController style) async {
    await style.addSource(GeoJsonSource(id: 'veil-src', data: _emptyGeoJson));
    await style.addLayer(FillStyleLayer(
      id: 'veil-fill',
      sourceId: 'veil-src',
      paint: {'fill-color': '#FF0000', 'fill-opacity': 0.15},
    ));
    await style.addSource(GeoJsonSource(id: 'fast-fill-src', data: _emptyGeoJson));
    await style.addSource(GeoJsonSource(id: 'fast-line-src', data: _emptyGeoJson));
    await style.addLayer(FillStyleLayer(
      id: 'fast-fill',
      sourceId: 'fast-fill-src',
      paint: {
        'fill-color': [
          'case',
          ['==', ['get', 'isLeave'], true],
          'rgba(0,0,0,0)',
          ['==', ['get', 'isTime'], true],
          'rgba(255,152,0,0.10)',
          'rgba(255,0,0,0.12)',
        ],
      },
    ));
    await style.addLayer(LineStyleLayer(
      id: 'fast-line',
      sourceId: 'fast-line-src',
      layout: const {
        'line-cap': 'round',
        'line-join': 'round',
      },
      paint: {
        'line-color': [
          'case',
          ['==', ['get', 'isTime'], true],
          'rgba(255,152,0,0.7)',
          'rgba(255,0,0,0.6)',
        ],
        'line-width': 2.0,
      },
    ));
    for (int i = 0; i < 20; i++) {
      await style.addSource(GeoJsonSource(id: 'radius-pt-alarm-$i', data: _emptyGeoJson));
      await style.addSource(GeoJsonSource(id: 'radius-fill-alarm-$i', data: _emptyGeoJson));
      await style.addSource(GeoJsonSource(id: 'radius-line-alarm-$i', data: _emptyGeoJson));
    }
    _radiusLayerReady = true;
    DebugConsole.log('VECTOR: radius layer system ready');
  }

  Future<void> _updateFastCircleLayer(StyleController style) async {
    final isTime = _assignTriggerType == TriggerType.time;
    double radius = _assignRadius;
    if (isTime) {
      radius = math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60);
    }

    try {
      await style.updateGeoJsonSource(
        id: 'fast-fill-src',
        data: _circlePolygonGeoJson(
          _assignLng,
          _assignLat,
          radius,
          isTime: isTime,
          isLeave: _assignZoneTrigger == ZoneTrigger.onLeave,
        ),
      );
      await style.updateGeoJsonSource(
        id: 'fast-line-src',
        data: _circleLineGeoJson(
          _assignLng,
          _assignLat,
          radius,
          isTime: isTime,
          isLeave: _assignZoneTrigger == ZoneTrigger.onLeave,
        ),
      );
    } catch (_) {}
  }

  Future<void> _clearFastCircleLayer(StyleController style) async {
    try {
      await style.updateGeoJsonSource(id: 'fast-fill-src', data: _emptyGeoJson);
      await style.updateGeoJsonSource(id: 'fast-line-src', data: _emptyGeoJson);
    } catch (_) {}
  }
}
