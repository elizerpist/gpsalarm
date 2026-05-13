part of '../maplibre_new_view.dart';

extension _MaplibreAssignMarker on _MaplibreNewViewState {
  bool get _showAssignOverlay => _isAssigning && (_assignExisting == null || _assignNativeHidden);
  bool get _showAssignMarkerOverlay =>
      _isAssigning &&
      (_assignExisting == null || _assignNativeHidden) &&
      !_assignNativePreviewReady;
  bool get _useNativeExistingAssignLayer =>
      _isAssigning && _useNativeAssignCircle && _assignExisting != null && !_assignNativeHidden;

  String _assignMarkerLabel() {
    if (_assignTriggerType == TriggerType.time) return '${_assignTimeMinutes}min';
    return AlarmMarkerRenderer.formatDistance(_assignRadius);
  }

  Color _assignMarkerColor() {
    if (!_assignActive) return Colors.grey;
    if (_assignTriggerType == TriggerType.time) return Colors.orange;
    return Colors.red;
  }

  void _refreshAssignMarker() {
    if (!_showAssignMarkerOverlay) return;
    this._updateAssignMarkerFromState();
  }

  Future<void> _ensureAssignMarkerBitmap() async {
    final key = this._updateAssignMarkerFromState();
    if (_assignMarkerPng != null) return;
    final label = _assignMarkerLabel();
    final color = _assignMarkerColor();
    final png = await AlarmMarkerRenderer.render(label: label, color: color, dpr: _deviceDpr);
    _markerBitmapCache[key] = png;
    if (mounted && _assignMarkerKey == key) {
      _assignMarkerPng = png;
    }
  }

  String _updateAssignMarkerFromState() {
    final label = _assignMarkerLabel();
    final color = _assignMarkerColor();
    final key = '$label-${color.value}-$_deviceDpr';
    if (key == _assignMarkerKey && _assignMarkerPng != null) return key;
    _assignMarkerKey = key;
    _assignMarkerSize = _markerSizeCache[key] ??= AlarmMarkerRenderer.measureLogicalSize(label);
    final cached = _markerBitmapCache[key];
    if (cached != null) {
      _assignMarkerPng = cached;
      return key;
    }
    final version = ++_assignMarkerVersion;
    final renderSw = Stopwatch()..start();
    AlarmMarkerRenderer.render(label: label, color: color, dpr: _deviceDpr).then((png) {
      renderSw.stop();
      DebugConsole.log('VECTOR_MARKER_RENDER: ${renderSw.elapsedMilliseconds}ms label=$label cached=false');
      if (!mounted || version != _assignMarkerVersion || _assignMarkerKey != key) return;
      _markerBitmapCache[key] = png;
      setState(() => _assignMarkerPng = png);
    });
    return key;
  }

  double get _currentRadiusPx {
    final isTime = _assignTriggerType == TriggerType.time;
    double radius = _assignRadius;
    if (isTime) {
      radius = math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60);
    }
    final actualZoom = _controller?.camera?.zoom ?? _currentZoom;
    return radius / _vectorMetersPerPx(_assignLat, actualZoom);
  }
}
