part of '../maplibre_new_view.dart';

extension _MaplibreRadiusLayerRebuild on _MaplibreNewViewState {
  Future<void> _rebuildRadiusLayers(
    StyleController style,
    List<_RadiusCircleData> circles,
    int version,
  ) async {
    DebugConsole.log('REBUILD_LAYERS: START ${circles.length} circles v=$version');
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

    if (version != _radiusLayerVersion) return;

    for (int i = 0; i < 20; i++) {
      final id = 'alarm-$i';
      try {
        await style.removeLayer('radius-label-$id');
      } catch (_) {}
      try {
        await style.removeLayer('radius-circle-$id');
      } catch (_) {}
      style.updateGeoJsonSource(id: 'radius-pt-$id', data: _emptyGeoJson);
    }

    for (final c in circles) {
      final basePx = 2 * c.radiusMeters / (156543.03392 * math.cos(c.lat * math.pi / 180));
      final String fillColor = c.isLeave
          ? 'rgba(0,0,0,0)'
          : (c.isTime
              ? (c.active ? 'rgba(255,152,0,0.10)' : 'rgba(158,158,158,0.05)')
              : (c.active ? 'rgba(255,0,0,0.12)' : 'rgba(158,158,158,0.05)'));
      final String strokeColor = c.isTime
          ? (c.active ? 'rgba(255,152,0,0.7)' : 'rgba(158,158,158,0.3)')
          : (c.active ? 'rgba(255,0,0,0.6)' : 'rgba(158,158,158,0.3)');
      final strokeWidth = c.active ? 2.0 : 1.0;

      try {
        style.updateGeoJsonSource(
          id: 'radius-pt-${c.id}',
          data: _pointGeoJson(c.lng, c.lat),
        );
        await style.addLayer(CircleStyleLayer(
          id: 'radius-circle-${c.id}',
          sourceId: 'radius-pt-${c.id}',
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
          },
        ));
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
