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

  Future<void> _activateAssignOverlay({
    bool updateMarker = false,
    bool radiusOnly = false,
    bool forceNative = false,
    String debugReason = 'unspecified',
  }) async {
    final seq = ++_assignSyncSeq;
    if (!_isAssigning) {
      DebugConsole.log(
        'ASSIGN_SYNC_DROP: seq=$seq reason=$debugReason notAssigning',
      );
      return;
    }
    if (_assignOverlayActivating) {
      _assignSyncSkipCount++;
      final pendingRadiusOnly = radiusOnly && !updateMarker;
      if (!_assignOverlayPending) {
        _assignOverlayPendingRadiusOnly = pendingRadiusOnly;
      } else {
        _assignOverlayPendingRadiusOnly =
            _assignOverlayPendingRadiusOnly && pendingRadiusOnly;
      }
      _assignOverlayPending = true;
      _assignOverlayPendingMarker |= updateMarker;
      _assignOverlayPendingReason = debugReason;
      if (_assignSyncSkipCount <= 5 || _assignSyncSkipCount % 15 == 0) {
        DebugConsole.log(
          'ASSIGN_SYNC_QUEUE: seq=$seq reason=$debugReason '
          'skips=$_assignSyncSkipCount ${_assignDebugState()}',
        );
      }
      return;
    }
    _assignOverlayActivating = true;
    final sw = Stopwatch()..start();
    var path = 'overlay';
    try {
      _radiusNotifier.value = this._currentRadiusPx;
      final existing = _assignExisting;
      final style = _controller?.style;
      final alarmProv = context.read<AlarmProvider>();
      if (_assignFlutterPreviewActive && !forceNative) {
        path = 'flutter-preview';
        return;
      }
      if (_useNativeExistingAssignLayer && style != null) {
        path = 'existing-native';
        await this._updateExistingNativeAssignLayer(
          style,
          alarmProv,
          updateMarker: updateMarker,
          radiusOnly: radiusOnly && !updateMarker,
        );
        await this._syncAssignVeilWithOverlay(debugReason: debugReason);
        return;
      }
      var needsState = false;
      if (!_assignNativeHidden) {
        path = 'hide-native-overlay';
        _assignNativeHidden = true;
        needsState = true;
        if (existing != null) {
          await this._hideExistingNativeAlarm(existing);
        }
      }
      if (_useNativeAssignCircle && style != null) {
        path = 'fast-native';
        await this._updateFastCircleLayer(
          style,
          radiusOnly: radiusOnly && !updateMarker,
        );
      }
      if (style != null) {
        await this._syncAssignVeilWithOverlay(debugReason: debugReason);
      }
      if (needsState && mounted) setState(() {});
    } finally {
      sw.stop();
      if (_shouldLogAssignFrame(seq) || sw.elapsedMilliseconds > 12) {
        DebugConsole.log(
          'ASSIGN_SYNC_DONE: seq=$seq reason=$debugReason path=$path '
          'ms=${sw.elapsedMilliseconds} marker=$updateMarker '
          '${_assignDebugState()}',
        );
      }
      _assignOverlayActivating = false;
      final runPending = _assignOverlayPending && mounted && _isAssigning;
      final pendingMarker = _assignOverlayPendingMarker;
      final pendingRadiusOnly = _assignOverlayPendingRadiusOnly;
      final pendingReason = _assignOverlayPendingReason ?? 'pending';
      _assignOverlayPending = false;
      _assignOverlayPendingMarker = false;
      _assignOverlayPendingRadiusOnly = false;
      _assignOverlayPendingReason = null;
      if (runPending) {
        scheduleMicrotask(() {
          if (!mounted || !_isAssigning) return;
          unawaited(
            this._activateAssignOverlay(
              updateMarker: pendingMarker,
              radiusOnly: pendingRadiusOnly && !pendingMarker,
              debugReason: 'queued:$pendingReason',
            ),
          );
        });
      }
    }
  }

  void _scheduleAssignOverlaySync({
    bool updateMarker = false,
    bool radiusOnly = false,
    String debugReason = 'scheduled',
  }) {
    if (_assignOverlayActivating) {
      if (!_assignOverlayPending) {
        _assignOverlayPendingRadiusOnly = radiusOnly && !updateMarker;
      } else {
        _assignOverlayPendingRadiusOnly =
            _assignOverlayPendingRadiusOnly && radiusOnly && !updateMarker;
      }
      _assignOverlayPending = true;
      _assignOverlayPendingMarker |= updateMarker;
      _assignOverlayPendingReason = debugReason;
      return;
    }
    _assignOverlaySyncMarker |= updateMarker;
    if (_assignOverlaySyncTimer == null) {
      _assignOverlaySyncRadiusOnly = radiusOnly && !updateMarker;
    } else {
      _assignOverlaySyncRadiusOnly =
          _assignOverlaySyncRadiusOnly && radiusOnly && !updateMarker;
    }
    _assignOverlaySyncReason = debugReason;
    if (_assignOverlaySyncTimer != null) return;
    _assignOverlaySyncTimer = Timer(Duration.zero, () {
      _assignOverlaySyncTimer = null;
      final marker = _assignOverlaySyncMarker;
      final syncRadiusOnly = _assignOverlaySyncRadiusOnly;
      final reason = _assignOverlaySyncReason ?? 'scheduled';
      _assignOverlaySyncMarker = false;
      _assignOverlaySyncRadiusOnly = false;
      _assignOverlaySyncReason = null;
      unawaited(
        this._activateAssignOverlay(
          updateMarker: marker,
          radiusOnly: syncRadiusOnly && !marker,
          debugReason: 'scheduled:$reason',
        ),
      );
    });
  }

  Future<void> _flushAssignOverlaySync({
    bool updateMarker = false,
    bool finishPreview = false,
    String debugReason = 'flush',
  }) async {
    _assignOverlaySyncTimer?.cancel();
    _assignOverlaySyncTimer = null;
    final marker = _assignOverlaySyncMarker || updateMarker;
    _assignOverlaySyncMarker = false;
    _assignOverlaySyncRadiusOnly = false;
    _assignOverlaySyncReason = null;
    await this._activateAssignOverlay(
      updateMarker: marker,
      forceNative: finishPreview,
      debugReason: 'flush:$debugReason',
    );
    await this._flushVeilSync(
      fullQuality: true,
      reason: 'assign-overlay:$debugReason',
    );
    if (finishPreview && _assignFlutterPreviewActive) {
      DebugConsole.log(
        'FLUTTER_PREVIEW_NATIVE_SYNC: reason=$debugReason ${_assignDebugState()}',
      );
    }
  }

  void _scheduleAssignCardSync() {
    if (_assignCardSyncTimer != null) {
      _assignCardSyncPending = true;
      return;
    }
    _assignCardSyncTimer = Timer(const Duration(milliseconds: 200), () {
      _assignCardSyncTimer = null;
      if (!mounted || !_isAssigning) return;
      setState(() {});
      if (_assignCardSyncPending) {
        _assignCardSyncPending = false;
        this._scheduleAssignCardSync();
      }
    });
  }

  void _flushAssignCardSync() {
    _assignCardSyncTimer?.cancel();
    _assignCardSyncTimer = null;
    _assignCardSyncPending = false;
    if (mounted && _isAssigning) setState(() {});
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

  void _beginClosingAssignVisual({
    required bool keepCircle,
    bool keepPreview = false,
  }) {
    _assignVisualClearTimer?.cancel();
    _assignOverlaySyncTimer?.cancel();
    _assignOverlaySyncTimer = null;
    _assignOverlaySyncMarker = false;
    _assignOverlaySyncRadiusOnly = false;
    _assignOverlaySyncReason = null;
    _assignOverlayPending = false;
    _assignOverlayPendingMarker = false;
    _assignOverlayPendingRadiusOnly = false;
    _assignOverlayPendingReason = null;
    _veilSyncTimer?.cancel();
    _veilSyncTimer = null;
    _veilSyncRequested = false;
    _veilSyncRequestedIgnoreAssign = false;
    _veilSyncRequestedFullQuality = false;
    _veilSyncRequestedReason = null;
    _cardRadiusLogCounter = 0;
    _cardTimeLogCounter = 0;
    _assignCardSyncTimer?.cancel();
    _assignCardSyncTimer = null;
    _assignCardSyncPending = false;
    if (!keepPreview) {
      _assignFlutterPreviewActive = false;
      _assignPreviewCircleHidden = false;
      _assignPreviewVeilHidden = false;
    }
    setState(() {
      _isAssigning = false;
      _closingAssignVisual = true;
      _closingAssignCircle = keepCircle;
      _assignExisting = null;
      if (!keepPreview) {
        _assignNativeAlarmLayerId = null;
      }
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
      unawaited(() async {
        if (!mounted) return;
        final style = _controller?.style;
        if (style != null &&
            (_assignPreviewCircleHidden || _assignPreviewVeilHidden)) {
          await this._restoreNativeAssignPreviewOpacity(style);
        }
        if (!mounted) return;
        setState(() {
          _closingAssignVisual = false;
          _closingAssignCircle = false;
          _assignFlutterPreviewActive = false;
          _assignPreviewCircleHidden = false;
          _assignPreviewVeilHidden = false;
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
      }());
    });
  }

  Future<void> _startAssign(
    double lat,
    double lng, {
    AlarmPoint? existing,
  }) async {
    _assignVisualClearTimer?.cancel();
    _assignOverlaySyncTimer?.cancel();
    _assignOverlaySyncTimer = null;
    _assignOverlaySyncMarker = false;
    _assignOverlaySyncReason = null;
    _assignOverlayPending = false;
    _assignOverlayPendingMarker = false;
    _assignOverlayPendingReason = null;
    _veilSyncTimer?.cancel();
    _veilSyncTimer = null;
    _veilSyncRequested = false;
    _veilSyncRequestedIgnoreAssign = false;
    _veilSyncRequestedFullQuality = false;
    _veilSyncRequestedReason = null;
    _assignCardSyncTimer?.cancel();
    _assignCardSyncTimer = null;
    _assignCardSyncPending = false;
    _assignFlutterPreviewActive = false;
    _assignPreviewCircleHidden = false;
    _assignPreviewVeilHidden = false;
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
    final alarmProv = context.read<AlarmProvider>();
    _assignNativeAlarmLayerId = existing == null
        ? 'alarm-${alarmProv.alarmPoints.length}'
        : this._alarmLayerId(alarmProv, existing.id);
    _assignNativeHidden = existing == null;
    _isAssigning = true;
    _radiusNotifier.value = this._currentRadiusPx;
    this._refreshAssignMarker();
    DebugConsole.log(
      'ASSIGN_START: lat=$lat lng=$lng existing=${existing?.id} '
      'screenCenter=$_assignScreenCenter nativeLayer=$_assignNativeAlarmLayerId '
      'radiusPx=${this._currentRadiusPx.toStringAsFixed(1)} radiusM=$_assignRadius '
      'trigger=${_assignTriggerType.name} zone=${_assignZoneTrigger.name} '
      'useNative=$_useNativeAssignCircle nativeHidden=$_assignNativeHidden',
    );
    final style = _controller?.style;
    if (style != null && _showAssignOverlay) {
      if (_useNativeAssignCircle) await this._updateFastCircleLayer(style);
      DebugConsole.log('ASSIGN_START: updating veil immediately');
      await this._flushVeilSync(fullQuality: true, reason: 'assign-start');
    } else if (existing != null) {
      DebugConsole.log('ASSIGN_START: keeping native alarm visual during edit');
    }
    setState(() {});
  }

  void _startAssignFlutterPreview({required String reason}) {
    if (!_isAssigning) return;
    final wasActive = _assignFlutterPreviewActive;
    _assignFlutterPreviewActive = true;
    if (!wasActive && mounted) setState(() {});
    final style = _controller?.style;
    if (style == null) return;
    unawaited(this._hideNativeAssignVisualForPreview(style, reason));
    if (!wasActive) {
      DebugConsole.log(
        'FLUTTER_PREVIEW_START: reason=$reason ${_assignDebugState()}',
      );
    }
  }

  Future<void> _hideNativeAssignVisualForPreview(
    StyleController style,
    String reason, {
    bool force = false,
  }) async {
    final id = _assignNativeAlarmLayerId;
    if (id != null && (force || !_assignPreviewCircleHidden)) {
      final layerId = 'radius-circle-$id';
      await this._setNativeLayerPaintProperty(
        style,
        layerId: layerId,
        property: 'circle-opacity',
        value: 0.0,
      );
      await this._setNativeLayerPaintProperty(
        style,
        layerId: layerId,
        property: 'circle-stroke-opacity',
        value: 0.0,
      );
      _assignPreviewCircleHidden = true;
    }
    final shouldHideVeil =
        _assignActive && _assignZoneTrigger == ZoneTrigger.onLeave;
    if (shouldHideVeil && (force || !_assignPreviewVeilHidden)) {
      await this._setNativeLayerPaintProperty(
        style,
        layerId: 'veil-fill',
        property: 'fill-opacity',
        value: 0.0,
      );
      await this._setNativeLayerPaintProperty(
        style,
        layerId: 'veil-outline',
        property: 'line-opacity',
        value: 0.0,
      );
      _assignPreviewVeilHidden = true;
    } else if (!shouldHideVeil && _assignPreviewVeilHidden) {
      await this._restoreNativeVeilOpacity(style);
    }
  }

  Future<void> _stopAssignFlutterPreview({required String reason}) async {
    if (!_assignFlutterPreviewActive &&
        !_assignPreviewCircleHidden &&
        !_assignPreviewVeilHidden) {
      return;
    }
    final style = _controller?.style;
    if (style != null) {
      await this._restoreNativeAssignPreviewOpacity(style);
    }
    _assignFlutterPreviewActive = false;
    if (mounted && _isAssigning) setState(() {});
    DebugConsole.log(
      'FLUTTER_PREVIEW_STOP: reason=$reason ${_assignDebugState()}',
    );
  }

  Future<bool> _holdAssignFlutterPreviewForNativeHandoff({
    required StyleController? style,
    required String reason,
  }) async {
    final shouldHold = _assignFlutterPreviewActive;
    if (!_assignFlutterPreviewActive &&
        !_assignPreviewCircleHidden &&
        !_assignPreviewVeilHidden) {
      return false;
    }
    if (style != null && shouldHold) {
      await this._hideNativeAssignVisualForPreview(style, reason, force: true);
    } else if (style != null) {
      await this._restoreNativeAssignPreviewOpacity(style);
    }
    DebugConsole.log(
      'FLUTTER_PREVIEW_HANDOFF: reason=$reason hold=$shouldHold ${_assignDebugState()}',
    );
    return shouldHold;
  }

  Future<void> _restoreNativeAssignPreviewOpacity(StyleController style) async {
    final id = _assignNativeAlarmLayerId;
    if (id != null && _assignPreviewCircleHidden) {
      final layerId = 'radius-circle-$id';
      await this._setNativeLayerPaintProperty(
        style,
        layerId: layerId,
        property: 'circle-opacity',
        value: 1.0,
      );
      await this._setNativeLayerPaintProperty(
        style,
        layerId: layerId,
        property: 'circle-stroke-opacity',
        value: 1.0,
      );
      _assignPreviewCircleHidden = false;
    }
    if (_assignPreviewVeilHidden) {
      await this._restoreNativeVeilOpacity(style);
    }
  }

  Future<void> _restoreNativeVeilOpacity(StyleController style) async {
    await this._setNativeLayerPaintProperty(
      style,
      layerId: 'veil-fill',
      property: 'fill-opacity',
      value: 0.15,
    );
    await this._setNativeLayerPaintProperty(
      style,
      layerId: 'veil-outline',
      property: 'line-opacity',
      value: 1.0,
    );
    _assignPreviewVeilHidden = false;
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
      await this._flushVeilSync(
        ignoreAssign: true,
        fullQuality: true,
        reason: 'cancel-in-place',
      );
      await this._stopAssignFlutterPreview(reason: 'cancel-in-place');
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
    if (style != null && nativeWasHidden) {
      await this._flushVeilSync(
        ignoreAssign: true,
        fullQuality: true,
        reason: 'cancel-rebuild',
      );
    }
    if (style != null) await this._clearFastCircleLayer(style);
    await this._stopAssignFlutterPreview(reason: 'cancel');
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
        await this._flushVeilSync(
          ignoreAssign: true,
          fullQuality: true,
          reason: 'save-in-place',
        );
        final keepPreview = await this
            ._holdAssignFlutterPreviewForNativeHandoff(
              style: liveStyle,
              reason: 'save-in-place',
            );
        await this._clearFastCircleLayer(liveStyle);
        _beginClosingAssignVisual(keepCircle: false, keepPreview: keepPreview);
        _scheduleAssignVisualClear(
          keepPreview
              ? const Duration(milliseconds: 220)
              : const Duration(milliseconds: 80),
        );
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
          await this._promoteDraftRadiusCircleLayer(liveStyle, singleCircle);
          _lastRadiusDataHash = this._radiusHash(circles);
        } else {
          await this._rebuildRadiusLayers(
            liveStyle,
            circles,
            _radiusLayerVersion,
          );
          _lastRadiusDataHash = this._radiusHash(circles);
        }
        await this._flushVeilSync(
          ignoreAssign: true,
          fullQuality: true,
          reason: 'save-rebuild',
        );
      }
      // Wait for MapLibre to render native marker before hiding overlay pin
      if (shouldRebuildNative) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
      final keepPreview = await this._holdAssignFlutterPreviewForNativeHandoff(
        style: style,
        reason: 'save',
      );
      _beginClosingAssignVisual(keepCircle: false, keepPreview: keepPreview);
      _finishClosingAssignCircle();
      _scheduleAssignVisualClear(
        !wasExisting && _useNativeAssignCircle
            ? const Duration(milliseconds: 500)
            : keepPreview
            ? const Duration(milliseconds: 220)
            : const Duration(milliseconds: 80),
      );
    } finally {
      _suppressRadiusSync = false;
    }
  }
}
