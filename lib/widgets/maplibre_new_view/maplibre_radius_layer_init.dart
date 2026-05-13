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

  Future<void> _updateFastCircleLayer(
    StyleController style, {
    bool radiusOnly = false,
  }) async {
    final sw = Stopwatch()..start();
    final isTime = _assignTriggerType == TriggerType.time;
    double radius = _assignRadius;
    if (isTime) {
      radius = math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60);
    }

    final draftId = _assignExisting == null ? _assignNativeAlarmLayerId : null;
    if (draftId != null) {
      try {
        await this._updateDraftRadiusCircleLayer(style, (
          id: draftId,
          lng: _assignLng,
          lat: _assignLat,
          radiusMeters: radius,
          active: _assignActive,
          isTime: isTime,
          isLeave: _assignZoneTrigger == ZoneTrigger.onLeave,
        ), radiusOnly: radiusOnly);
      } catch (_) {}
      sw.stop();
      if (_shouldLogAssignFrame(_assignSyncSeq) || sw.elapsedMilliseconds > 12) {
        DebugConsole.log(
          'FAST_CIRCLE_SYNC: mode=draft id=$draftId r=${radius.round()}m '
          'leave=${_assignZoneTrigger == ZoneTrigger.onLeave} '
          'ms=${sw.elapsedMilliseconds} ${_assignDebugState()}',
        );
      }
      return;
    }

    try {
      if (radiusOnly &&
          _fastCircleLayerKey != null &&
          await this._setCircleLayerRadiusPaint(
            style,
            layerId: 'fast-circle',
            visualId: 'fast',
            radiusPx: this._currentRadiusPx,
            debugReason: 'fast-radius-only',
          )) {
        sw.stop();
        if (_shouldLogAssignFrame(_assignSyncSeq) ||
            sw.elapsedMilliseconds > 12) {
          DebugConsole.log(
            'FAST_CIRCLE_SYNC: mode=paint r=${radius.round()}m '
            'leave=${_assignZoneTrigger == ZoneTrigger.onLeave} '
            'ms=${sw.elapsedMilliseconds} ${_assignDebugState()}',
          );
        }
        return;
      }
      await style.updateGeoJsonSource(
        id: 'fast-pt-src',
        data: _pointGeoJson(
          _assignLng,
          _assignLat,
          properties: _circleProps(
            lat: _assignLat,
            radiusMeters: radius,
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
    sw.stop();
    if (_shouldLogAssignFrame(_assignSyncSeq) || sw.elapsedMilliseconds > 12) {
      DebugConsole.log(
        'FAST_CIRCLE_SYNC: mode=fast r=${radius.round()}m '
        'leave=${_assignZoneTrigger == ZoneTrigger.onLeave} '
        'ms=${sw.elapsedMilliseconds} ${_assignDebugState()}',
      );
    }
  }

  Future<void> _clearFastCircleLayer(StyleController style) async {
    final sw = Stopwatch()..start();
    try {
      await style.removeLayer('fast-circle');
    } catch (_) {}
    _fastCircleLayerKey = null;
    _radiusPaintOverrideIds.remove('fast');
    try {
      await style.updateGeoJsonSource(id: 'fast-pt-src', data: _emptyGeoJson);
    } catch (_) {}
    sw.stop();
    if (sw.elapsedMilliseconds > 8) {
      DebugConsole.log('FAST_CIRCLE_CLEAR: ms=${sw.elapsedMilliseconds}');
    }
  }
}
