part of '../maplibre_new_view.dart';

extension _MaplibreAssignMarker on _MaplibreNewViewState {
  bool get _showAssignOverlay =>
      _isAssigning && (_assignExisting == null || _assignNativeHidden);
  bool get _showAssignMarkerOverlay => _isAssigning && _assignExisting == null;
  bool get _useNativeExistingAssignLayer =>
      _isAssigning &&
      _useNativeAssignCircle &&
      _assignExisting != null &&
      !_assignNativeHidden &&
      _assignVisualOwner == _AssignVisualOwner.nativeLive &&
      !_assignFlutterPreviewActive;

  String _assignMarkerLabel() {
    if (_assignTriggerType == TriggerType.time)
      return '${_assignTimeMinutes}min';
    return AlarmMarkerRenderer.formatDistance(_assignRadius);
  }

  Color _assignMarkerColor() {
    if (!_assignActive) return Colors.grey;
    if (_assignTriggerType == TriggerType.time) return Colors.orange;
    return Colors.red;
  }

  void _refreshAssignMarker() {
    if (!_isAssigning) return;
    this._updateAssignMarkerFromState();
  }

  Future<void> _ensureAssignMarkerBitmap() async {
    final key = this._updateAssignMarkerFromState();
    if (_assignMarkerPng != null) return;
    final label = _assignMarkerLabel();
    final color = _assignMarkerColor();
    final png = await AlarmMarkerRenderer.render(
      label: label,
      color: color,
      dpr: _deviceDpr,
    );
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
    _assignMarkerSize = _markerSizeCache[key] ??=
        AlarmMarkerRenderer.measureLogicalSize(label);
    final cached = _markerBitmapCache[key];
    if (cached != null) {
      _assignMarkerPng = cached;
      return key;
    }
    final version = ++_assignMarkerVersion;
    AlarmMarkerRenderer.render(
      label: label,
      color: color,
      dpr: _deviceDpr,
    ).then((png) {
      if (!mounted ||
          version != _assignMarkerVersion ||
          _assignMarkerKey != key)
        return;
      _markerBitmapCache[key] = png;
      setState(() => _assignMarkerPng = png);
    });
    return key;
  }

  void _syncAssignNativeMarkerChipForLiveRadius(
    StyleController style,
    _RadiusCircleData circle, {
    required String reason,
  }) {
    if (!_useNativeExistingAssignLayer) return;
    if (!_radiusVisualIds.contains(circle.id) &&
        !_radiusCircleLayerKeys.containsKey(circle.id)) {
      return;
    }

    final label = _markerLabelForCircle(circle);
    final color = _markerColorForCircle(circle);
    final imageId = _markerImageIdForCircle(circle, label, color);
    final key = '${circle.id}|$imageId';
    if (_assignLiveMarkerChipKey == key) return;
    _assignLiveMarkerChipKey = key;
    final version = ++_assignLiveMarkerChipVersion;

    unawaited(() async {
      try {
        final registeredImageId = await _ensureRadiusMarkerImage(style, circle);
        if (!mounted ||
            !_isAssigning ||
            version != _assignLiveMarkerChipVersion ||
            _assignLiveMarkerChipKey != key) {
          return;
        }
        _radiusPointImageIds[circle.id] = registeredImageId;
        await style.updateGeoJsonSource(
          id: 'radius-pt-${circle.id}',
          data: _radiusPointSourceGeoJson(circle),
        );
        if (_shouldLogAssignDebugReason(reason)) {
          DebugConsole.log(
            'ASSIGN_MARKER_CHIP_SYNC: id=${circle.id} label=$label '
            'reason=$reason r=${circle.radiusMeters.round()}m '
            '${_assignDebugState()}',
          );
        }
      } catch (error) {
        if (_assignLiveMarkerChipKey == key) _assignLiveMarkerChipKey = null;
        DebugConsole.log(
          'ASSIGN_MARKER_CHIP_SYNC: id=${circle.id} label=$label '
          'reason=$reason error=$error ${_assignDebugState()}',
        );
      }
    }());
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
