part of '../maplibre_new_view.dart';

extension _MaplibreAssignLifecycle on _MaplibreNewViewState {
  bool _alarmVisualChanged(AlarmPoint? previous, AlarmPoint next) {
    if (previous == null) return true;
    return previous.latitude != next.latitude ||
        previous.longitude != next.longitude ||
        previous.radiusMeters != next.radiusMeters ||
        previous.triggerType != next.triggerType ||
        previous.zoneTrigger != next.zoneTrigger ||
        previous.isActive != next.isActive ||
        previous.timeTrigger != next.timeTrigger;
  }

  Future<void> _activateAssignOverlay({bool updateMarker = false}) async {
    if (!_isAssigning) return;
    if (_assignOverlayActivating) return;
    _assignOverlayActivating = true;
    try {
      _radiusNotifier.value = this._currentRadiusPx;
      final existing = _assignExisting;
      final style = _controller?.style;
      final alarmProv = context.read<AlarmProvider>();
      if (_useNativeExistingAssignLayer && style != null) {
        await this._updateExistingNativeAssignLayer(
          style,
          alarmProv,
          updateMarker: updateMarker,
        );
        this._updateVeil(style, alarmProv);
        return;
      }
      var needsState = false;
      if (!_assignNativeHidden) {
        _assignNativeHidden = true;
        needsState = true;
        if (existing != null) {
          await this._hideExistingNativeAlarm(existing);
        }
      }
      if (_useNativeAssignCircle && style != null) {
        await this._updateFastCircleLayer(style);
      }
      if (style != null) this._updateVeil(style, alarmProv);
      if (needsState && mounted) setState(() {});
    } finally {
      _assignOverlayActivating = false;
    }
  }

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
    _radiusCircleLayerKeys.remove(id);
    try {
      await style.removeLayer('radius-circle-$id');
    } catch (_) {}
  }

  void _beginClosingAssignVisual({required bool keepCircle}) {
    _assignVisualClearTimer?.cancel();
    setState(() {
      _isAssigning = false;
      _closingAssignVisual = true;
      _closingAssignCircle = keepCircle;
      _assignExisting = null;
      _assignNativeAlarmLayerId = null;
      _assignNativeHidden = false;
      _isDraggingRadius = false;
      _dragPointerId = null;
    });
  }

  void _finishClosingAssignCircle() {
    if (!_closingAssignCircle || !mounted) return;
    setState(() => _closingAssignCircle = false);
  }

  void _scheduleAssignVisualClear([
    Duration delay = const Duration(milliseconds: 80),
  ]) {
    _assignVisualClearTimer?.cancel();
    _assignVisualClearTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _closingAssignVisual = false;
        _closingAssignCircle = false;
        _assignScreenCenter = null;
        _assignMarkerPng = null;
        _assignMarkerKey = null;
        _assignNativeAlarmLayerId = null;
        _assignNativeHidden = false;
        _assignTriggerType = TriggerType.distance;
        _assignZoneTrigger = ZoneTrigger.onEntry;
        _assignTimeMinutes = 10;
        _assignActive = true;
      });
      _restoreCompassAfterAssign();
    });
  }

  Future<void> _startAssign(
    double lat,
    double lng, {
    AlarmPoint? existing,
  }) async {
    _assignVisualClearTimer?.cancel();
    _suspendCompassForAssign();
    _closingAssignVisual = false;
    _assignScreenCenter = existing != null
        ? (this._geoToScreen(existing.latitude, existing.longitude) ??
              _lastPointerDownPos)
        : _lastPointerDownPos;
    _assignExisting = existing;
    _assignLat = lat;
    _assignLng = lng;
    _assignRadius = existing?.radiusMeters ?? 500;
    _assignTriggerType = existing?.triggerType ?? TriggerType.distance;
    _assignZoneTrigger = existing?.zoneTrigger ?? ZoneTrigger.onEntry;
    _assignTimeMinutes = existing?.timeTrigger?.inMinutes ?? 10;
    _assignActive = existing?.isActive ?? true;
    _assignMarkerPng = null;
    _assignMarkerKey = null;
    _assignNativeAlarmLayerId = existing == null
        ? null
        : this._alarmLayerId(context.read<AlarmProvider>(), existing.id);
    _assignNativeHidden = existing == null;
    _isAssigning = true;
    _radiusNotifier.value = this._currentRadiusPx;
    this._refreshAssignMarker();
    DebugConsole.log(
      'ASSIGN_START: lat=$lat lng=$lng existing=${existing?.id} screenCenter=$_assignScreenCenter radiusPx=${this._currentRadiusPx.toStringAsFixed(1)} radiusM=$_assignRadius',
    );
    final style = _controller?.style;
    if (style != null && _showAssignOverlay) {
      if (_useNativeAssignCircle) await this._updateFastCircleLayer(style);
      DebugConsole.log('ASSIGN_START: updating veil immediately');
      this._updateVeil(style, context.read<AlarmProvider>());
    } else if (existing != null) {
      DebugConsole.log('ASSIGN_START: keeping native alarm visual during edit');
    }
    setState(() {});
  }

  Future<void> _cancelAssign({bool nativeAlreadySynced = false}) async {
    DebugConsole.log(
      'CANCEL_ASSIGN: isAssigning=$_isAssigning existing=${_assignExisting?.id}',
    );
    final previousSuppress = _suppressRadiusSync;
    _suppressRadiusSync = true;
    _radiusDebounce?.cancel();
    final wasExisting = _assignExisting;
    final nativeWasHidden = _assignNativeHidden;
    final style = _controller?.style;
    final alarmProv = context.read<AlarmProvider>();
    final canRestoreInPlace =
        !nativeAlreadySynced &&
        _useNativeAssignCircle &&
        !nativeWasHidden &&
        wasExisting != null &&
        style != null &&
        _radiusLayerReady;
    if (canRestoreInPlace) {
      final liveStyle = style!;
      final circles = this._buildRadiusCircles(
        alarmProv,
        excludeEditing: false,
      );
      final circle = this._circleForAlarmId(
        alarmProv,
        wasExisting!.id,
        circles: circles,
      );
      if (circle != null) {
        await this._updateRadiusCircleSources(
          liveStyle,
          circle,
          updateMarker: true,
        );
      } else if (_assignNativeAlarmLayerId != null) {
        await this._removeRadiusVisual(
          liveStyle,
          _assignNativeAlarmLayerId!,
          clearSources: true,
        );
      }
      _lastRadiusDataHash = this._radiusHash(circles);
      this._updateVeil(liveStyle, alarmProv, ignoreAssign: true);
      await this._clearFastCircleLayer(liveStyle);
      _beginClosingAssignVisual(keepCircle: false);
      _scheduleAssignVisualClear();
      _suppressRadiusSync = previousSuppress;
      return;
    }
    final shouldRebuildNative =
        !nativeAlreadySynced &&
        nativeWasHidden &&
        wasExisting != null &&
        style != null &&
        _radiusLayerReady;
    _beginClosingAssignVisual(
      keepCircle: shouldRebuildNative && !_useNativeAssignCircle,
    );

    if (shouldRebuildNative) {
      final liveStyle = style!;
      final circles = this._buildRadiusCircles(
        alarmProv,
        excludeEditing: false,
      );
      _radiusLayerVersion++;
      _RadiusCircleData? circle;
      if (wasExisting != null) {
        final index = alarmProv.alarmPoints.indexWhere(
          (p) => p.id == wasExisting.id,
        );
        final id = 'alarm-$index';
        for (final c in circles) {
          if (c.id == id) {
            circle = c;
            break;
          }
        }
      }
      if (circle != null) {
        await this._upsertRadiusVisual(liveStyle, circle);
      } else {
        await this._rebuildRadiusLayers(
          liveStyle,
          circles,
          _radiusLayerVersion,
        );
      }
      _lastRadiusDataHash = this._radiusHash(circles);
    }
    if (style != null && nativeWasHidden)
      this._updateVeil(style, alarmProv, ignoreAssign: true);
    if (style != null) await this._clearFastCircleLayer(style);
    _finishClosingAssignCircle();

    _scheduleAssignVisualClear();
    _suppressRadiusSync = previousSuppress;
  }

  Future<void> _saveAssign(AlarmPoint alarm) async {
    _assignActive = alarm.isActive;
    final effectiveAlarm = AlarmPoint(
      id: alarm.id,
      name: alarm.name,
      latitude: _assignLat,
      longitude: _assignLng,
      radiusMeters: _assignTriggerType == TriggerType.distance
          ? _assignRadius
          : 0,
      triggerType: _assignTriggerType,
      zoneTrigger: _assignZoneTrigger,
      isActive: alarm.isActive,
      timeTrigger: _assignTriggerType == TriggerType.time
          ? Duration(minutes: _assignTimeMinutes)
          : null,
      customAlarmSound:
          _assignExisting?.customAlarmSound ?? alarm.customAlarmSound,
      customAlarmType:
          _assignExisting?.customAlarmType ?? alarm.customAlarmType,
      createdAt: _assignExisting?.createdAt ?? alarm.createdAt,
    );
    DebugConsole.log(
      'SAVE_ASSIGN: existing=${_assignExisting?.id} lat=${effectiveAlarm.latitude} lng=${effectiveAlarm.longitude} r=${effectiveAlarm.radiusMeters.round()}m',
    );
    _suppressRadiusSync = true;
    final alarmProv = context.read<AlarmProvider>();
    try {
      final wasExisting = _assignExisting != null;
      final nativeWasHidden = _assignNativeHidden;
      final visualChanged = _alarmVisualChanged(
        _assignExisting,
        effectiveAlarm,
      );
      if (wasExisting) {
        alarmProv.updateAlarmPoint(effectiveAlarm);
      } else if (alarmProv.canAddAlarm) {
        alarmProv.addAlarmPoint(effectiveAlarm);
      }
      _seedAlarmInsideState(effectiveAlarm);
      _radiusDebounce?.cancel();
      final style = _controller?.style;
      final canUpdateInPlace =
          wasExisting && !nativeWasHidden && style != null && _radiusLayerReady;
      if (canUpdateInPlace) {
        final liveStyle = style!;
        final circles = this._buildRadiusCircles(
          alarmProv,
          excludeEditing: false,
        );
        final circle = this._circleForAlarmId(
          alarmProv,
          effectiveAlarm.id,
          circles: circles,
        );
        if (circle != null) {
          await this._updateRadiusCircleSources(
            liveStyle,
            circle,
            updateMarker: true,
          );
        }
        _lastRadiusDataHash = this._radiusHash(circles);
        this._updateVeil(liveStyle, alarmProv, ignoreAssign: true);
        await this._clearFastCircleLayer(liveStyle);
        _beginClosingAssignVisual(keepCircle: false);
        _scheduleAssignVisualClear();
        return;
      }
      final shouldRebuildNative =
          style != null &&
          _radiusLayerReady &&
          (!wasExisting || nativeWasHidden || visualChanged);
      if (shouldRebuildNative) _lastRadiusDataHash = '';
      if (shouldRebuildNative) await this._ensureAssignMarkerBitmap();
      if (shouldRebuildNative) {
        final liveStyle = style!;
        final circles = this._buildRadiusCircles(
          alarmProv,
          excludeEditing: false,
        );
        _radiusLayerVersion++;
        final singleCircle = !wasExisting
            ? this._circleForAlarmId(
                alarmProv,
                effectiveAlarm.id,
                circles: circles,
              )
            : null;
        if (_useNativeAssignCircle && singleCircle != null) {
          // Atomic swap: remove fast-circle BEFORE adding permanent (prevents duplication)
          await this._clearFastCircleLayer(liveStyle);
          await this._upsertRadiusVisual(liveStyle, singleCircle);
        } else {
          await this._rebuildRadiusLayers(
            liveStyle,
            circles,
            _radiusLayerVersion,
          );
        }
        _lastRadiusDataHash = this._radiusHash(circles);
        this._updateVeil(liveStyle, alarmProv, ignoreAssign: true);
      }
      // Hide overlay AFTER native layers are ready (prevents flash)
      _beginClosingAssignVisual(keepCircle: false);
      _finishClosingAssignCircle();
      if (style != null) {
        await this._clearFastCircleLayer(style);
      }
      _scheduleAssignVisualClear(
        !wasExisting && _useNativeAssignCircle
            ? const Duration(milliseconds: 500)
            : const Duration(milliseconds: 80),
      );
    } finally {
      _suppressRadiusSync = false;
    }
  }
}
