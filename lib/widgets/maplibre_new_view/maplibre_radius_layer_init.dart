part of '../maplibre_new_view.dart';

extension _MaplibreRadiusLayerInit on _MaplibreNewViewState {
  Future<void> _initRadiusLayer(StyleController style) async {
    await style.addSource(GeoJsonSource(id: 'veil-src', data: _emptyGeoJson));
    await style.addLayer(
      FillStyleLayer(
        id: 'veil-fill',
        sourceId: 'veil-src',
        paint: {'fill-color': '#FF0000', 'fill-opacity': 0.15},
      ),
    );
    await style.addSource(
      GeoJsonSource(id: 'fast-pt-src', data: _emptyGeoJson),
    );
    for (int i = 0; i < 20; i++) {
      await style.addSource(
        GeoJsonSource(id: 'radius-pt-alarm-$i', data: _emptyGeoJson),
      );
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
        id: 'fast-pt-src',
        data: _pointGeoJson(
          _assignLng,
          _assignLat,
          properties: _circleProps(
            isTime: isTime,
            isLeave: _assignZoneTrigger == ZoneTrigger.onLeave,
            active: _assignActive,
          ),
        ),
      );
      await this._ensureFastCircleLayer(style, (
        id: 'fast',
        lng: _assignLng,
        lat: _assignLat,
        radiusMeters: radius,
        active: _assignActive,
        isTime: isTime,
        isLeave: _assignZoneTrigger == ZoneTrigger.onLeave,
      ));
    } catch (_) {}
  }

  Future<void> _clearFastCircleLayer(StyleController style) async {
    try {
      await style.removeLayer('fast-circle');
    } catch (_) {}
    _fastCircleLayerKey = null;
    try {
      await style.updateGeoJsonSource(id: 'fast-pt-src', data: _emptyGeoJson);
    } catch (_) {}
  }
}
