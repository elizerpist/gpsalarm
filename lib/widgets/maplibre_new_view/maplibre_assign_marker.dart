part of '../maplibre_new_view.dart';

extension _MaplibreAssignMarker on _MaplibreNewViewState {
  bool get _showAssignOverlay => _isAssigning && (_assignExisting == null || _assignNativeHidden);

  String _assignMarkerLabel() {
    if (_assignTriggerType == TriggerType.time) return '${_assignTimeMinutes}min';
    return AlarmMarkerRenderer.formatDistance(_assignRadius);
  }

  Color _assignMarkerColor() {
    if (_assignTriggerType == TriggerType.time) return Colors.orange;
    return Colors.red;
  }

  void _refreshAssignMarker() {
    if (!_showAssignOverlay) return;
    final label = _assignMarkerLabel();
    final color = _assignMarkerColor();
    final key = '$label-${color.value}-$_deviceDpr';
    if (key == _assignMarkerKey && _assignMarkerPng != null) return;
    _assignMarkerKey = key;
    _assignMarkerSize = _markerSizeCache[key] ??= AlarmMarkerRenderer.measureLogicalSize(label);
    final cached = _markerBitmapCache[key];
    if (cached != null) {
      _assignMarkerPng = cached;
      return;
    }
    final version = ++_assignMarkerVersion;
    AlarmMarkerRenderer.render(label: label, color: color, dpr: _deviceDpr).then((png) {
      if (!mounted || version != _assignMarkerVersion || _assignMarkerKey != key) return;
      _markerBitmapCache[key] = png;
      setState(() => _assignMarkerPng = png);
    });
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
