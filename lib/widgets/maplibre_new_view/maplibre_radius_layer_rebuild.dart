part of '../maplibre_new_view.dart';

extension _MaplibreRadiusLayerRebuild on _MaplibreNewViewState {
  Future<void> _restoreRadiusCircleLayer(StyleController style, _RadiusCircleData circle) async {
    try {
      await style.removeLayer('radius-circle-${circle.id}');
    } catch (_) {}
    await this._addRadiusCircleLayer(
      style,
      circle,
      belowLayerId: 'radius-label-${circle.id}',
    );
  }

  Future<void> _addRadiusCircleLayer(
    StyleController style,
    _RadiusCircleData circle, {
    String? belowLayerId,
  }) async {
    final basePx = 2 * circle.radiusMeters / (156543.03392 * math.cos(circle.lat * math.pi / 180));
    final String fillColor = circle.isLeave
        ? 'rgba(0,0,0,0)'
        : (circle.isTime
            ? (circle.active ? 'rgba(255,152,0,0.10)' : 'rgba(158,158,158,0.05)')
            : (circle.active ? 'rgba(255,0,0,0.12)' : 'rgba(158,158,158,0.05)'));
    final String strokeColor = circle.isTime
        ? (circle.active ? 'rgba(255,152,0,0.7)' : 'rgba(158,158,158,0.3)')
        : (circle.active ? 'rgba(255,0,0,0.6)' : 'rgba(158,158,158,0.3)');
    final strokeWidth = circle.active ? 2.0 : 1.0;

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
        'circle-color': fillColor,
        'circle-stroke-color': strokeColor,
        'circle-stroke-width': strokeWidth,
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
      final labelText = c.isTime
          ? '${(c.radiusMeters / 1000).toStringAsFixed(1)}km'
          : AlarmMarkerRenderer.formatDistance(c.radiusMeters);
      final markerColor = c.isTime
          ? (c.active ? Colors.orange : Colors.grey)
          : (c.active ? Colors.red : Colors.grey);
      final imageId = 'alarm-marker-${c.id}-${labelText}-${markerColor.value}';
      final cacheKey = '$labelText-${markerColor.value}-$_deviceDpr';
      markerImageIds[c.id] = imageId;
      markerLabels[c.id] = labelText;
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
      } catch (_) {
        // The same visual image may already be registered from a previous swap.
      }
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
      try { style.updateGeoJsonSource(id: 'radius-pt-$id', data: _emptyGeoJson); } catch (_) {}
    }

    for (final c in circles) {
      try {
        style.updateGeoJsonSource(
          id: 'radius-pt-${c.id}',
          data: _pointGeoJson(c.lng, c.lat),
        );
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
