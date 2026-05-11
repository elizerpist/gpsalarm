part of '../maplibre_new_view.dart';

extension _MaplibreRadiusSync on _MaplibreNewViewState {
  void _syncRadiusSource(AlarmProvider alarmProv) {
    if (_suppressRadiusSync) return;
    if (!_radiusLayerReady) return;
    final style = _controller?.style;
    if (style == null) return;

    _fastCircleDebounce?.cancel();
    if (_fastCircleVersion > 0) {
      _fastCircleVersion = 0;
      _fastCircleUpdating = false;
      try {
        style.removeLayer('fast-circle');
      } catch (_) {}
      style.updateGeoJsonSource(id: 'fast-src', data: _emptyGeoJson);
    }

    this._updateVeil(style, alarmProv);

    if (_isDraggingRadius) return;

    final alarmCircles = this._buildRadiusCircles(alarmProv, excludeEditing: true);
    final fullHash = this._radiusHash(
      alarmCircles,
      editingId: _isAssigning && _assignNativeHidden && _assignExisting != null ? _assignExisting!.id : null,
    );
    if (fullHash == _lastRadiusDataHash) return;
    _lastRadiusDataHash = fullHash;

    _radiusLayerVersion++;
    final v = _radiusLayerVersion;
    _radiusDebounce?.cancel();
    _radiusDebounce = Timer(const Duration(milliseconds: 200), () {
      if (v == _radiusLayerVersion) {
        this._rebuildRadiusLayers(style, alarmCircles, v);
      }
    });
  }
}
