part of '../maplibre_new_view.dart';

extension _MaplibreAssignLifecycle on _MaplibreNewViewState {
  Future<void> _hideExistingNativeAlarm(AlarmPoint existing) async {
    _radiusDebounce?.cancel();
    final alarmProv = context.read<AlarmProvider>();
    final circles = this._buildRadiusCircles(
      alarmProv,
      excludeEditing: true,
      excludeAlarmId: existing.id,
    );
    _radiusLayerVersion++;
    _lastRadiusDataHash = this._radiusHash(circles, editingId: existing.id);
    final index = alarmProv.alarmPoints.indexWhere((p) => p.id == existing.id);
    if (index < 0) return;
    final style = _controller?.style;
    if (style == null) return;
    final id = 'alarm-$index';
    try {
      await style.removeLayer('radius-label-$id');
    } catch (_) {}
    try {
      await style.removeLayer('radius-circle-$id');
    } catch (_) {}
    style.updateGeoJsonSource(id: 'radius-pt-$id', data: _emptyGeoJson);
  }

  void _beginClosingAssignVisual({required bool keepCircle}) {
    _assignVisualClearTimer?.cancel();
    setState(() {
      _isAssigning = false;
      _closingAssignVisual = true;
      _closingAssignCircle = keepCircle;
      _assignExisting = null;
      _isDraggingRadius = false;
      _dragPointerId = null;
    });
  }

  void _finishClosingAssignCircle() {
    if (!_closingAssignCircle || !mounted) return;
    setState(() => _closingAssignCircle = false);
  }

  void _scheduleAssignVisualClear() {
    _assignVisualClearTimer?.cancel();
    _assignVisualClearTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _closingAssignVisual = false;
        _closingAssignCircle = false;
        _assignScreenCenter = null;
        _assignMarkerPng = null;
        _assignMarkerKey = null;
        _assignTriggerType = TriggerType.distance;
        _assignZoneTrigger = ZoneTrigger.onEntry;
        _assignTimeMinutes = 10;
      });
    });
  }

  Future<void> _startAssign(double lat, double lng, {AlarmPoint? existing}) async {
    _assignVisualClearTimer?.cancel();
    _closingAssignVisual = false;
    _assignScreenCenter = existing != null
        ? (this._geoToScreen(existing.latitude, existing.longitude) ?? _lastPointerDownPos)
        : _lastPointerDownPos;
    _assignExisting = existing;
    _assignLat = lat;
    _assignLng = lng;
    _assignRadius = existing?.radiusMeters ?? 500;
    _assignTriggerType = existing?.triggerType ?? TriggerType.distance;
    _assignZoneTrigger = existing?.zoneTrigger ?? ZoneTrigger.onEntry;
    _assignTimeMinutes = existing?.timeTrigger?.inMinutes ?? 10;
    _assignMarkerPng = null;
    _assignMarkerKey = null;
    if (existing != null) {
      await this._hideExistingNativeAlarm(existing);
      if (!mounted) return;
    }
    _isAssigning = true;
    _radiusNotifier.value = this._currentRadiusPx;
    this._refreshAssignMarker();
    DebugConsole.log('ASSIGN_START: lat=$lat lng=$lng existing=${existing?.id} screenCenter=$_assignScreenCenter radiusPx=${this._currentRadiusPx.toStringAsFixed(1)} radiusM=$_assignRadius');
    final style = _controller?.style;
    if (style != null) {
      DebugConsole.log('ASSIGN_START: updating veil immediately');
      this._updateVeil(style, context.read<AlarmProvider>());
    }
    setState(() {});
  }

  Future<void> _cancelAssign({bool nativeAlreadySynced = false}) async {
    DebugConsole.log('CANCEL_ASSIGN: isAssigning=$_isAssigning existing=${_assignExisting?.id}');
    final previousSuppress = _suppressRadiusSync;
    _suppressRadiusSync = true;
    _radiusDebounce?.cancel();
    _controller?.style?.updateGeoJsonSource(id: 'fast-src', data: _emptyGeoJson);
    final wasExisting = _assignExisting;
    final style = _controller?.style;
    final alarmProv = context.read<AlarmProvider>();
    final shouldRebuildNative = !nativeAlreadySynced && wasExisting != null && style != null && _radiusLayerReady;
    _beginClosingAssignVisual(keepCircle: shouldRebuildNative);

    if (shouldRebuildNative) {
      final circles = this._buildRadiusCircles(alarmProv, excludeEditing: false);
      _radiusLayerVersion++;
      await this._rebuildRadiusLayers(style, circles, _radiusLayerVersion);
      _lastRadiusDataHash = this._radiusHash(circles);
    }
    if (style != null) this._updateVeil(style, alarmProv, ignoreAssign: true);
    _finishClosingAssignCircle();

    _scheduleAssignVisualClear();
    _suppressRadiusSync = previousSuppress;
  }

  Future<void> _saveAssign(AlarmPoint alarm) async {
    DebugConsole.log('SAVE_ASSIGN: existing=${_assignExisting?.id} lat=${alarm.latitude} lng=${alarm.longitude} r=${alarm.radiusMeters.round()}m');
    _suppressRadiusSync = true;
    final alarmProv = context.read<AlarmProvider>();
    try {
      final wasExisting = _assignExisting != null;
      if (wasExisting) {
        alarmProv.updateAlarmPoint(alarm);
      } else if (alarmProv.canAddAlarm) {
        alarmProv.addAlarmPoint(alarm);
      }
      _radiusDebounce?.cancel();
      _lastRadiusDataHash = '';
      final style = _controller?.style;
      _beginClosingAssignVisual(keepCircle: style != null && _radiusLayerReady);
      if (style != null && _radiusLayerReady) {
        final circles = this._buildRadiusCircles(alarmProv, excludeEditing: false);
        _radiusLayerVersion++;
        await this._rebuildRadiusLayers(style, circles, _radiusLayerVersion);
        _lastRadiusDataHash = this._radiusHash(circles);
        this._updateVeil(style, alarmProv, ignoreAssign: true);
      }
      _finishClosingAssignCircle();
      _controller?.style?.updateGeoJsonSource(id: 'fast-src', data: _emptyGeoJson);
      _scheduleAssignVisualClear();
    } finally {
      _suppressRadiusSync = false;
    }
  }
}
