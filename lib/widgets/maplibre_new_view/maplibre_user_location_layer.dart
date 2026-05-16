part of '../maplibre_new_view.dart';

const _userLocationSourceId = 'user-location-src';
const _userLocationGlowLayerId = 'user-location-glow';
const _userLocationDotLayerId = 'user-location-dot';

extension _MaplibreUserLocationLayer on _MaplibreNewViewState {
  Future<void> _initUserLocationLayer(StyleController style) async {
    await style.addSource(
      GeoJsonSource(id: 'user-location-src', data: _emptyGeoJson),
    );
    await _addUserLocationLayers(style);
    _userLocationLayerReady = true;
    _lastUserLocationGeoJson = '';
    DebugConsole.log(
      'USER_POS_NATIVE_LAYER_READY: source=$_userLocationSourceId',
    );
    _syncUserLocationSource(reason: 'init');
  }

  Future<void> _ensureUserLocationLayerOrder(StyleController style) async {
    if (!_userLocationLayerReady) return;
    try {
      await style.removeLayer(_userLocationDotLayerId);
    } catch (_) {}
    try {
      await style.removeLayer(_userLocationGlowLayerId);
    } catch (_) {}
    await _addUserLocationLayers(style);
  }

  Future<void> _addUserLocationLayers(StyleController style) async {
    await style.addLayer(
      _userLocationCircleLayer(
        id: _userLocationGlowLayerId,
        radius: 16.0,
        color: 'rgba(33,150,243,0.15)',
        strokeColor: 'rgba(0,0,0,0)',
        strokeWidth: 0.0,
      ),
    );
    await style.addLayer(
      _userLocationCircleLayer(
        id: _userLocationDotLayerId,
        radius: 8.0,
        color: '#2196F3',
        strokeColor: '#FFFFFF',
        strokeWidth: 3.0,
      ),
    );
  }

  CircleStyleLayer _userLocationCircleLayer({
    required String id,
    required double radius,
    required String color,
    required String strokeColor,
    required double strokeWidth,
  }) {
    return CircleStyleLayer(
      id: id,
      sourceId: 'user-location-src',
      paint: {
        'circle-radius': radius,
        'circle-color': color,
        'circle-stroke-color': strokeColor,
        'circle-stroke-width': strokeWidth,
        'circle-pitch-alignment': 'map',
        'circle-pitch-scale': 'map',
      },
    );
  }

  void _syncUserLocationSource({String reason = 'direct'}) {
    if (!_userLocationLayerReady) return;
    final style = _controller?.style;
    if (style == null) return;
    final pos = _userPos;
    final data = pos == null
        ? _emptyGeoJson
        : _pointGeoJson(pos.lng.toDouble(), pos.lat.toDouble());
    if (data == _lastUserLocationGeoJson) return;
    final previousData = _lastUserLocationGeoJson;
    _lastUserLocationGeoJson = data;
    unawaited(() async {
      final sw = Stopwatch()..start();
      try {
        await style.updateGeoJsonSource(id: _userLocationSourceId, data: data);
        sw.stop();
        DebugConsole.log(
          'USER_POS_NATIVE_SYNC: updated=true reason=$reason '
          'empty=${pos == null} is3d=$_is3D pitch=${_is3D ? 45 : 0} '
          'bytes=${data.length} ms=${sw.elapsedMilliseconds}',
        );
      } catch (e) {
        sw.stop();
        if (_lastUserLocationGeoJson == data) {
          _lastUserLocationGeoJson = previousData;
        }
        DebugConsole.log(
          'USER_POS_NATIVE_SYNC: updated=false reason=$reason '
          'empty=${pos == null} is3d=$_is3D bytes=${data.length} '
          'ms=${sw.elapsedMilliseconds} error=$e',
        );
      }
    }());
  }
}
