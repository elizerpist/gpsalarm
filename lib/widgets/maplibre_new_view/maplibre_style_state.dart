part of '../maplibre_new_view.dart';

typedef _GeoJsonSourceUpdateResult = ({
  bool updated,
  String path,
  int? viewId,
  Object? error,
});

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
    _assignNativeLiveVeilActive = false;
    _nativeLiveExitVeilSourceKey = null;
    _radiusDebounce?.cancel();
    _veilSyncTimer?.cancel();
    _veilSyncTimer = null;
    _veilSyncRequested = false;
    _veilSyncRequestedIgnoreAssign = false;
    _veilSyncRequestedFullQuality = false;
    _veilSyncRequestedReason = null;
    _assignRadiusPaintSyncPending = false;
    _assignRadiusPaintSyncReason = null;
    _assignLiveMarkerChipKey = null;
    _assignLiveMarkerChipVersion++;
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
    String reason = 'direct',
  }) async {
    final isVeilSource =
        id == 'veil-src' ||
        id == 'veil-live-outline-src' ||
        id == 'veil-live-annulus-src';
    final sw = Stopwatch()..start();
    if (isVeilSource) {
      final syncResult = _tryUpdateGeoJsonSourceSyncAndroid(id: id, data: data);
      if (syncResult.updated) {
        sw.stop();
        _logGeoJsonSourceUpdate(
          id: id,
          dataLength: data.length,
          reason: reason,
          result: syncResult,
          elapsedMs: sw.elapsedMilliseconds,
        );
        return true;
      }
    }

    late final _GeoJsonSourceUpdateResult result;
    try {
      await style.updateGeoJsonSource(id: id, data: data);
      result = (
        updated: true,
        path: isVeilSource ? 'fallback-async' : 'maplibre-async',
        viewId: null,
        error: null,
      );
    } catch (error) {
      result = (
        updated: false,
        path: isVeilSource ? 'fallback-error' : 'maplibre-error',
        viewId: null,
        error: error,
      );
    }
    sw.stop();
    _logGeoJsonSourceUpdate(
      id: id,
      dataLength: data.length,
      reason: reason,
      result: result,
      elapsedMs: sw.elapsedMilliseconds,
    );
    return result.updated;
  }

  void _logGeoJsonSourceUpdate({
    required String id,
    required int dataLength,
    required String reason,
    required _GeoJsonSourceUpdateResult result,
    required int elapsedMs,
  }) {
    if (id != 'veil-src' &&
        id != 'veil-live-outline-src' &&
        id != 'veil-live-annulus-src') {
      return;
    }
    final shouldLog = _isAssigning || elapsedMs > 4 || !result.updated;
    if (!shouldLog) return;
    final viewId = result.viewId?.toString() ?? 'n/a';
    final error = result.error == null ? 'none' : result.error.runtimeType;
    DebugConsole.log(
      'VEIL_SOURCE_UPDATE: id=$id path=${result.path} '
      'path=android-sync/${result.path.startsWith("android-sync")} '
      'updated=${result.updated} viewId=$viewId bytes=$dataLength '
      'ms=$elapsedMs reason=$reason error=$error ${_assignDebugState()}',
    );
  }

  _GeoJsonSourceUpdateResult _syncMiss(String path) {
    return (updated: false, path: path, viewId: null, error: null);
  }

  _GeoJsonSourceUpdateResult _syncHit(String path, int viewId) {
    return (updated: true, path: path, viewId: viewId, error: null);
  }

  _GeoJsonSourceUpdateResult _tryUpdateGeoJsonSourceSyncAndroid({
    required String id,
    required String data,
  }) {
    if (foundation.defaultTargetPlatform != foundation.TargetPlatform.android) {
      return _syncMiss('not-android');
    }

    final cachedViewId = _androidGeoJsonSyncViewId;
    if (cachedViewId != null &&
        _tryUpdateGeoJsonSourceSyncAndroidView(
          viewId: cachedViewId,
          id: id,
          data: data,
        )) {
      return _syncHit('android-sync-cached', cachedViewId);
    }

    for (var viewId = 63; viewId >= 0; viewId--) {
      if (viewId == cachedViewId) continue;
      if (_tryUpdateGeoJsonSourceSyncAndroidView(
        viewId: viewId,
        id: id,
        data: data,
      )) {
        _androidGeoJsonSyncViewId = viewId;
        return _syncHit('android-sync-scan', viewId);
      }
    }

    _androidGeoJsonSyncViewId = null;
    return _syncMiss('android-sync-miss');
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
