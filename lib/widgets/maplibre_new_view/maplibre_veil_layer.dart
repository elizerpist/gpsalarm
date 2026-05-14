part of '../maplibre_new_view.dart';

extension _MaplibreVeilLayer on _MaplibreNewViewState {
  void _queueVeilSyncRequest({
    required bool ignoreAssign,
    required bool fullQuality,
    required String reason,
  }) {
    _veilSyncRequested = true;
    _veilSyncRequestedIgnoreAssign = ignoreAssign;
    _veilSyncRequestedFullQuality =
        _veilSyncRequestedFullQuality || fullQuality;
    _veilSyncRequestedReason = reason;
  }

  void _scheduleVeilSync({
    bool ignoreAssign = false,
    bool fullQuality = false,
    String reason = 'scheduled',
  }) {
    _queueVeilSyncRequest(
      ignoreAssign: ignoreAssign,
      fullQuality: fullQuality,
      reason: reason,
    );
    if (_veilSyncDrainFuture != null || _veilSyncTimer != null) return;
    _armVeilSyncTimer();
  }

  void _armVeilSyncTimer() {
    if (_veilSyncDrainFuture != null || _veilSyncTimer != null) return;
    final delay = const Duration(milliseconds: 16);
    _veilSyncTimer = Timer(delay, () {
      _veilSyncTimer = null;
      unawaited(_drainVeilSyncQueue());
    });
  }

  Future<void> _flushVeilSync({
    bool ignoreAssign = false,
    bool fullQuality = true,
    String reason = 'flush',
  }) {
    _veilSyncTimer?.cancel();
    _veilSyncTimer = null;
    _queueVeilSyncRequest(
      ignoreAssign: ignoreAssign,
      fullQuality: fullQuality,
      reason: reason,
    );
    final activeDrain = _veilSyncDrainFuture;
    if (activeDrain != null) {
      return activeDrain.then((_) {
        _veilSyncTimer?.cancel();
        _veilSyncTimer = null;
        return _drainVeilSyncQueue(drainAll: true);
      });
    }
    return _drainVeilSyncQueue(drainAll: true);
  }

  bool _usesLiveAssignVeilHole({bool ignoreAssign = false}) {
    return !ignoreAssign &&
        _isAssigning &&
        _assignVisualOwner == _AssignVisualOwner.nativeLive &&
        !_assignFlutterPreviewActive &&
        _assignActive &&
        _assignZoneTrigger == ZoneTrigger.onLeave &&
        (_showAssignOverlay || _useNativeExistingAssignLayer);
  }

  Future<void> _syncAssignVeilWithRadiusPaint({
    required StyleController style,
    required AlarmProvider alarmProv,
    required String debugReason,
  }) {
    if (!this._usesLiveAssignVeilHole()) {
      if (_assignExitVeilOutlineActive) {
        return this._syncAssignExitVeilOutlineMode(
          style,
          active: false,
          reason: 'assign-radius:immediate:$debugReason',
        );
      }
      return Future<void>.value();
    }

    _veilSyncTimer?.cancel();
    _veilSyncTimer = null;
    _veilSyncRequested = false;
    _veilSyncRequestedIgnoreAssign = false;
    _veilSyncRequestedFullQuality = false;
    _veilSyncRequestedReason = null;

    return this._updateVeil(
      style,
      alarmProv,
      fullQuality: false,
      reason: 'assign-radius:immediate:$debugReason',
    );
  }

  Future<void> _syncAssignVeilWithOverlay({required String debugReason}) {
    if (!this._usesLiveAssignVeilHole()) {
      final style = _controller?.style;
      if (style != null && _assignExitVeilOutlineActive) {
        return this._syncAssignExitVeilOutlineMode(
          style,
          active: false,
          reason: 'assign-overlay:$debugReason',
        );
      }
      return Future<void>.value();
    }
    return this._flushVeilSync(
      fullQuality: false,
      reason: 'assign-overlay:$debugReason',
    );
  }

  Future<void> _syncAssignExitVeilOutlineMode(
    StyleController style, {
    required bool active,
    required String reason,
  }) async {
    if (!active) {
      _assignExitVeilOutlineRestoreTimer?.cancel();
      _assignExitVeilOutlineRestoreTimer = null;
      _assignExitVeilOutlineFastSuppressed = false;
    }

    final outlineOpacity = active && !_assignExitVeilOutlineFastSuppressed
        ? 0.62
        : 0.0;
    if (_assignExitVeilOutlineActive == active &&
        (_assignExitVeilOutlineOpacity - outlineOpacity).abs() < 0.001) {
      return;
    }

    _assignExitVeilOutlineActive = active;
    _assignExitVeilOutlineOpacity = outlineOpacity;
    await this._setNativeLayerPaintProperty(
      style,
      layerId: 'veil-outline',
      property: 'line-opacity',
      value: 0.0,
    );
    await this._setNativeLayerPaintProperty(
      style,
      layerId: 'veil-live-outline',
      property: 'line-opacity',
      value: outlineOpacity,
    );
    final id = _assignNativeAlarmLayerId;
    if (id != null) {
      await this._setNativeLayerPaintProperty(
        style,
        layerId: 'radius-circle-$id',
        property: 'circle-stroke-opacity',
        value: active ? 0.0 : 1.0,
      );
    }
    DebugConsole.log(
      'EXIT_OUTLINE_MODE: active=$active liveOutline=$outlineOpacity '
      'maskOutline=0.0 nativeStrokeHidden=$active reason=$reason '
      '${_assignDebugState()}',
    );
  }

  double _exitLiveRadiusDeltaPx(
    _RadiusCircleData circle,
    double previousRadiusM,
  ) {
    if (circle.radiusMeters.abs() <= 0.001) return 0.0;
    final currentPx = _radiusPxForCircle(circle);
    final previousPx = currentPx * previousRadiusM / circle.radiusMeters;
    return (currentPx - previousPx).abs();
  }

  Future<void> _suppressExitVeilOutlineForFastSwipe(
    StyleController style, {
    required double deltaPx,
    required String reason,
  }) async {
    _assignExitVeilOutlineRestoreTimer?.cancel();
    _assignExitVeilOutlineRestoreTimer = Timer(
      const Duration(milliseconds: 72),
      () {
        _assignExitVeilOutlineRestoreTimer = null;
        if (!mounted || !_usesLiveAssignVeilHole()) return;
        if (!_assignExitVeilOutlineFastSuppressed) return;
        final liveStyle = _controller?.style;
        if (liveStyle == null) return;
        unawaited(() async {
          _assignExitVeilOutlineFastSuppressed = false;
          DebugConsole.log(
            'EXIT_OUTLINE_FAST_SUPPRESS: active=false reason=restore '
            '${_assignDebugState()}',
          );
          await _syncAssignExitVeilOutlineMode(
            liveStyle,
            active: true,
            reason: 'fast-restore:$reason',
          );
          _refreshFastExitOutlineFallback();
        }());
      },
    );

    if (_assignExitVeilOutlineFastSuppressed) return;
    _assignExitVeilOutlineFastSuppressed = true;
    _refreshFastExitOutlineFallback();
    DebugConsole.log(
      'EXIT_OUTLINE_FAST_SUPPRESS: active=true '
      'dPx=${deltaPx.toStringAsFixed(1)} reason=$reason '
      '${_assignDebugState()}',
    );
    await _syncAssignExitVeilOutlineMode(
      style,
      active: true,
      reason: 'fast-suppress:$reason',
    );
  }

  bool _shouldLogVeilSync(String reason, int elapsedMs) {
    return _isAssigning &&
        (_shouldLogAssignFrame(_assignSyncSeq) ||
            (reason.startsWith('assign-radius:immediate:') &&
                this._shouldLogAssignDebugReason(reason)) ||
            elapsedMs > 8);
  }

  Future<void> _drainVeilSyncQueue({bool drainAll = false}) {
    final existing = _veilSyncDrainFuture;
    if (existing != null) return existing;
    final future = () async {
      while (mounted && _veilSyncRequested) {
        final ignoreAssign = _veilSyncRequestedIgnoreAssign;
        final fullQuality = _veilSyncRequestedFullQuality;
        final reason = _veilSyncRequestedReason ?? 'queued';
        _veilSyncRequested = false;
        _veilSyncRequestedIgnoreAssign = false;
        _veilSyncRequestedFullQuality = false;
        _veilSyncRequestedReason = null;
        final style = _controller?.style;
        if (style == null) continue;
        await this._updateVeil(
          style,
          context.read<AlarmProvider>(),
          ignoreAssign: ignoreAssign,
          fullQuality: fullQuality,
          reason: reason,
        );
        if (!drainAll) break;
      }
    }();
    _veilSyncDrainFuture = future.whenComplete(() {
      _veilSyncDrainFuture = null;
      if (mounted && _veilSyncRequested && _veilSyncTimer == null) {
        if (!drainAll) {
          _armVeilSyncTimer();
          return;
        }
        _veilSyncTimer = Timer(Duration.zero, () {
          _veilSyncTimer = null;
          unawaited(_drainVeilSyncQueue(drainAll: true));
        });
      }
    });
    return _veilSyncDrainFuture!;
  }

  int _veilSegments({
    required bool fullQuality,
    required bool useLiveAssignHole,
  }) {
    if (fullQuality) return 128;
    if (useLiveAssignHole) return 96;
    return 32;
  }

  int _liveAssignVeilSegments(
    _RadiusCircleData? circle, {
    required bool fullQuality,
    required int fallbackSegments,
  }) {
    if (circle == null) return fallbackSegments;
    final radiusPx = _radiusPxForCircle(circle);
    if (radiusPx >= 420) return 256;
    if (radiusPx >= 220) return 192;
    if (radiusPx >= 110) return 128;
    return fullQuality ? 128 : math.max(fallbackSegments, 96);
  }

  List<List<double>> _veilHoleForRadiusCircle(
    _RadiusCircleData circle, {
    required int segments,
  }) {
    return _geoCircle(
      circle.lng,
      circle.lat,
      circle.radiusMeters,
      segments: segments,
    );
  }

  String _veilLiveOutlineGeoJson(
    _RadiusCircleData circle,
    List<List<double>> ring,
  ) {
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {'type': 'LineString', 'coordinates': ring},
          'properties': {'radius_m': circle.radiusMeters},
        },
      ],
    });
  }

  String _exitDebugRingStats(
    _RadiusCircleData circle,
    List<List<double>> ring, {
    required int segments,
  }) {
    if (ring.length < segments + 1 || segments < 4) return 'ring=incomplete';
    double metersAt(int index) {
      final point = ring[index.clamp(0, ring.length - 1)];
      return AlarmService.distanceMeters(
        circle.lat,
        circle.lng,
        point[1],
        point[0],
      );
    }

    final north = metersAt(0);
    final east = metersAt((segments / 4).round());
    final south = metersAt((segments / 2).round());
    final west = metersAt((segments * 3 / 4).round());
    final closed =
        (ring.first[0] - ring.last[0]).abs() < 0.0000001 &&
        (ring.first[1] - ring.last[1]).abs() < 0.0000001;
    return 'geoN=${north.toStringAsFixed(1)} '
        'geoE=${east.toStringAsFixed(1)} '
        'geoS=${south.toStringAsFixed(1)} '
        'geoW=${west.toStringAsFixed(1)} '
        'geoEW=${(east - west).toStringAsFixed(2)} '
        'geoNS=${(north - south).toStringAsFixed(2)} closed=$closed';
  }

  String _exitDebugScreenRingStats(
    _RadiusCircleData circle,
    List<List<double>> ring, {
    required int segments,
  }) {
    final center = this._geoToScreen(circle.lat, circle.lng);
    if (center == null || ring.length < segments + 1 || segments < 4) {
      return 'screenRing=unavailable';
    }

    double? pxAt(int index) {
      final point = ring[index.clamp(0, ring.length - 1)];
      final screen = this._geoToScreen(point[1], point[0]);
      if (screen == null) return null;
      return (screen - center).distance;
    }

    final north = pxAt(0);
    final east = pxAt((segments / 4).round());
    final south = pxAt((segments / 2).round());
    final west = pxAt((segments * 3 / 4).round());
    if (north == null || east == null || south == null || west == null) {
      return 'screenRing=partial';
    }
    return 'scrN=${north.toStringAsFixed(1)} '
        'scrE=${east.toStringAsFixed(1)} '
        'scrS=${south.toStringAsFixed(1)} '
        'scrW=${west.toStringAsFixed(1)} '
        'scrEW=${(east - west).toStringAsFixed(2)} '
        'scrNS=${(north - south).toStringAsFixed(2)} '
        'screenCenter=${center.dx.toStringAsFixed(1)},${center.dy.toStringAsFixed(1)}';
  }

  Future<void> _syncLiveExitVeilOutlineSource(
    StyleController style, {
    required _RadiusCircleData? circle,
    required List<List<double>>? ring,
    required int segments,
    required String reason,
  }) async {
    final sw = Stopwatch()..start();
    final data = circle == null || ring == null
        ? _emptyGeoJson
        : _veilLiveOutlineGeoJson(circle, ring);
    final unchanged = _lastVeilOutlineGeoJson == data;
    var updated = false;
    if (!unchanged) {
      updated = await this._tryUpdateGeoJsonSource(
        style,
        id: 'veil-live-outline-src',
        data: data,
      );
      if (updated) _lastVeilOutlineGeoJson = data;
    }
    sw.stop();
    if (circle == null) {
      _exitDebugLastOutlineRadiusM = null;
      if (this._shouldLogVeilSync(reason, sw.elapsedMilliseconds) ||
          sw.elapsedMilliseconds > 4) {
        DebugConsole.log(
          'VEIL_OUTLINE_SYNC: updated=$updated unchanged=$unchanged '
          'empty=true seg=$segments ms=${sw.elapsedMilliseconds} '
          'reason=$reason ${_assignDebugState()}',
        );
      }
      return;
    }

    final previousOutlineRadius = _exitDebugLastOutlineRadiusM;
    final outlineDelta = previousOutlineRadius == null
        ? 0.0
        : circle.radiusMeters - previousOutlineRadius;
    final outlineSeq = ++_exitDebugOutlineSeq;
    _exitDebugLastOutlineRadiusM = circle.radiusMeters;
    if (this._shouldLogExitDebugTrace(
          reason: reason,
          elapsedMs: sw.elapsedMilliseconds,
          radiusDeltaM: outlineDelta,
          force: !updated && !unchanged,
        ) ||
        sw.elapsedMilliseconds > 4) {
      final ringStats = ring == null
          ? 'ring=null'
          : this._exitDebugRingStats(circle, ring, segments: segments);
      final screenStats = ring == null
          ? 'screenRing=null'
          : this._exitDebugScreenRingStats(circle, ring, segments: segments);
      DebugConsole.log(
        'VEIL_OUTLINE_SYNC: oSeq=$outlineSeq updated=$updated '
        'unchanged=$unchanged empty=false r=${circle.radiusMeters.round()}m '
        'px=${this._radiusPxForCircle(circle).toStringAsFixed(1)} '
        'dOutline=${_exitDebugDelta(previousOutlineRadius, circle.radiusMeters)} '
        'inputSeq=$_exitDebugInputSeq '
        'inputDelta=${_exitDebugDelta(_exitDebugLastInputRadiusM, circle.radiusMeters)} '
        'nativeSeq=$_exitDebugNativePaintSeq '
        'nativeDelta=${_exitDebugDelta(_exitDebugLastNativePaintRadiusM, circle.radiusMeters)} '
        'maskSeq=$_exitDebugMaskSeq '
        'maskDelta=${_exitDebugDelta(_exitDebugLastMaskRadiusM, circle.radiusMeters)} '
        'bytes=${data.length} seg=$segments ms=${sw.elapsedMilliseconds} '
        'reason=$reason $ringStats $screenStats ${_assignDebugState()}',
      );
    }
  }

  Future<void> _updateVeil(
    StyleController style,
    AlarmProvider alarmProv, {
    bool ignoreAssign = false,
    bool fullQuality = true,
    String reason = 'direct',
  }) async {
    final sw = Stopwatch()..start();
    final seq = ++_veilUpdateSeq;
    final useLiveAssignHole = this._usesLiveAssignVeilHole(
      ignoreAssign: ignoreAssign,
    );
    final segments = _veilSegments(
      fullQuality: fullQuality,
      useLiveAssignHole: useLiveAssignHole,
    );
    final leaveAlarms = alarmProv.alarmPoints
        .where(
          (p) =>
              p.isActive &&
              p.zoneTrigger == ZoneTrigger.onLeave &&
              !(!ignoreAssign && _isAssigning && _assignExisting?.id == p.id),
        )
        .where(
          (p) =>
              !(useLiveAssignHole &&
                  _assignExisting != null &&
                  _assignExisting!.id == p.id),
        )
        .toList();
    final liveAssignCircle = useLiveAssignHole
        ? this._currentAssignNativeVisualCircle(alarmProv)
        : null;
    final liveAssignSegments = _liveAssignVeilSegments(
      liveAssignCircle,
      fullQuality: fullQuality,
      fallbackSegments: segments,
    );
    final liveAssignRing = liveAssignCircle == null
        ? null
        : _veilHoleForRadiusCircle(
            liveAssignCircle,
            segments: liveAssignSegments,
          );
    final previousLiveMaskRadius = liveAssignCircle == null
        ? null
        : _exitDebugLastMaskRadiusM;
    final liveRadiusDeltaPx =
        liveAssignCircle == null || previousLiveMaskRadius == null
        ? 0.0
        : _exitLiveRadiusDeltaPx(liveAssignCircle, previousLiveMaskRadius);
    final suppressFastOutline =
        liveAssignCircle != null &&
        previousLiveMaskRadius != null &&
        !fullQuality &&
        reason.startsWith('assign-radius:immediate:') &&
        liveRadiusDeltaPx >= 24.0;
    final hasFastLeave = liveAssignCircle != null;
    final liveAssignDebug = liveAssignCircle == null
        ? ''
        : ' liveR=${liveAssignCircle.radiusMeters.round()}m '
              'livePx=${this._radiusPxForCircle(liveAssignCircle).toStringAsFixed(1)}';
    if (leaveAlarms.isEmpty && !hasFastLeave) {
      if (_lastVeilGeoJson != _emptyGeoJson) {
        try {
          await style.updateGeoJsonSource(id: 'veil-src', data: _emptyGeoJson);
          _lastVeilGeoJson = _emptyGeoJson;
        } catch (_) {}
      }
      await this._syncLiveExitVeilOutlineSource(
        style,
        circle: null,
        ring: null,
        segments: liveAssignSegments,
        reason: reason,
      );
      await this._syncAssignExitVeilOutlineMode(
        style,
        active: false,
        reason: reason,
      );
      sw.stop();
      if (this._shouldLogVeilSync(reason, sw.elapsedMilliseconds)) {
        DebugConsole.log(
          'VEIL_SYNC: seq=$seq empty=true ms=${sw.elapsedMilliseconds} '
          'ignore=$ignoreAssign live=$useLiveAssignHole leaves=0 '
          'full=$fullQuality reason=$reason ${_assignDebugState()}',
        );
      }
      return;
    }

    final holes = <List<List<double>>>[];
    for (final p in leaveAlarms) {
      double r = p.radiusMeters;
      if (p.triggerType == TriggerType.time && p.timeTrigger != null) {
        r = math.max(
          200.0,
          (_speedKmh / 3.6) * p.timeTrigger!.inSeconds.toDouble(),
        );
      }
      holes.add(_geoCircle(p.longitude, p.latitude, r, segments: segments));
    }
    if (liveAssignRing != null) {
      holes.add(liveAssignRing);
    }

    final coords = <List<List<double>>>[
      [
        [-180, -85],
        [180, -85],
        [180, 85],
        [-180, 85],
        [-180, -85],
      ],
      ...holes,
    ];

    final veilGeoJson = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {'type': 'Polygon', 'coordinates': coords},
          'properties': {},
        },
      ],
    });

    if (suppressFastOutline) {
      await _suppressExitVeilOutlineForFastSwipe(
        style,
        deltaPx: liveRadiusDeltaPx,
        reason: reason,
      );
    }

    final maskUnchanged = _lastVeilGeoJson == veilGeoJson;
    var maskUpdated = false;
    if (!maskUnchanged) {
      maskUpdated = await this._tryUpdateGeoJsonSource(
        style,
        id: 'veil-src',
        data: veilGeoJson,
      );
      if (maskUpdated) _lastVeilGeoJson = veilGeoJson;
    }
    if (liveAssignCircle != null) {
      final previousMaskRadius = previousLiveMaskRadius;
      final maskDelta = previousMaskRadius == null
          ? 0.0
          : liveAssignCircle.radiusMeters - previousMaskRadius;
      final maskSeq = ++_exitDebugMaskSeq;
      _exitDebugLastMaskRadiusM = liveAssignCircle.radiusMeters;
      if (this._shouldLogExitDebugTrace(
        reason: reason,
        elapsedMs: sw.elapsedMilliseconds,
        radiusDeltaM: maskDelta,
        force: !maskUpdated && !maskUnchanged,
      )) {
        final ringStats = liveAssignRing == null
            ? 'ring=null'
            : this._exitDebugRingStats(
                liveAssignCircle,
                liveAssignRing,
                segments: liveAssignSegments,
              );
        final screenStats = liveAssignRing == null
            ? 'screenRing=null'
            : this._exitDebugScreenRingStats(
                liveAssignCircle,
                liveAssignRing,
                segments: liveAssignSegments,
              );
        DebugConsole.log(
          'VEIL_MASK_SYNC: mSeq=$maskSeq updated=$maskUpdated '
          'unchanged=$maskUnchanged r=${liveAssignCircle.radiusMeters.round()}m '
          'px=${this._radiusPxForCircle(liveAssignCircle).toStringAsFixed(1)} '
          'dMask=${_exitDebugDelta(previousMaskRadius, liveAssignCircle.radiusMeters)} '
          'inputSeq=$_exitDebugInputSeq '
          'inputDelta=${_exitDebugDelta(_exitDebugLastInputRadiusM, liveAssignCircle.radiusMeters)} '
          'nativeSeq=$_exitDebugNativePaintSeq '
          'nativeDelta=${_exitDebugDelta(_exitDebugLastNativePaintRadiusM, liveAssignCircle.radiusMeters)} '
          'outlineSeq=$_exitDebugOutlineSeq '
          'outlineDelta=${_exitDebugDelta(_exitDebugLastOutlineRadiusM, liveAssignCircle.radiusMeters)} '
          'bytes=${veilGeoJson.length} leaves=${leaveAlarms.length} '
          'holes=${holes.length} seg=$segments liveSeg=$liveAssignSegments ms=${sw.elapsedMilliseconds} '
          'reason=$reason $ringStats $screenStats ${_assignDebugState()}',
        );
      }
    } else {
      _exitDebugLastMaskRadiusM = null;
    }
    await this._syncLiveExitVeilOutlineSource(
      style,
      circle: liveAssignCircle,
      ring: liveAssignRing,
      segments: liveAssignSegments,
      reason: reason,
    );
    await _syncAssignExitVeilOutlineMode(
      style,
      active: liveAssignCircle != null,
      reason: reason,
    );
    sw.stop();
    if (this._shouldLogVeilSync(reason, sw.elapsedMilliseconds)) {
      DebugConsole.log(
        'VEIL_SYNC: seq=$seq empty=false ms=${sw.elapsedMilliseconds} '
        'ignore=$ignoreAssign live=$useLiveAssignHole leaves=${leaveAlarms.length} '
        'fastLeave=$hasFastLeave holes=${holes.length} seg=$segments liveSeg=$liveAssignSegments '
        '$liveAssignDebug full=$fullQuality reason=$reason '
        '${_assignDebugState()}',
      );
    }
  }
}
