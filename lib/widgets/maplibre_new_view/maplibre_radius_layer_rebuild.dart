part of '../maplibre_new_view.dart';

extension _MaplibreRadiusLayerRebuild on _MaplibreNewViewState {
  String _markerLabelForCircle(_RadiusCircleData circle) {
    return circle.isTime
        ? '${(circle.radiusMeters / 1000).toStringAsFixed(1)}km'
        : AlarmMarkerRenderer.formatDistance(circle.radiusMeters);
  }

  Color _markerColorForCircle(_RadiusCircleData circle) {
    return circle.isTime
        ? (circle.active ? Colors.orange : Colors.grey)
        : (circle.active ? Colors.red : Colors.grey);
  }

  Object get _radiusFillColorExpression => [
        'case',
        ['==', ['get', 'isLeave'], true],
        'rgba(0,0,0,0)',
        ['==', ['get', 'active'], false],
        'rgba(158,158,158,0.08)',
        ['==', ['get', 'isTime'], true],
        'rgba(255,152,0,0.10)',
        'rgba(255,0,0,0.12)',
      ];

  Object get _radiusStrokeColorExpression => [
        'case',
        ['==', ['get', 'active'], false],
        'rgba(158,158,158,0.70)',
        ['==', ['get', 'isTime'], true],
        'rgba(255,152,0,0.7)',
        'rgba(255,0,0,0.6)',
      ];

  Future<String> _ensureRadiusMarkerImage(
    StyleController style,
    _RadiusCircleData circle,
  ) async {
    final labelText = _markerLabelForCircle(circle);
    final markerColor = _markerColorForCircle(circle);
    final imageId = 'alarm-marker-${circle.id}';
    final visualKey = '$labelText-${markerColor.value}-$_deviceDpr';
    if (_registeredMarkerImageKeys[imageId] == visualKey) return imageId;

    final cacheKey = '$labelText-${markerColor.value}-$_deviceDpr';
    var markerPng = _markerBitmapCache[cacheKey];
    if (markerPng == null) {
      markerPng = await AlarmMarkerRenderer.render(
        label: labelText,
        color: markerColor,
        dpr: _deviceDpr,
      );
      _markerBitmapCache[cacheKey] = markerPng;
    }

    try {
      await style.removeImage(imageId);
    } catch (_) {}
    try {
      await style.addImage(imageId, markerPng);
      _registeredMarkerImageKeys[imageId] = visualKey;
    } catch (_) {
      _registeredMarkerImageKeys.remove(imageId);
    }
    return imageId;
  }

  Future<void> _updateRadiusCircleSources(
    StyleController style,
    _RadiusCircleData circle,
  ) async {
    await style.updateGeoJsonSource(
      id: 'radius-pt-${circle.id}',
      data: _pointGeoJson(circle.lng, circle.lat),
    );
    if (_is3D) {
      await style.updateGeoJsonSource(
        id: 'radius-fill-${circle.id}',
        data: _radiusFillSourceGeoJson(circle),
      );
      await style.updateGeoJsonSource(
        id: 'radius-line-${circle.id}',
        data: _radiusLineSourceGeoJson(circle),
      );
    }
  }

  Future<void> _updateExistingNativeAssignLayer(
    StyleController style,
    AlarmProvider alarmProv,
  ) async {
    final circle = this._currentAssignCircle(alarmProv);
    if (circle == null) return;
    await this._updateRadiusCircleSources(style, circle);
    await this._ensureRadiusMarkerImage(style, circle);
  }

  Future<void> _removeRadiusVisual(
    StyleController style,
    String id, {
    required bool clearSources,
  }) async {
    try {
      await style.removeLayer('radius-label-$id');
    } catch (_) {}
    try {
      await style.removeLayer('radius-circle-$id');
    } catch (_) {}
    try {
      await style.removeLayer('radius-line-$id');
    } catch (_) {}
    try {
      await style.removeLayer('radius-fill-$id');
    } catch (_) {}
    if (!clearSources) return;
    try {
      await style.updateGeoJsonSource(id: 'radius-pt-$id', data: _emptyGeoJson);
    } catch (_) {}
    try {
      await style.updateGeoJsonSource(id: 'radius-fill-$id', data: _emptyGeoJson);
    } catch (_) {}
    try {
      await style.updateGeoJsonSource(id: 'radius-line-$id', data: _emptyGeoJson);
    } catch (_) {}
  }

  Future<void> _upsertRadiusVisual(
    StyleController style,
    _RadiusCircleData circle,
  ) async {
    await this._removeRadiusVisual(style, circle.id, clearSources: false);
    await this._updateRadiusCircleSources(style, circle);
    await this._addRadiusCircleLayer(style, circle);
    final imageId = await this._ensureRadiusMarkerImage(style, circle);
    final markerSize = AlarmMarkerRenderer.measureLogicalSize(_markerLabelForCircle(circle));
    final pinTipCorrection = markerSize.height - AlarmMarkerSpec.pinSize;
    await style.addLayer(SymbolStyleLayer(
      id: 'radius-label-${circle.id}',
      sourceId: 'radius-pt-${circle.id}',
      layout: {
        'icon-image': imageId,
        'icon-size': 1.0,
        'icon-anchor': 'bottom',
        'icon-offset': [0.0, pinTipCorrection],
        'icon-allow-overlap': true,
      },
    ));
  }

  Future<void> _addRadiusCircleLayer(
    StyleController style,
    _RadiusCircleData circle, {
    String? belowLayerId,
  }) async {
    if (_is3D) {
      final fillLayer = FillStyleLayer(
        id: 'radius-fill-${circle.id}',
        sourceId: 'radius-fill-${circle.id}',
        paint: {'fill-color': _radiusFillColorExpression},
      );
      final lineLayer = LineStyleLayer(
        id: 'radius-line-${circle.id}',
        sourceId: 'radius-line-${circle.id}',
        layout: const {
          'line-cap': 'round',
          'line-join': 'round',
        },
        paint: {
          'line-color': _radiusStrokeColorExpression,
          'line-width': 2.0,
        },
      );
      try {
        await style.addLayer(fillLayer, belowLayerId: belowLayerId);
      } catch (_) {
        await style.addLayer(fillLayer);
      }
      try {
        await style.addLayer(lineLayer, belowLayerId: belowLayerId);
      } catch (_) {
        await style.addLayer(lineLayer);
      }
    } else {
      final basePx = 2 * circle.radiusMeters / (156543.03392 * math.cos(circle.lat * math.pi / 180));
      final layer = CircleStyleLayer(
        id: 'radius-circle-${circle.id}',
        sourceId: 'radius-pt-${circle.id}',
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
          'circle-color': _radiusFillColorExpression,
          'circle-stroke-color': _radiusStrokeColorExpression,
          'circle-stroke-width': 2.0,
          'circle-pitch-alignment': 'map',
          'circle-pitch-scale': 'map',
        },
      );
      try {
        await style.addLayer(layer, belowLayerId: belowLayerId);
      } catch (_) {
        await style.addLayer(layer);
      }
    }
  }

  String _radiusFillSourceGeoJson(_RadiusCircleData circle) {
    if (!_is3D) return _emptyGeoJson;
    return _circlePolygonGeoJson(
      circle.lng,
      circle.lat,
      circle.radiusMeters,
      isTime: circle.isTime,
      isLeave: circle.isLeave,
      active: circle.active,
    );
  }

  String _radiusLineSourceGeoJson(_RadiusCircleData circle) {
    if (!_is3D) return _emptyGeoJson;
    return _circleLineGeoJson(
      circle.lng,
      circle.lat,
      circle.radiusMeters,
      isTime: circle.isTime,
      isLeave: circle.isLeave,
      active: circle.active,
    );
  }

  Future<void> _rebuildRadiusLayers(
    StyleController style,
    List<_RadiusCircleData> circles,
    int version,
  ) async {
    if (!_radiusLayerReady) return;
    final generation = _styleGeneration;
    DebugConsole.log('REBUILD_LAYERS: START ${circles.length} circles v=$version gen=$generation');
    final markerImageIds = <String, String>{};
    final markerLabels = <String, String>{};
    for (final c in circles) {
      final labelText = _markerLabelForCircle(c);
      final imageId = await this._ensureRadiusMarkerImage(style, c);
      markerImageIds[c.id] = imageId;
      markerLabels[c.id] = labelText;
    }

    if (version != _radiusLayerVersion || generation != _styleGeneration) return;

    for (int i = 0; i < 20; i++) {
      final id = 'alarm-$i';
      try {
        await style.removeLayer('radius-label-$id');
      } catch (_) {}
      try {
        await style.removeLayer('radius-circle-$id');
      } catch (_) {}
      try {
        await style.removeLayer('radius-line-$id');
      } catch (_) {}
      try {
        await style.removeLayer('radius-fill-$id');
      } catch (_) {}
      try { await style.updateGeoJsonSource(id: 'radius-pt-$id', data: _emptyGeoJson); } catch (_) {}
      try { await style.updateGeoJsonSource(id: 'radius-fill-$id', data: _emptyGeoJson); } catch (_) {}
      try { await style.updateGeoJsonSource(id: 'radius-line-$id', data: _emptyGeoJson); } catch (_) {}
    }

    for (final c in circles) {
      try {
        await this._updateRadiusCircleSources(style, c);
        await this._addRadiusCircleLayer(style, c);
        final imageId = markerImageIds[c.id];
        if (imageId == null) continue;
        final markerSize = AlarmMarkerRenderer.measureLogicalSize(markerLabels[c.id]!);
        final pinTipCorrection = markerSize.height - AlarmMarkerSpec.pinSize;
        await style.addLayer(SymbolStyleLayer(
          id: 'radius-label-${c.id}',
          sourceId: 'radius-pt-${c.id}',
          layout: {
            'icon-image': imageId,
            'icon-size': 1.0,
            'icon-anchor': 'bottom',
            'icon-offset': [0.0, pinTipCorrection],
            'icon-allow-overlap': true,
          },
        ));
      } catch (e) {
        DebugConsole.log('VECTOR: radius layer error for ${c.id}: $e');
      }
    }
  }
}
