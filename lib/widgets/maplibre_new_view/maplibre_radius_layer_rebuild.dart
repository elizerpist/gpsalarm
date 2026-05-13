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

  String _markerImageIdForCircle(
    _RadiusCircleData circle,
    String labelText,
    Color markerColor,
  ) {
    final labelKey = labelText.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    final colorKey = markerColor.value.toRadixString(16);
    final dprKey = (_deviceDpr * 100).round();
    return 'alarm-marker-${circle.id}-$labelKey-$colorKey-$dprKey';
  }

  Object get _radiusFillColorExpression => [
    'case',
    [
      '==',
      ['get', 'isLeave'],
      true,
    ],
    'rgba(0,0,0,0)',
    [
      '==',
      ['get', 'active'],
      false,
    ],
    'rgba(158,158,158,0.08)',
    [
      '==',
      ['get', 'isTime'],
      true,
    ],
    'rgba(255,152,0,0.10)',
    'rgba(255,0,0,0.12)',
  ];

  Object get _radiusStrokeColorExpression => [
    'case',
    [
      '==',
      ['get', 'active'],
      false,
    ],
    'rgba(158,158,158,0.70)',
    [
      '==',
      ['get', 'isTime'],
      true,
    ],
    'rgba(255,152,0,0.7)',
    'rgba(255,0,0,0.6)',
  ];

  Future<String> _ensureRadiusMarkerImage(
    StyleController style,
    _RadiusCircleData circle,
  ) async {
    final labelText = _markerLabelForCircle(circle);
    final markerColor = _markerColorForCircle(circle);
    final imageId = _markerImageIdForCircle(circle, labelText, markerColor);
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
      await style.addImage(imageId, markerPng);
      _registeredMarkerImageKeys[imageId] = visualKey;
    } catch (_) {
      _registeredMarkerImageKeys[imageId] = visualKey;
    }
    return imageId;
  }

  Future<void> _syncRadiusMarkerImage(
    StyleController style,
    _RadiusCircleData circle,
  ) async {
    final imageId = await this._ensureRadiusMarkerImage(style, circle);
    _radiusPointImageIds[circle.id] = imageId;
  }

  String _radiusPointSourceGeoJson(_RadiusCircleData circle) {
    final imageId = _radiusPointImageIds[circle.id];
    return _pointGeoJson(
      circle.lng,
      circle.lat,
      properties: {
        if (imageId != null) 'image': imageId,
        ..._circleProps(
          isTime: circle.isTime,
          isLeave: circle.isLeave,
          active: circle.active,
        ),
      },
    );
  }

  String _radiusCircleLayerKey(_RadiusCircleData circle) {
    return '${circle.lat.toStringAsFixed(6)}:${circle.radiusMeters.toStringAsFixed(1)}';
  }

  Object _radiusCircleExpression(_RadiusCircleData circle) {
    final cosLat = math.cos(circle.lat * math.pi / 180).abs();
    final safeCosLat = math.max(0.000001, cosLat);
    final basePx = 2 * circle.radiusMeters / (156543.03392 * safeCosLat);
    return [
      'interpolate',
      ['exponential', 2.0],
      ['zoom'],
      0.0,
      basePx,
      22.0,
      basePx * 4194304.0,
    ];
  }

  CircleStyleLayer _radiusCircleStyleLayer(
    _RadiusCircleData circle, {
    required String id,
    required String sourceId,
  }) {
    return CircleStyleLayer(
      id: id,
      sourceId: sourceId,
      paint: {
        'circle-radius': _radiusCircleExpression(circle),
        'circle-color': _radiusFillColorExpression,
        'circle-stroke-color': _radiusStrokeColorExpression,
        'circle-stroke-width': 2.0,
        'circle-pitch-alignment': 'map',
        'circle-pitch-scale': 'map',
      },
    );
  }

  Future<void> _updateRadiusCircleSources(
    StyleController style,
    _RadiusCircleData circle, {
    bool updateMarker = false,
  }) async {
    if (updateMarker || !_radiusPointImageIds.containsKey(circle.id)) {
      await this._syncRadiusMarkerImage(style, circle);
    }
    await style.updateGeoJsonSource(
      id: 'radius-pt-${circle.id}',
      data: _radiusPointSourceGeoJson(circle),
    );
    if (_radiusVisualIds.contains(circle.id)) {
      await this._ensureRadiusCircleLayer(style, circle);
    }
  }

  Future<void> _updateExistingNativeAssignLayer(
    StyleController style,
    AlarmProvider alarmProv, {
    bool updateMarker = false,
  }) async {
    final circle = this._currentAssignCircle(alarmProv);
    if (circle == null) return;
    await this._updateRadiusCircleSources(
      style,
      circle,
      updateMarker: updateMarker,
    );
  }

  Future<void> _removeRadiusVisual(
    StyleController style,
    String id, {
    required bool clearSources,
  }) async {
    _radiusVisualIds.remove(id);
    _radiusCircleLayerKeys.remove(id);
    try {
      await style.removeLayer('radius-label-$id');
    } catch (_) {}
    try {
      await style.removeLayer('radius-circle-$id');
    } catch (_) {}
    if (!clearSources) return;
    _radiusPointImageIds.remove(id);
    try {
      await style.updateGeoJsonSource(id: 'radius-pt-$id', data: _emptyGeoJson);
    } catch (_) {}
  }

  Future<void> _upsertRadiusVisual(
    StyleController style,
    _RadiusCircleData circle,
  ) async {
    await this._removeRadiusVisual(style, circle.id, clearSources: false);
    await this._syncRadiusMarkerImage(style, circle);
    await this._updateRadiusCircleSources(style, circle);
    await this._addRadiusCircleLayer(style, circle);
    await this._addRadiusLabelLayer(style, circle);
    _radiusVisualIds.add(circle.id);
  }

  Future<void> _addRadiusLabelLayer(
    StyleController style,
    _RadiusCircleData circle,
  ) async {
    try {
      await style.removeLayer('radius-label-${circle.id}');
    } catch (_) {}
    final markerSize = AlarmMarkerRenderer.measureLogicalSize(
      _markerLabelForCircle(circle),
    );
    final pinTipCorrection = markerSize.height - AlarmMarkerSpec.pinSize;
    await style.addLayer(
      SymbolStyleLayer(
        id: 'radius-label-${circle.id}',
        sourceId: 'radius-pt-${circle.id}',
        layout: {
          'icon-image': ['get', 'image'],
          'icon-size': 1.0,
          'icon-anchor': 'bottom',
          'icon-offset': [0.0, pinTipCorrection],
          'icon-allow-overlap': true,
        },
      ),
    );
  }

  Future<void> _addRadiusCircleLayer(
    StyleController style,
    _RadiusCircleData circle, {
    String? belowLayerId,
  }) async {
    final circleLayer = _radiusCircleStyleLayer(
      circle,
      id: 'radius-circle-${circle.id}',
      sourceId: 'radius-pt-${circle.id}',
    );
    try {
      await style.addLayer(circleLayer, belowLayerId: belowLayerId);
    } catch (_) {
      await style.addLayer(circleLayer);
    }
    _radiusCircleLayerKeys[circle.id] = _radiusCircleLayerKey(circle);
  }

  Future<void> _ensureRadiusCircleLayer(
    StyleController style,
    _RadiusCircleData circle, {
    String? belowLayerId,
  }) async {
    final nextKey = _radiusCircleLayerKey(circle);
    if (_radiusCircleLayerKeys[circle.id] == nextKey) return;
    try {
      await style.removeLayer('radius-circle-${circle.id}');
    } catch (_) {}
    await this._addRadiusCircleLayer(style, circle, belowLayerId: belowLayerId);
  }

  Future<void> _ensureFastCircleLayer(
    StyleController style,
    _RadiusCircleData circle,
  ) async {
    final nextKey = _radiusCircleLayerKey(circle);
    if (_fastCircleLayerKey == nextKey) return;
    try {
      await style.removeLayer('fast-circle');
    } catch (_) {}
    await style.addLayer(
      _radiusCircleStyleLayer(
        circle,
        id: 'fast-circle',
        sourceId: 'fast-pt-src',
      ),
    );
    _fastCircleLayerKey = nextKey;
  }

  Future<void> _updateDraftRadiusCircleLayer(
    StyleController style,
    _RadiusCircleData circle, {
    bool updateMarker = false,
  }) async {
    if (updateMarker || !_radiusPointImageIds.containsKey(circle.id)) {
      await this._syncRadiusMarkerImage(style, circle);
    }
    await style.updateGeoJsonSource(
      id: 'radius-pt-${circle.id}',
      data: _radiusPointSourceGeoJson(circle),
    );
    await this._ensureRadiusCircleLayer(style, circle);
  }

  Future<void> _promoteDraftRadiusCircleLayer(
    StyleController style,
    _RadiusCircleData circle,
  ) async {
    await this._updateDraftRadiusCircleLayer(style, circle, updateMarker: true);
    await this._addRadiusLabelLayer(style, circle);
    _radiusVisualIds.add(circle.id);
  }

  Future<void> _rebuildRadiusLayers(
    StyleController style,
    List<_RadiusCircleData> circles,
    int version,
  ) async {
    if (!_radiusLayerReady) return;
    final generation = _styleGeneration;
    DebugConsole.log(
      'REBUILD_LAYERS: START ${circles.length} circles v=$version gen=$generation',
    );
    final markerLabels = <String, String>{};
    for (final c in circles) {
      final labelText = _markerLabelForCircle(c);
      final imageId = await this._ensureRadiusMarkerImage(style, c);
      markerLabels[c.id] = labelText;
      _radiusPointImageIds[c.id] = imageId;
    }

    if (version != _radiusLayerVersion || generation != _styleGeneration)
      return;

    // Also clear fast-circle if still alive (from new alarm save path)
    await this._clearFastCircleLayer(style);

    for (int i = 0; i < 20; i++) {
      final id = 'alarm-$i';
      _radiusVisualIds.remove(id);
      try {
        await style.removeLayer('radius-label-$id');
      } catch (_) {}
      try {
        await style.removeLayer('radius-circle-$id');
      } catch (_) {}
      try {
        await style.updateGeoJsonSource(
          id: 'radius-pt-$id',
          data: _emptyGeoJson,
        );
      } catch (_) {}
      _radiusCircleLayerKeys.remove(id);
    }

    final activeVisualIds = <String>{};
    for (final c in circles) {
      try {
        await this._updateRadiusCircleSources(style, c);
        await this._addRadiusCircleLayer(style, c);
        final markerSize = AlarmMarkerRenderer.measureLogicalSize(
          markerLabels[c.id]!,
        );
        final pinTipCorrection = markerSize.height - AlarmMarkerSpec.pinSize;
        await style.addLayer(
          SymbolStyleLayer(
            id: 'radius-label-${c.id}',
            sourceId: 'radius-pt-${c.id}',
            layout: {
              'icon-image': ['get', 'image'],
              'icon-size': 1.0,
              'icon-anchor': 'bottom',
              'icon-offset': [0.0, pinTipCorrection],
              'icon-allow-overlap': true,
            },
          ),
        );
        activeVisualIds.add(c.id);
      } catch (e) {
        DebugConsole.log('VECTOR: radius layer error for ${c.id}: $e');
      }
    }
    _radiusVisualIds
      ..clear()
      ..addAll(activeVisualIds);
  }
}
