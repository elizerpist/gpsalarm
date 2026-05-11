part of '../maplibre_new_view.dart';

extension _MaplibreRadiusLayerInit on _MaplibreNewViewState {
  Future<void> _initRadiusLayer(StyleController style) async {
    await style.addSource(GeoJsonSource(id: 'veil-src', data: _emptyGeoJson));
    await style.addLayer(FillStyleLayer(
      id: 'veil-fill',
      sourceId: 'veil-src',
      paint: {'fill-color': '#FF0000', 'fill-opacity': 0.15},
    ));
    await style.addSource(GeoJsonSource(id: 'fast-src', data: _emptyGeoJson));
    for (int i = 0; i < 20; i++) {
      await style.addSource(GeoJsonSource(id: 'radius-pt-alarm-$i', data: _emptyGeoJson));
    }
    _radiusLayerReady = true;
    DebugConsole.log('VECTOR: radius layer system ready');
  }

  Future<void> _updateFastCircleLayer(StyleController style) async {
    if (_fastCircleUpdating) return;
    _fastCircleUpdating = true;
    try {
      await style.removeLayer('fast-circle');
    } catch (_) {}

    style.updateGeoJsonSource(
      id: 'fast-src',
      data: _pointGeoJson(_assignLng, _assignLat),
    );

    final isTime = _assignTriggerType == TriggerType.time;
    double radius = _assignRadius;
    if (isTime) {
      radius = math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60);
    }
    final basePx = 2 * radius / (156543.03392 * math.cos(_assignLat * math.pi / 180));
    final fillColor = isTime ? 'rgba(255,152,0,0.10)' : 'rgba(255,0,0,0.12)';
    final strokeColor = isTime ? 'rgba(255,152,0,0.7)' : 'rgba(255,0,0,0.6)';

    await style.addLayer(CircleStyleLayer(
      id: 'fast-circle',
      sourceId: 'fast-src',
      paint: {
        'circle-radius': [
          'interpolate',
          ['exponential', 2.0],
          ['zoom'],
          0.0,
          basePx,
          22.0,
          basePx * 4194304.0,
        ],
        'circle-color': fillColor,
        'circle-stroke-color': strokeColor,
        'circle-stroke-width': 2.0,
      },
    ));
    _fastCircleUpdating = false;
  }
}
