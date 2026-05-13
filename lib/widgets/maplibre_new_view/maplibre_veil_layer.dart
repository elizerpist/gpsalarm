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

  bool _shouldHideLiveVeilOutline({
    required bool ignoreAssign,
    required bool fullQuality,
  }) {
    return !ignoreAssign &&
        !fullQuality &&
        _isAssigning &&
        _isDraggingRadius &&
        _assignVisualOwner == _AssignVisualOwner.nativeLive &&
        !_assignFlutterPreviewActive &&
        _assignActive &&
        _assignZoneTrigger == ZoneTrigger.onLeave &&
        (_showAssignOverlay || _useNativeExistingAssignLayer);
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

  Duration get _veilSyncDelay {
    final isLiveExitDrag = _shouldHideLiveVeilOutline(
      ignoreAssign: _veilSyncRequestedIgnoreAssign,
      fullQuality: _veilSyncRequestedFullQuality,
    );
    if (isLiveExitDrag) return const Duration(milliseconds: 32);
    return const Duration(milliseconds: 16);
  }

  Future<void> _setLiveVeilOutlineHidden(bool hidden) async {
    if (_liveVeilOutlineHidden == hidden) return;
    final style = _controller?.style;
    if (style == null) return;
    if (!hidden && _assignPreviewVeilHidden) {
      _liveVeilOutlineHidden = false;
      return;
    }
    final changed = await this._setNativeLayerPaintProperty(
      style,
      layerId: 'veil-outline',
      property: 'line-opacity',
      value: hidden ? 0.0 : 1.0,
    );
    if (changed) {
      _liveVeilOutlineHidden = hidden;
    }
  }

  void _armVeilSyncTimer() {
    if (_veilSyncDrainFuture != null || _veilSyncTimer != null) return;
    _veilSyncTimer = Timer(_veilSyncDelay, () {
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

  Future<void> _syncAssignVeilWithOverlay({required String debugReason}) {
    if (_assignVisualOwner != _AssignVisualOwner.nativeLive ||
        _assignFlutterPreviewActive) {
      return Future<void>.value();
    }
    if (!_isAssigning ||
        !_assignActive ||
        _assignZoneTrigger != ZoneTrigger.onLeave ||
        !(_showAssignOverlay || _useNativeExistingAssignLayer)) {
      return Future<void>.value();
    }
    return this._flushVeilSync(
      fullQuality: false,
      reason: 'assign-overlay:$debugReason',
    );
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

  int _liveAssignVeilSegments() {
    final radiusPx = math.max(_radiusNotifier.value, this._currentRadiusPx);
    if (radiusPx >= 80) return 64;
    if (radiusPx >= 48) return 48;
    return 32;
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
    final useLiveAssignHole =
        !ignoreAssign &&
        _isAssigning &&
        _assignVisualOwner == _AssignVisualOwner.nativeLive &&
        !_assignFlutterPreviewActive &&
        _assignActive &&
        _assignZoneTrigger == ZoneTrigger.onLeave &&
        (_showAssignOverlay || _useNativeExistingAssignLayer);
    await this._setLiveVeilOutlineHidden(
      _shouldHideLiveVeilOutline(
        ignoreAssign: ignoreAssign,
        fullQuality: fullQuality,
      ),
    );
    final segments = fullQuality
        ? 128
        : (useLiveAssignHole ? _liveAssignVeilSegments() : 32);
    final leaveAlarms = alarmProv.alarmPoints
        .where(
          (p) =>
              p.isActive &&
              p.zoneTrigger == ZoneTrigger.onLeave &&
              !(!ignoreAssign &&
                  _isAssigning &&
                  _assignExisting?.id == p.id),
        )
        .where(
          (p) =>
              !(useLiveAssignHole &&
                  _assignExisting != null &&
                  _assignExisting!.id == p.id),
        )
        .toList();
    final hasFastLeave = useLiveAssignHole;

    if (leaveAlarms.isEmpty && !hasFastLeave) {
      if (_lastVeilGeoJson != _emptyGeoJson) {
        try {
          await style.updateGeoJsonSource(id: 'veil-src', data: _emptyGeoJson);
          _lastVeilGeoJson = _emptyGeoJson;
        } catch (_) {}
      }
      sw.stop();
      if (_isAssigning &&
          (_shouldLogAssignFrame(_assignSyncSeq) ||
              sw.elapsedMilliseconds > 8)) {
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
    if (hasFastLeave) {
      final r = _assignTriggerType == TriggerType.time
          ? math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60)
          : _assignRadius;
      holes.add(_geoCircle(_assignLng, _assignLat, r, segments: segments));
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

    try {
      if (_lastVeilGeoJson != veilGeoJson) {
        await style.updateGeoJsonSource(id: 'veil-src', data: veilGeoJson);
        _lastVeilGeoJson = veilGeoJson;
      }
    } catch (_) {}
    sw.stop();
    if ((_isAssigning && _shouldLogAssignFrame(_assignSyncSeq)) ||
        sw.elapsedMilliseconds > 8) {
      DebugConsole.log(
        'VEIL_SYNC: seq=$seq empty=false ms=${sw.elapsedMilliseconds} '
        'ignore=$ignoreAssign live=$useLiveAssignHole leaves=${leaveAlarms.length} '
        'fastLeave=$hasFastLeave holes=${holes.length} seg=$segments '
        'full=$fullQuality reason=$reason ${_assignDebugState()}',
      );
    }
  }
}
