part of '../maplibre_new_view.dart';

extension _MaplibreAssignLifecycle on _MaplibreNewViewState {
  void _cancelAssignDragUpdateTimers() {
    _assignNativeUpdateTimer?.cancel();
    _assignNativeUpdateTimer = null;
    _assignCardSyncTimer?.cancel();
    _assignCardSyncTimer = null;
    _assignNativeUpdatePending = false;
    _assignNativeUpdateMarkerPending = false;
  }

  void _scheduleAssignNativeOverlayUpdate({bool updateMarker = false}) {
    if (!_isAssigning) return;
    if (!_useNativeAssignCircle &&
        _isDraggingRadius &&
        _assignZoneTrigger != ZoneTrigger.onLeave) {
      return;
    }
    _assignNativeUpdatePending = true;
    _assignNativeUpdateMarkerPending =
        _assignNativeUpdateMarkerPending || updateMarker;
    if (_assignNativeUpdateRunning || _assignNativeUpdateTimer != null) return;
    _assignNativeUpdateTimer = Timer(const Duration(milliseconds: 16), () {
      _assignNativeUpdateTimer = null;
      final future = _flushAssignNativeOverlayUpdate();
      _assignNativeUpdateFuture = future;
      unawaited(
        future.whenComplete(() {
          if (_assignNativeUpdateFuture == future) {
            _assignNativeUpdateFuture = null;
          }
        }),
      );
    });
  }

  Future<void> _waitForAssignNativeUpdate() async {
    final future = _assignNativeUpdateFuture;
    if (future == null) return;
    try {
      await future;
    } catch (_) {}
  }

  Future<void> _drainAssignNativeUpdate() async {
    while (true) {
      _assignNativeUpdateTimer?.cancel();
      _assignNativeUpdateTimer = null;
      final running = _assignNativeUpdateFuture;
      if (running != null) {
        try {
          await running;
        } catch (_) {}
        continue;
      }
      if (!_assignNativeUpdatePending) return;
      final future = _flushAssignNativeOverlayUpdate();
      _assignNativeUpdateFuture = future;
      try {
        await future;
      } catch (_) {
        // Ignore stale native sync failures while closing or saving.
      } finally {
        if (_assignNativeUpdateFuture == future) {
          _assignNativeUpdateFuture = null;
        }
      }
    }
  }

  Future<void> _flushAssignNativeOverlayUpdate() async {
    if (!_isAssigning) {
      _assignNativeUpdatePending = false;
      _assignNativeUpdateMarkerPending = false;
      return;
    }
    if (_assignNativeUpdateRunning) return;
    if (!_assignNativeUpdatePending) return;
    _assignNativeUpdatePending = false;
    final updateMarker = _assignNativeUpdateMarkerPending;
    _assignNativeUpdateMarkerPending = false;
    _assignNativeUpdateRunning = true;
    final sw = Stopwatch()..start();
    try {
      if (_useNativeAssignCircle) {
        await this._activateAssignOverlay(updateMarker: updateMarker);
      } else {
        await this._syncAssignVeilOnly();
      }
    } finally {
      sw.stop();
      DebugConsole.log(
        'VECTOR_NATIVE_SYNC: ${sw.elapsedMilliseconds}ms marker=$updateMarker handoff=$_handoffToNative',
      );
      _assignNativeUpdateRunning = false;
      // End handoff: native is ready, kill overlay after 1 frame
      if (_handoffToNative && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _handoffToNative = false);
        });
      }
      if (_assignNativeUpdatePending && _isAssigning) {
        this._scheduleAssignNativeOverlayUpdate(
          updateMarker: _assignNativeUpdateMarkerPending,
        );
      }
    }
  }

  Future<bool> _syncAssignNativePreview({bool updateMarker = false}) async {
    if (!_isAssigning || !_radiusLayerReady) return false;
    final style = _controller?.style;
    if (style == null) return false;
    final alarmProv = context.read<AlarmProvider>();
    final circle = this._currentAssignPreviewCircle(alarmProv);
    if (circle == null) return false;
    final removal = _assignNativePreviewRemovalFuture;
    if (removal != null) {
      try {
        await removal;
      } catch (_) {}
      if (_assignNativePreviewRemovalFuture == removal) {
        _assignNativePreviewRemovalFuture = null;
      }
    }
    final sw = Stopwatch()..start();
    await this._upsertRadiusVisual(
      style,
      circle,
      updateMarker: updateMarker,
    );
    this._updateVeil(style, alarmProv);
    sw.stop();
    DebugConsole.log(
      'ASSIGN_NATIVE_PREVIEW: ${sw.elapsedMilliseconds}ms id=${circle.id} r=${circle.radiusMeters.round()}m marker=$updateMarker',
    );
    if (mounted && !_assignNativePreviewReady) {
      setState(() => _assignNativePreviewReady = true);
    } else {
      _assignNativePreviewReady = true;
    }
    return true;
  }

  Future<void> _syncAssignVeilOnly() async {
    if (!_isAssigning) return;
    final style = _controller?.style;
    if (style == null) return;
    this._updateVeil(style, context.read<AlarmProvider>());
  }

  void _markAssignNativePreviewDirty({bool removeVisual = true}) {
    if (!_assignNativePreviewReady) return;
    _assignNativePreviewReady = false;
    if (removeVisual) {
      final removal = _removeAssignNativePreviewVisual();
      _assignNativePreviewRemovalFuture = removal;
      unawaited(
        removal.whenComplete(() {
          if (_assignNativePreviewRemovalFuture == removal) {
            _assignNativePreviewRemovalFuture = null;
          }
        }),
      );
    }
  }

  Future<void> _removeAssignNativePreviewVisual() async {
    final style = _controller?.style;
    final id = _assignNativeAlarmLayerId;
    if (style == null || id == null) return;
    await this._removeRadiusVisual(style, id, clearSources: false);
    this._updateVeil(style, context.read<AlarmProvider>());
  }

  void _scheduleAssignCardSync() {
    if (!_isAssigning) return;
    if (_assignCardSyncTimer != null) return;
    _assignCardSyncTimer = Timer(const Duration(milliseconds: 80), () {
      _assignCardSyncTimer = null;
      this._flushAssignCardSync();
    });
  }

  void _flushAssignCardSync() {
    _assignCardSyncTimer?.cancel();
    _assignCardSyncTimer = null;
    if (!mounted || !_isAssigning) return;
    final sw = Stopwatch()..start();
    // Skip expensive bitmap render during drag — only update card text via setState
    if (!_isDraggingRadius) this._refreshAssignMarker();
    setState(() {});
    sw.stop();
    if (sw.elapsedMilliseconds > 5) {
      DebugConsole.log(
        'VECTOR_CARD_SYNC: ${sw.elapsedMilliseconds}ms (marker+setState)',
      );
    }
  }

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
    // Overlay-only fallback skips native work while dragging. Native assign mode
    // keeps the final alarm-N layer alive and updates only its source radiusPx.
    if (_isDraggingRadius && !_useNativeAssignCircle) return;
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
    if (!_useNativeAssignCircle) {
      await this._removeRadiusVisual(style, id, clearSources: false);
      return;
    }
    _radiusCircleLayerKeys.remove(id);
    try {
      await style.removeLayer('radius-circle-$id');
    } catch (_) {}
  }

  void _beginClosingAssignVisual({
    required bool keepCircle,
    bool forceKeepVisual = false,
  }) {
    _assignVisualClearTimer?.cancel();
    _cancelAssignDragUpdateTimers();
    final keepOverlayUntilClear = forceKeepVisual || !_assignNativePreviewReady;
    setState(() {
      _isAssigning = false;
      _handoffToNative = false;
      _closingAssignVisual = keepOverlayUntilClear;
      _closingAssignCircle = keepCircle && keepOverlayUntilClear;
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
        _assignNativePreviewReady = false;
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
    final alarmProv = context.read<AlarmProvider>();
    _cancelAssignDragUpdateTimers();
    await _waitForAssignNativeUpdate();
    final previewRemoval = _assignNativePreviewRemovalFuture;
    if (previewRemoval != null) {
      try {
        await previewRemoval;
      } catch (_) {}
      if (_assignNativePreviewRemovalFuture == previewRemoval) {
        _assignNativePreviewRemovalFuture = null;
      }
    }
    _assignVisualClearTimer?.cancel();
    _suspendCompassForAssign();
    _closingAssignVisual = false;
    _handoffToNative = false;
    _assignNativePreviewReady = false;
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
        ? 'alarm-${alarmProv.alarmPoints.length}'
        : this._alarmLayerId(alarmProv, existing.id);
    _assignNativeHidden = existing == null || !_useNativeAssignCircle;
    _isAssigning = true;
    _radiusNotifier.value = this._currentRadiusPx;
    if (existing != null && _assignNativeHidden && !_useNativeAssignCircle) {
      await this._ensureAssignMarkerBitmap();
    } else {
      this._refreshAssignMarker();
    }
    DebugConsole.log(
      'ASSIGN_START: lat=$lat lng=$lng existing=${existing?.id} screenCenter=$_assignScreenCenter radiusPx=${this._currentRadiusPx.toStringAsFixed(1)} radiusM=$_assignRadius',
    );
    final style = _controller?.style;
    if (style != null && _showAssignOverlay) {
      if (existing != null && _assignNativeHidden) {
        await this._hideExistingNativeAlarm(existing);
      }
      // Native mode keeps the final alarm-N draft circle alive even during
      // long-press drag; overlay-only fallback waits until drag ends.
      if (_useNativeAssignCircle) {
        if (_isDraggingRadius) {
          this._scheduleAssignNativeOverlayUpdate();
        } else {
          await this._updateFastCircleLayer(style);
        }
      }
      DebugConsole.log(
        'ASSIGN_START: updating veil immediately isDragging=$_isDraggingRadius',
      );
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
    final alarmProv = context.read<AlarmProvider>();
    _cancelAssignDragUpdateTimers();
    await _waitForAssignNativeUpdate();
    final previousSuppress = _suppressRadiusSync;
    _suppressRadiusSync = true;
    _radiusDebounce?.cancel();
    final wasExisting = _assignExisting;
    final nativeWasHidden = _assignNativeHidden;
    final style = _controller?.style;
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
    if (wasExisting == null &&
        style != null &&
        _assignNativeAlarmLayerId != null) {
      await this._removeRadiusVisual(
        style,
        _assignNativeAlarmLayerId!,
        clearSources: true,
      );
    }

    final previewWasReady = _assignNativePreviewReady;
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
        await this._upsertRadiusVisual(liveStyle, circle, updateMarker: true);
        _assignNativePreviewReady = true;
      } else {
        await this._rebuildRadiusLayers(
          liveStyle,
          circles,
          _radiusLayerVersion,
        );
        _assignNativePreviewReady = true;
      }
      _lastRadiusDataHash = this._radiusHash(circles);
    }
    if (style != null && nativeWasHidden)
      this._updateVeil(style, alarmProv, ignoreAssign: true);
    if (style != null) await this._clearFastCircleLayer(style);
    final keepOverlayForCancel = shouldRebuildNative && !previewWasReady;
    _beginClosingAssignVisual(
      keepCircle: keepOverlayForCancel,
      forceKeepVisual: keepOverlayForCancel,
    );

    _scheduleAssignVisualClear(
      keepOverlayForCancel
          ? const Duration(milliseconds: 300)
          : const Duration(milliseconds: 80),
    );
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
    final alarmProv = context.read<AlarmProvider>();
    await _drainAssignNativeUpdate();
    _cancelAssignDragUpdateTimers();
    _suppressRadiusSync = true;
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
        _assignNativePreviewReady = true;
        _beginClosingAssignVisual(keepCircle: false);
        _scheduleAssignVisualClear();
        return;
      }
      final shouldRebuildNative =
          style != null &&
          _radiusLayerReady &&
          (!wasExisting || nativeWasHidden || visualChanged);
      DebugConsole.log(
        'SAVE_FLOW: shouldRebuild=$shouldRebuildNative wasExisting=$wasExisting nativeHidden=$nativeWasHidden visualChanged=$visualChanged useNativeCircle=$_useNativeAssignCircle',
      );
      if (shouldRebuildNative) _lastRadiusDataHash = '';
      if (shouldRebuildNative) await this._ensureAssignMarkerBitmap();
      final previewWasReady = _assignNativePreviewReady;
      if (shouldRebuildNative) {
        final liveStyle = style!;
        final circles = this._buildRadiusCircles(
          alarmProv,
          excludeEditing: false,
        );
        _radiusLayerVersion++;
        final singleCircle = this._circleForAlarmId(
          alarmProv,
          effectiveAlarm.id,
          circles: circles,
        );
        DebugConsole.log(
          'SAVE_FLOW: singleCircle=${singleCircle?.id} circles=${circles.length}',
        );
        if (_useNativeAssignCircle && singleCircle != null) {
          DebugConsole.log('SAVE_FLOW: promote draft layer');
          await this._promoteDraftRadiusCircleLayer(liveStyle, singleCircle);
          _assignNativePreviewReady = true;
          _lastRadiusDataHash = this._radiusHash(circles);
        } else if (singleCircle != null) {
          DebugConsole.log('SAVE_FLOW: upsert single circle');
          await this._upsertRadiusVisual(
            liveStyle,
            singleCircle,
            updateMarker: true,
          );
          _assignNativePreviewReady = true;
          _lastRadiusDataHash = this._radiusHash(circles);
        } else {
          DebugConsole.log('SAVE_FLOW: full rebuildRadiusLayers');
          await this._rebuildRadiusLayers(
            liveStyle,
            circles,
            _radiusLayerVersion,
          );
          _assignNativePreviewReady = true;
          _lastRadiusDataHash = this._radiusHash(circles);
        }
        DebugConsole.log('SAVE_FLOW: updateVeil ignoreAssign=true');
        this._updateVeil(liveStyle, alarmProv, ignoreAssign: true);
      }
      final keepOverlayForHandoff = shouldRebuildNative && !previewWasReady;
      DebugConsole.log(
        'SAVE_FLOW: beginClosingAssignVisual keepCircle=$keepOverlayForHandoff forceKeep=$keepOverlayForHandoff previewWasReady=$previewWasReady',
      );
      _beginClosingAssignVisual(
        keepCircle: keepOverlayForHandoff,
        forceKeepVisual: keepOverlayForHandoff,
      );
      final clearDelay = keepOverlayForHandoff
          ? const Duration(milliseconds: 300)
          : const Duration(milliseconds: 80);
      DebugConsole.log(
        'SAVE_FLOW: scheduleAssignVisualClear ${clearDelay.inMilliseconds}ms',
      );
      _scheduleAssignVisualClear(clearDelay);
    } finally {
      _suppressRadiusSync = false;
    }
  }
}
