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

  _RadiusCircleData? _currentAssignNativeVisualCircle(AlarmProvider alarmProv) {
    if (_assignExisting != null) {
      return this._currentAssignCircle(alarmProv);
    }
    final id = _assignNativeAlarmLayerId;
    if (id == null) return null;
    final isTime = _assignTriggerType == TriggerType.time;
    final radius = isTime
        ? math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60)
        : _assignRadius;
    return (
      id: id,
      lng: _assignLng,
      lat: _assignLat,
      radiusMeters: radius,
      active: _assignActive,
      isTime: isTime,
      isLeave: _assignZoneTrigger == ZoneTrigger.onLeave,
    );
  }

  bool _canTrustImmediateAssignRadiusPaint({
    required bool radiusOnly,
    required bool updateMarker,
  }) {
    if (!radiusOnly ||
        updateMarker ||
        !_useNativeAssignCircle ||
        _assignFlutterPreviewActive ||
        _nativeCircleRadiusPaintAvailable == false) {
      return false;
    }
    final existing = _assignExisting;
    final nativeCircleId = _assignNativeAlarmLayerId;
    return (existing == null || !_assignNativeHidden) &&
        nativeCircleId != null &&
        (_radiusVisualIds.contains(nativeCircleId) ||
            _radiusCircleLayerKeys.containsKey(nativeCircleId));
  }

  int? _assignRadiusFrameFromDebugReason(String debugReason) {
    final hash = debugReason.lastIndexOf('#');
    if (hash < 0 || hash == debugReason.length - 1) return null;
    return int.tryParse(debugReason.substring(hash + 1));
  }

  bool _shouldSyncLiveAssignVeilForRadiusFrame(String debugReason) {
    if (!_isDraggingRadius) return true;
    final frame = _assignRadiusFrameFromDebugReason(debugReason);
    if (frame == null) return false;
    return frame == 1 || frame % 15 == 0;
  }

  bool _shouldLogImmediateLeaveRadiusPaint(String debugReason) {
    if (!debugReason.startsWith('immediate:')) return false;
    if (_assignZoneTrigger != ZoneTrigger.onLeave) return false;
    final frame = _assignRadiusFrameFromDebugReason(debugReason);
    if (frame == null) return false;
    return frame == 1 || frame % 15 == 0;
  }

  Future<void> _applyAssignRadiusPaint({required String debugReason}) async {
    if (!_isAssigning ||
        !_useNativeAssignCircle ||
        _assignFlutterPreviewActive) {
      return;
    }
    final style = _controller?.style;
    if (style == null) return;
    final circle = this._currentAssignNativeVisualCircle(
      context.read<AlarmProvider>(),
    );
    if (circle == null) return;
    if (!_radiusVisualIds.contains(circle.id) &&
        !_radiusCircleLayerKeys.containsKey(circle.id)) {
      return;
    }
    await this._setCircleLayerRadiusPaint(
      style,
      layerId: 'radius-circle-${circle.id}',
      visualId: circle.id,
      radiusPx: this._radiusPxForCircle(circle),
      debugReason: 'immediate:$debugReason',
    );
  }

  void _syncAssignRadiusPaintImmediate({required String debugReason}) {
    _assignRadiusPaintSyncReason = debugReason;
    if (_assignRadiusPaintSyncActive) {
      _assignRadiusPaintSyncPending = true;
      return;
    }
    _assignRadiusPaintSyncActive = true;
    final drain = () async {
      try {
        while (mounted && _isAssigning) {
          final reason = _assignRadiusPaintSyncReason ?? debugReason;
          _assignRadiusPaintSyncReason = null;
          _assignRadiusPaintSyncPending = false;
          await this._applyAssignRadiusPaint(debugReason: reason);
          if (!_assignRadiusPaintSyncPending) break;
        }
      } finally {
        _assignRadiusPaintSyncActive = false;
        if (mounted && _isAssigning && _assignRadiusPaintSyncPending) {
          _assignRadiusPaintSyncPending = false;
          final reason = _assignRadiusPaintSyncReason ?? debugReason;
          _assignRadiusPaintSyncReason = null;
          this._syncAssignRadiusPaintImmediate(debugReason: reason);
        }
      }
    }();
    _assignRadiusPaintSyncDrain = drain;
    unawaited(
      drain.whenComplete(() {
        if (identical(_assignRadiusPaintSyncDrain, drain)) {
          _assignRadiusPaintSyncDrain = null;
        }
      }),
    );
  }

  void _syncAssignRadiusOnlyVisual({required String debugReason}) {
    if (_assignFlutterPreviewActive) return;
    if (!_canTrustImmediateAssignRadiusPaint(
      radiusOnly: true,
      updateMarker: false,
    )) {
      this._scheduleAssignOverlaySync(
        radiusOnly: true,
        debugReason: debugReason,
      );
      return;
    }
    this._syncAssignRadiusPaintImmediate(debugReason: debugReason);
    if (_assignActive &&
        _assignZoneTrigger == ZoneTrigger.onLeave &&
        _shouldSyncLiveAssignVeilForRadiusFrame(debugReason)) {
      this._scheduleVeilSync(
        fullQuality: false,
        reason: 'assign-radius:' + debugReason,
      );
    }
  }

  Future<void> _flushAssignRadiusPaintSync() async {
    _assignRadiusPaintSyncPending = false;
    _assignRadiusPaintSyncReason = null;
    final drain = _assignRadiusPaintSyncDrain;
    if (drain != null) await drain;
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
      final shouldScheduleLiveVeil =
          radiusOnly &&
          !updateMarker &&
          _assignActive &&
          _assignZoneTrigger == ZoneTrigger.onLeave;
      if (_assignFlutterPreviewActive && !forceNative) {
        path = 'flutter-preview';
        return;
      }
      final liveStyle = style;
      final canUpdateExistingNative =
          liveStyle != null &&
          _useNativeAssignCircle &&
          existing != null &&
          !_assignNativeHidden;
      if (canUpdateExistingNative) {
        path = 'existing-native';
        await this._updateExistingNativeAssignLayer(
          liveStyle,
          alarmProv,
          updateMarker: updateMarker,
          radiusOnly: radiusOnly && !updateMarker,
        );
        if (_assignVisualOwner == _AssignVisualOwner.nativeLive) {
          if (shouldScheduleLiveVeil) {
            this._scheduleVeilSync(
              fullQuality: false,
              reason: 'assign-overlay:$debugReason',
            );
          } else {
            await this._syncAssignVeilWithOverlay(debugReason: debugReason);
          }
        }
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
        if (shouldScheduleLiveVeil) {
          this._scheduleVeilSync(
            fullQuality: false,
            reason: 'assign-overlay:$debugReason',
          );
        } else {
          await this._syncAssignVeilWithOverlay(debugReason: debugReason);
        }
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
    if (_assignVisualOwner == _AssignVisualOwner.nativeLive &&
        !_assignFlutterPreviewActive) {
      await this._flushVeilSync(
        fullQuality: false,
        reason: 'assign-overlay:$debugReason',
      );
    }
    if (finishPreview && _assignFlutterPreviewActive) {
      final style = _controller?.style;
      if (style != null) {
        await this._hideNativeAssignVisualForPreview(
          style,
          'finish-preview:$debugReason',
          force: true,
        );
      }
    }
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
    _radiusCircleSourceKeys.remove(id);
    _radiusPaintOverrideIds.remove(id);
    _radiusPaintOverrideTokens.remove(id);
    try {
      await style.removeLayer('radius-circle-$id');
    } catch (_) {}
  }

  void _beginClosingAssignVisual({
    required bool keepCircle,
    bool keepPreview = false,
    bool keepMarker = false,
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
    _assignRadiusPaintSyncPending = false;
    _assignRadiusPaintSyncReason = null;
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
      _assignPreviewLabelHidden = false;
      _assignVisualOwner = _AssignVisualOwner.nativeLive;
    }
    setState(() {
      _isAssigning = false;
      _closingAssignCircle = keepCircle;
      _closingAssignMarker = keepMarker;
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
        final shouldRestoreNativePreview =
            style != null &&
            (_assignPreviewCircleHidden ||
                _assignPreviewVeilHidden ||
                _assignPreviewLabelHidden);
        if (!mounted) return;
        setState(() {
          _closingAssignCircle = false;
          _closingAssignMarker = false;
          _assignFlutterPreviewActive = false;
          _assignScreenCenter = null;
          _assignMarkerPng = null;
          _assignMarkerKey = null;
          if (!shouldRestoreNativePreview) {
            _assignPreviewCircleHidden = false;
            _assignPreviewVeilHidden = false;
            _assignPreviewLabelHidden = false;
            _assignNativeAlarmLayerId = null;
            _assignNativeHidden = false;
          }
          _assignTriggerType = TriggerType.distance;
          _assignZoneTrigger = ZoneTrigger.onEntry;
          _assignTimeMinutes = 10;
          _assignActive = true;
          _assignVisualOwner = _AssignVisualOwner.nativeLive;
        });
        if (shouldRestoreNativePreview && style != null) {
          await this._restoreNativeAssignPreviewOpacity(style);
          if (!mounted) return;
          setState(() {
            _assignPreviewCircleHidden = false;
            _assignPreviewVeilHidden = false;
            _assignPreviewLabelHidden = false;
            _assignNativeAlarmLayerId = null;
            _assignNativeHidden = false;
          });
        }
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
    _assignRadiusPaintSyncPending = false;
    _assignRadiusPaintSyncReason = null;
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
    _assignPreviewLabelHidden = false;
    _assignVisualOwner = _AssignVisualOwner.nativeLive;
    _closingAssignMarker = false;
    _suspendCompassForAssign();
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
    if (id != null && (force || !_assignPreviewLabelHidden)) {
      final hidden = await this._setNativeLayerPaintProperty(
        style,
        layerId: 'radius-label-$id',
        property: 'icon-opacity',
        value: 0.0,
      );
      _assignPreviewLabelHidden = _assignPreviewLabelHidden || hidden;
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

  void _refreshNativePreviewHiddenState(String reason) {
    if (!_assignFlutterPreviewActive) return;
    final style = _controller?.style;
    if (style == null) return;
    unawaited(
      this._hideNativeAssignVisualForPreview(style, reason, force: true),
    );
  }

  Future<void> _stopAssignFlutterPreview({required String reason}) async {
    if (!_assignFlutterPreviewActive &&
        !_assignPreviewCircleHidden &&
        !_assignPreviewVeilHidden &&
        !_assignPreviewLabelHidden) {
      return;
    }
    final style = _controller?.style;
    if (style != null) {
      await this._restoreNativeAssignPreviewOpacity(style);
    }
    _assignFlutterPreviewActive = false;
    _assignVisualOwner = _AssignVisualOwner.nativeLive;
    if (mounted && _isAssigning) setState(() {});
    DebugConsole.log(
      'FLUTTER_PREVIEW_STOP: reason=$reason ${_assignDebugState()}',
    );
  }

  Future<bool> _prepareFlutterPreviewNativeHandoff({
    required StyleController? style,
    required String reason,
  }) async {
    if (!_assignFlutterPreviewActive &&
        !_assignPreviewCircleHidden &&
        !_assignPreviewVeilHidden &&
        !_assignPreviewLabelHidden) {
      return false;
    }
    _assignVisualOwner = _AssignVisualOwner.transitionPending;
    if (style != null) {
      await this._hideNativeAssignVisualForPreview(style, reason, force: true);
    }
    DebugConsole.log(
      'FLUTTER_PREVIEW_HANDOFF: reason=$reason stage=prepare ${_assignDebugState()}',
    );
    return true;
  }

  Future<void> _completeFlutterPreviewNativeHandoff({
    required StyleController? style,
    required bool keepPreview,
    required String reason,
    Future<void>? nativeAck,
  }) async {
    if (!keepPreview || style == null) {
      if (nativeAck != null) {
        await nativeAck;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      _assignVisualOwner = _AssignVisualOwner.nativeLive;
      return;
    }
    await (nativeAck ?? this._waitForNativeRenderAck(reason: reason));
    await this._restoreNativeAssignPreviewOpacity(style);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _assignVisualOwner = _AssignVisualOwner.nativeLive;
    DebugConsole.log(
      'FLUTTER_PREVIEW_HANDOFF: reason=$reason stage=native-visible ${_assignDebugState()}',
    );
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
    if (id != null && _assignPreviewLabelHidden) {
      await this._setNativeLayerPaintProperty(
        style,
        layerId: 'radius-label-$id',
        property: 'icon-opacity',
        value: 1.0,
      );
      _assignPreviewLabelHidden = false;
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
      value: 0.0,
    );
    _assignPreviewVeilHidden = false;
  }

  Future<void> _cancelAssign({bool nativeAlreadySynced = false}) async {
    DebugConsole.log(
      'CANCEL_ASSIGN: isAssigning=$_isAssigning existing=${_assignExisting?.id}',
    );
    await this._flushAssignRadiusPaintSync();
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
    await this._flushAssignRadiusPaintSync();
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
        await alarmProv.updateAlarmPoint(effectiveAlarm);
      } else if (alarmProv.canAddAlarm) {
        if (effectiveAlarm.isActive) {
          await PermissionService.requestBackgroundLocation();
        }
        await alarmProv.addAlarmPoint(effectiveAlarm);
      }
      _seedAlarmInsideState(effectiveAlarm);
      _radiusDebounce?.cancel();
      final style = _controller?.style;
      final canUpdateInPlace =
          wasExisting && !nativeWasHidden && style != null && _radiusLayerReady;
      if (canUpdateInPlace) {
        final liveStyle = style;
        final keepPreview = await this._prepareFlutterPreviewNativeHandoff(
          style: liveStyle,
          reason: 'save-in-place',
        );
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
            preserveRadiusPaintOverride: true,
          );
        }
        if (keepPreview) {
          await this._hideNativeAssignVisualForPreview(
            liveStyle,
            'save-in-place-native-flush',
            force: true,
          );
        }
        _lastRadiusDataHash = this._radiusHash(circles);
        await this._flushVeilSync(
          ignoreAssign: true,
          fullQuality: true,
          reason: 'save-in-place',
        );
        final nativeAck = this._waitForNativeRenderAck(
          reason: 'save-in-place-native-flush',
        );
        await this._completeFlutterPreviewNativeHandoff(
          style: liveStyle,
          keepPreview: keepPreview,
          reason: 'save-in-place-native-flush',
          nativeAck: nativeAck,
        );
        if (circle != null) {
          this._scheduleCircleLayerRadiusExpressionRestore(
            liveStyle,
            circle,
          );
        }
        await this._clearFastCircleLayer(liveStyle);
        _beginClosingAssignVisual(
          keepCircle: false,
          keepPreview: false,
          keepMarker: false,
        );
        _scheduleAssignVisualClear(Duration.zero);
        return;
      }
      final shouldRebuildNative =
          style != null &&
          _radiusLayerReady &&
          (!wasExisting || nativeWasHidden || visualChanged);
      final keepPreview = await this._prepareFlutterPreviewNativeHandoff(
        style: style,
        reason: 'save',
      );
      Future<void>? nativeAck;
      _RadiusCircleData? promotedCircle;
      if (shouldRebuildNative) _lastRadiusDataHash = '';
      if (shouldRebuildNative) await this._ensureAssignMarkerBitmap();
      if (shouldRebuildNative) {
        final liveStyle = style;
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
          promotedCircle = singleCircle;
          await this._promoteDraftRadiusCircleLayer(
            liveStyle,
            singleCircle,
            preserveRadiusPaintOverride: true,
          );
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
        nativeAck = this._waitForNativeRenderAck(reason: 'save-native-flush');
        if (keepPreview) {
          await this._hideNativeAssignVisualForPreview(
            liveStyle,
            'save-rebuild-native-ready',
            force: true,
          );
        }
      }
      await this._completeFlutterPreviewNativeHandoff(
        style: style,
        keepPreview: keepPreview,
        reason: 'save-native-flush',
        nativeAck: nativeAck,
      );
      if (promotedCircle != null && style != null) {
        this._scheduleCircleLayerRadiusExpressionRestore(
          style,
          promotedCircle,
        );
      }
      _beginClosingAssignVisual(
        keepCircle: false,
        keepPreview: false,
        keepMarker: false,
      );
      _finishClosingAssignCircle();
      _scheduleAssignVisualClear(Duration.zero);
    } finally {
      _suppressRadiusSync = false;
    }
  }
}
