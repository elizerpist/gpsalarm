part of '../maplibre_new_view.dart';

extension _MaplibreStyleState on _MaplibreNewViewState {
  void _prepareVectorStyle(String styleUrl) {
    if (_activeStyleUrl == styleUrl) return;
    _activeStyleUrl = styleUrl;
    _registeredStyleUrl = null;
    _imagesRegistered = false;
    _radiusLayerReady = false;
    _lastRadiusDataHash = '';
    _radiusDebounce?.cancel();
    _radiusLayerVersion++;
    _styleGeneration++;
    _registeredMarkerImageKeys.clear();
    _controller = null;
  }

  Future<bool> _tryUpdateGeoJsonSource(
    StyleController style, {
    required String id,
    required String data,
  }) async {
    try {
      await style.updateGeoJsonSource(id: id, data: data);
      return true;
    } catch (_) {
      return false;
    }
  }
}
