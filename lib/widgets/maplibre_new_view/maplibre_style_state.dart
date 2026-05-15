part of '../maplibre_new_view.dart';

extension _MaplibreStyleState on _MaplibreNewViewState {
  void _prepareVectorStyle(String styleUrl) {
    if (_activeStyleUrl == styleUrl) return;
    _activeStyleUrl = styleUrl;
    _registeredStyleUrl = null;
    _imagesRegistered = false;
    _radiusLayerReady = false;
    _lastRadiusDataHash = '';
    _lastVeilGeoJson = '';
    _lastVeilOutlineGeoJson = '';
    this._resetExitDebugTrace();
    _assignExitVeilOutlineRestoreTimer?.cancel();
    _assignExitVeilOutlineRestoreTimer = null;
    _assignExitVeilOutlineActive = false;
    _assignExitVeilOutlineFastSuppressed = false;
    _assignExitVeilOutlineOpacity = 0.0;
    _radiusDebounce?.cancel();
    _veilSyncTimer?.cancel();
    _veilSyncTimer = null;
    _veilSyncRequested = false;
    _veilSyncRequestedIgnoreAssign = false;
    _veilSyncRequestedFullQuality = false;
    _veilSyncRequestedReason = null;
    _assignRadiusPaintSyncPending = false;
    _assignRadiusPaintSyncReason = null;
    _radiusLayerVersion++;
    _styleGeneration++;
    _registeredMarkerImageKeys.clear();
    _androidGeoJsonSyncViewId = null;
    _radiusPointImageIds.clear();
    _radiusCircleLayerKeys.clear();
    _radiusVisualIds.clear();
    _radiusPaintOverrideIds.clear();
    _radiusPaintOverrideTokens.clear();
    _fastCircleLayerKey = null;
    _controller = null;
  }

  Future<bool> _tryUpdateGeoJsonSource(
    StyleController style, {
    required String id,
    required String data,
  }) async {
    final isVeilSource = id == 'veil-src' || id == 'veil-live-outline-src';
    if (isVeilSource &&
        _tryUpdateGeoJsonSourceSyncAndroid(id: id, data: data)) {
      return true;
    }

    try {
      await style.updateGeoJsonSource(id: id, data: data);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _tryUpdateGeoJsonSourceSyncAndroid({
    required String id,
    required String data,
  }) {
    if (foundation.defaultTargetPlatform != foundation.TargetPlatform.android) {
      return false;
    }

    final cachedViewId = _androidGeoJsonSyncViewId;
    if (cachedViewId != null &&
        _tryUpdateGeoJsonSourceSyncAndroidView(
          viewId: cachedViewId,
          id: id,
          data: data,
        )) {
      return true;
    }

    for (var viewId = 63; viewId >= 0; viewId--) {
      if (viewId == cachedViewId) continue;
      if (_tryUpdateGeoJsonSourceSyncAndroidView(
        viewId: viewId,
        id: id,
        data: data,
      )) {
        _androidGeoJsonSyncViewId = viewId;
        return true;
      }
    }

    _androidGeoJsonSyncViewId = null;
    return false;
  }

  bool _tryUpdateGeoJsonSourceSyncAndroidView({
    required int viewId,
    required String id,
    required String data,
  }) {
    try {
      return using((arena) {
        final registry = maplibre_jni.MapLibreRegistry.INSTANCE
          ..releasedBy(arena);
        final map = registry.getMap(viewId);
        if (map == null) return false;
        map.releasedBy(arena);

        final style = map.getStyle$1();
        if (style == null) return false;
        style.releasedBy(arena);

        final sourceId = id.toJString()..releasedBy(arena);
        final source = style.getSourceAs(
          sourceId,
          T: maplibre_jni.GeoJsonSource.type,
        );
        if (source == null) return false;
        source.releasedBy(arena);

        final geoJson = data.toJString()..releasedBy(arena);
        source.setGeoJsonSync$3(geoJson);
        return true;
      });
    } catch (_) {
      return false;
    }
  }
}
