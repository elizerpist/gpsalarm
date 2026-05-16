import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:jni/jni.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:maplibre/maplibre.dart';
// ignore: implementation_imports
import 'package:maplibre/src/platform/android/jni.dart' as maplibre_jni;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../models/alarm_point.dart';
import '../models/app_settings.dart';
import '../providers/alarm_provider.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/map_controls.dart';
import '../widgets/search_pill.dart';
import '../widgets/alarm_card.dart';
import '../widgets/offline_indicator.dart';
import '../services/location_service.dart';
import '../services/alarm_service.dart';
import '../services/alarm_delivery_service.dart';
import '../services/permission_service.dart';
import '../services/debug_console.dart';
import '../widgets/alarm_marker_renderer.dart';
import '../widgets/scale_bar.dart';

part 'maplibre_new_view/maplibre_assign_lifecycle.dart';
part 'maplibre_new_view/maplibre_assign_marker.dart';
part 'maplibre_new_view/maplibre_geometry.dart';
part 'maplibre_new_view/maplibre_overlay_painter.dart';
part 'maplibre_new_view/maplibre_radius_data.dart';
part 'maplibre_new_view/maplibre_radius_layer_init.dart';
part 'maplibre_new_view/maplibre_radius_layer_rebuild.dart';
part 'maplibre_new_view/maplibre_radius_sync.dart';
part 'maplibre_new_view/maplibre_style_state.dart';
part 'maplibre_new_view/maplibre_style_urls.dart';
part 'maplibre_new_view/maplibre_user_location_layer.dart';
part 'maplibre_new_view/maplibre_tap_handling.dart';
part 'maplibre_new_view/maplibre_veil_layer.dart';

enum _AssignVisualOwner { nativeLive, transitionPending }

class MaplibreNewView extends StatefulWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  const MaplibreNewView({super.key, required this.scaffoldKey});

  @override
  State<MaplibreNewView> createState() => _MaplibreNewViewState();
}

class _MaplibreNewViewState extends State<MaplibreNewView>
    with SingleTickerProviderStateMixin {
  MapController? _controller;
  bool _imagesRegistered = false;
  bool _radiusLayerReady = false;
  String? _activeStyleUrl;
  String? _registeredStyleUrl;
  int _styleGeneration = 0;
  int? _androidGeoJsonSyncViewId;
  final LocationService _locationService = LocationService();
  // 3D view + GPS follow + compass
  static const Duration _minCompassCameraInterval = Duration(milliseconds: 32);
  static const Duration _compassRenderInterval = Duration(milliseconds: 24);
  static const double _compassSmoothingGain = 0.72;
  static const double _compassFastTurnGain = 1.0;
  static const double _compassFastTurnDelta = 6.0;
  static const double _compassFastTurnRateDegPerSec = 120.0;
  static const double _compassRenderSlowGain = 0.55;
  static const double _compassRenderMediumGain = 0.72;
  static const double _compassRenderFastGain = 0.92;
  static const double _compassRenderMediumDelta = 3.0;
  static const double _compassRenderFastDelta = 12.0;
  static const double _compassMinCameraDelta = 0.45;
  bool _is3D = false;
  bool _gpsFollow = false;
  double _lastBearing = 0;
  double _lastCameraBearing = 0;
  double? _lastRawCompassHeading;
  DateTime _lastCompassCameraUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _compassRenderTimer;
  DateTime? _lastCompassEventAt;
  int _compassEventSeq = 0;
  int _compassCameraSeq = 0;
  int _compassRenderSeq = 0;
  int _compassSkipSeq = 0;
  double _compassEventDtSumMs = 0;
  int _compassEventDtCount = 0;
  double _compassCameraIntervalSumMs = 0;
  int _compassCameraIntervalCount = 0;
  double _compassMaxRawLag = 0;
  double _compassMaxCameraLag = 0;
  StreamSubscription<CompassEvent>? _compassSub;
  bool _resumeCompassAfterAssign = false;
  // 3D button eject animation
  late final AnimationController _3dButtonAnim;
  late final Animation<double> _3dButtonSlide;
  bool _3dButtonVisible = true;
  bool _cameraAtUser = true; // true = my-location button becomes 3D toggle
  // Unified assign state
  bool _isAssigning = false;
  AlarmPoint? _assignExisting;
  double _assignLat = 0;
  double _assignLng = 0;
  double _assignRadius = 500;
  TriggerType _assignTriggerType = TriggerType.distance;
  ZoneTrigger _assignZoneTrigger = ZoneTrigger.onEntry;
  int _assignTimeMinutes = 10;
  bool _assignActive = true;
  bool _isDraggingRadius = false;
  int? _dragPointerId;
  double? _radiusDragStartDistancePx;
  double? _radiusDragStartRadiusM;
  double _currentZoom = 13;
  bool _zoomInitialized = false;
  double _deviceDpr = 1.0;
  double _speedKmh = 0;
  Position? _userPos;
  String _lastUserLocationGeoJson = '';
  bool _userLocationLayerReady = false;
  Offset? _lastPointerDownPos;
  Offset? _assignScreenCenter;
  Uint8List? _assignMarkerPng;
  String? _assignMarkerKey;
  Size _assignMarkerSize = Size.zero;
  int _assignMarkerVersion = 0;
  String? _assignLiveMarkerChipKey;
  int _assignLiveMarkerChipVersion = 0;
  String? _assignNativeAlarmLayerId;
  bool _closingAssignCircle = false;
  bool _assignNativeHidden = false;
  bool _assignOverlayActivating = false;
  bool _assignFlutterPreviewActive = false;
  bool _assignPreviewCircleHidden = false;
  bool _assignPreviewVeilHidden = false;
  bool _assignPreviewLabelHidden = false;
  bool _assignNativeLiveVeilActive = false;
  String? _nativeLiveExitVeilSourceKey;
  bool _assignExitVeilOutlineActive = false;
  bool _assignExitVeilOutlineFastSuppressed = false;
  double _assignExitVeilOutlineOpacity = -1.0;
  Timer? _assignExitVeilOutlineRestoreTimer;
  Timer? _liveExitVeilHandoffTimer;
  String _lastVeilOutlineGeoJson = '';
  _AssignVisualOwner _assignVisualOwner = _AssignVisualOwner.nativeLive;
  bool _closingAssignMarker = false;
  Timer? _assignVisualClearTimer;
  Completer<String>? _nativeRenderAckCompleter;
  Timer? _nativeRenderAckTimeout;
  final Map<String, Uint8List> _markerBitmapCache = {};
  final Map<String, Size> _markerSizeCache = {};
  final Map<String, String> _registeredMarkerImageKeys = {};
  final Map<String, String> _radiusPointImageIds = {};
  final Map<String, String> _radiusCircleLayerKeys = {};
  final Set<String> _radiusVisualIds = {};
  final Set<String> _radiusPaintOverrideIds = {};
  final Map<String, int> _radiusPaintOverrideTokens = {};
  int _radiusPaintOverrideTokenSeq = 0;
  bool? _nativeCircleRadiusPaintAvailable;
  String? _fastCircleLayerKey;
  // Overlay radius notifier — drives CustomPainter repaint without setState
  final ValueNotifier<double> _radiusNotifier = ValueNotifier(500);
  // Speed interpolation
  double _prevGpsSpeed = 0;
  double _currentGpsSpeed = 0;
  DateTime _prevGpsTime = DateTime.now();
  DateTime _currentGpsTime = DateTime.now();
  Timer? _speedInterpolTimer;

  @override
  void initState() {
    super.initState();
    _3dButtonAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _3dButtonSlide = CurvedAnimation(
      parent: _3dButtonAnim,
      curve: Curves.elasticOut,
    );
    // Eject animation: starts hidden, springs to final position
    _3dButtonAnim.value = 0.0;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _3dButtonAnim.forward();
    });
    _initLocation();
    _startSpeedInterpolation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _deviceDpr = MediaQuery.devicePixelRatioOf(context);
    if (!_zoomInitialized) {
      _zoomInitialized = true;
      _currentZoom = context.read<MapProvider>().zoom;
      DebugConsole.log(
        'VECTOR_INIT: zoom from MapProvider=${_currentZoom.toStringAsFixed(2)} center=${context.read<MapProvider>().center} dpr=$_deviceDpr',
      );
    }
  }

  /// 60fps speed interpolation between GPS ticks.
  void _startSpeedInterpolation() {
    _speedInterpolTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      final gpsInterval = _currentGpsTime
          .difference(_prevGpsTime)
          .inMilliseconds;
      double estimated;
      if (gpsInterval <= 0) {
        estimated = _currentGpsSpeed;
      } else {
        final accelPerMs = (_currentGpsSpeed - _prevGpsSpeed) / gpsInterval;
        final elapsed = DateTime.now()
            .difference(_currentGpsTime)
            .inMilliseconds;
        estimated = (_currentGpsSpeed + accelPerMs * elapsed).clamp(0.0, 300.0);
        if (elapsed > gpsInterval * 2) estimated = _currentGpsSpeed;
      }
      if ((estimated - _speedKmh).abs() > 0.05) {
        _speedKmh = estimated;
        // Update overlay radius if time-based trigger is active
        if (_isAssigning && _assignTriggerType == TriggerType.time) {
          _radiusNotifier.value = this._currentRadiusPx;
        }
      }
    });
  }

  Future<void> _initLocation() async {
    final hasPermission = await _locationService.requestPermission();
    if (hasPermission) {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null && mounted) {
        setState(() => _userPos = Position(pos.longitude, pos.latitude));
        _safeMoveCamera(
          center: Position(pos.longitude, pos.latitude),
          zoom: 14,
        );
      }
      _locationService.startTracking(
        onPosition: (position) {
          if (!mounted) return;
          final newPos = Position(position.longitude, position.latitude);
          if (_userPos == null ||
              AlarmService.distanceMeters(
                    _userPos!.lat.toDouble(),
                    _userPos!.lng.toDouble(),
                    position.latitude,
                    position.longitude,
                  ) >
                  5) {
            setState(() => _userPos = newPos);
          }
          unawaited(_checkAlarms(position.latitude, position.longitude));
          // GPS follow: auto-center + bearing in 3D mode
          // GPS follow: auto-center (bearing handled by compass stream, not GPS heading)
          if (_gpsFollow) {
            _safeAnimateCamera(
              center: newPos,
              nativeDuration: const Duration(milliseconds: 1500),
            );
          }
          // Feed speed interpolation
          final newSpeed = _locationService.averageSpeedKmh;
          _prevGpsSpeed = _currentGpsSpeed;
          _prevGpsTime = _currentGpsTime;
          _currentGpsSpeed = newSpeed;
          _currentGpsTime = DateTime.now();
        },
      );
    }
  }

  double _effectiveAlarmRadius(AlarmPoint point) {
    if (point.triggerType == TriggerType.time && point.timeTrigger != null) {
      final speedMs = _speedKmh / 3.6;
      return math.max(200.0, speedMs * point.timeTrigger!.inSeconds.toDouble());
    }
    return point.radiusMeters;
  }

  bool _alarmContainsUser(AlarmPoint point, double userLat, double userLng) {
    return AlarmService.isWithinRadius(
      userLat: userLat,
      userLng: userLng,
      pointLat: point.latitude,
      pointLng: point.longitude,
      radiusMeters: _effectiveAlarmRadius(point),
    );
  }

  void _seedAlarmInsideState(AlarmPoint point) {
    final pos = _userPos;
    if (pos == null) return;
    _alarmInsideState[point.id] = _alarmContainsUser(
      point,
      pos.lat.toDouble(),
      pos.lng.toDouble(),
    );
  }

  Future<void> _checkAlarms(double userLat, double userLng) async {
    final alarmProv = context.read<AlarmProvider>();
    final settings = context.read<SettingsProvider>().settings;
    final activeIds = alarmProv.alarmPoints
        .where((p) => p.isActive)
        .map((p) => p.id)
        .toSet();
    _alarmInsideState.removeWhere((id, _) => !activeIds.contains(id));

    for (final point in alarmProv.alarmPoints.where((p) => p.isActive)) {
      final distance = AlarmService.distanceMeters(
        userLat,
        userLng,
        point.latitude,
        point.longitude,
      );
      final isInside = _alarmContainsUser(point, userLat, userLng);
      final wasInside = _alarmInsideState[point.id];
      _alarmInsideState[point.id] = isInside;
      if (wasInside == null) continue;

      final shouldTrigger = point.zoneTrigger == ZoneTrigger.onEntry
          ? !wasInside && isInside
          : wasInside && !isInside;

      if (shouldTrigger) {
        DebugConsole.log('ALARM TRIGGERED: ${point.name ?? point.id}');
        await alarmProv.setActive(point.id, false);
        if (!mounted) return;
        await AlarmDeliveryService.trigger(
          context: context,
          point: point,
          settings: settings,
          distanceMeters: distance,
        );
      }
    }
  }

  @override
  void dispose() {
    _3dButtonAnim.dispose();
    _compassSub?.cancel();
    _compassRenderTimer?.cancel();
    _radiusDebounce?.cancel();
    _assignVisualClearTimer?.cancel();
    _assignExitVeilOutlineRestoreTimer?.cancel();
    _liveExitVeilHandoffTimer?.cancel();
    _nativeRenderAckTimeout?.cancel();
    final pendingAck = _nativeRenderAckCompleter;
    if (pendingAck != null && !pendingAck.isCompleted) {
      pendingAck.complete('dispose');
    }
    _assignOverlaySyncTimer?.cancel();
    _assignCardSyncTimer?.cancel();
    _veilSyncTimer?.cancel();
    _speedInterpolTimer?.cancel();
    _radiusNotifier.dispose();
    _locationService.dispose();
    super.dispose();
  }

  void _onMapCreated(MapController controller) {
    _controller = controller;
    DebugConsole.log('VECTOR: MapController created');
    DebugConsole.log('VECTOR: controller type = ${controller.runtimeType}');
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventIdle) {
      _completeNativeRenderAck('idle');
    }

    if (!mounted) return;
    if (event is MapEventClick) {
      _onTap(event.point);
      return;
    }
    if (event is! MapEventMoveCamera && event is! MapEventCameraIdle) {
      return;
    }

    final newZoom = _controller?.camera?.zoom ?? _currentZoom;
    if ((newZoom - _currentZoom).abs() > 0.05) {
      setState(() => _currentZoom = newZoom);
    }
    // Only sync to MapProvider AFTER images registered (style fully loaded).
    // Before that, camera events carry the style's default zoom, not the user's.
    if (!_imagesRegistered) return;
    final mp = context.read<MapProvider>();
    mp.updateZoomSilent(newZoom);
    final cam = _controller?.camera;
    if (cam?.center == null) return;
    mp.updateCenterSilent(
      LatLng(cam!.center.lat.toDouble(), cam.center.lng.toDouble()),
    );
    if (_userPos == null) return;
    final dist = AlarmService.distanceMeters(
      cam.center.lat.toDouble(),
      cam.center.lng.toDouble(),
      _userPos!.lat.toDouble(),
      _userPos!.lng.toDouble(),
    );
    final atUser = dist < 100;
    if (atUser != _cameraAtUser) setState(() => _cameraAtUser = atUser);
  }

  void _completeNativeRenderAck(String source) {
    final completer = _nativeRenderAckCompleter;
    if (completer == null || completer.isCompleted) return;
    _nativeRenderAckTimeout?.cancel();
    _nativeRenderAckTimeout = null;
    completer.complete(source);
  }

  Future<void> _waitForNativeRenderAck({
    required String reason,
    Duration timeout = const Duration(milliseconds: 96),
  }) async {
    final previous = _nativeRenderAckCompleter;
    if (previous != null && !previous.isCompleted) {
      previous.complete('superseded');
    }
    _nativeRenderAckTimeout?.cancel();
    final completer = Completer<String>();
    _nativeRenderAckCompleter = completer;
    _nativeRenderAckTimeout = Timer(timeout, () {
      _completeNativeRenderAck('timeout:${timeout.inMilliseconds}ms');
    });
    final source = await completer.future;
    if (identical(_nativeRenderAckCompleter, completer)) {
      _nativeRenderAckCompleter = null;
      _nativeRenderAckTimeout?.cancel();
      _nativeRenderAckTimeout = null;
    }
    if (_isAssigning || _assignFlutterPreviewActive) {
      DebugConsole.log(
        'NATIVE_RENDER_ACK: reason=$reason source=$source ${_assignDebugState()}',
      );
    }
  }

  void _safeMoveCamera({
    Position? center,
    double? zoom,
    double? bearing,
    double? pitch,
  }) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller
          .moveCamera(
            center: center,
            zoom: zoom,
            bearing: bearing,
            pitch: pitch,
          )
          .catchError((_) {}),
    );
  }

  void _safeAnimateCamera({
    Position? center,
    double? zoom,
    double? bearing,
    double? pitch,
    Duration nativeDuration = const Duration(seconds: 2),
  }) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller
          .animateCamera(
            center: center,
            zoom: zoom,
            bearing: bearing,
            pitch: pitch,
            nativeDuration: nativeDuration,
          )
          .catchError((_) {}),
    );
  }

  double _normalizeBearing(double value) => (value % 360 + 360) % 360;

  double _bearingDelta(double from, double to) {
    return (to - from + 540) % 360 - 180;
  }

  bool _shouldLogCompassFrame(int frame) => frame <= 3 || frame % 20 == 0;

  double _compassGainFor(double rawDelta, double turnRateDegPerSec) {
    if (rawDelta.abs() >= _compassFastTurnDelta ||
        turnRateDegPerSec.abs() >= _compassFastTurnRateDegPerSec) {
      return _compassFastTurnGain;
    }
    return _compassSmoothingGain;
  }

  double _compassRenderGainFor(double cameraDelta) {
    final absDelta = cameraDelta.abs();
    if (absDelta >= _compassRenderFastDelta) {
      return _compassRenderFastGain;
    }
    if (absDelta >= _compassRenderMediumDelta) {
      return _compassRenderMediumGain;
    }
    return _compassRenderSlowGain;
  }

  void _recordCompassEventDt(int? eventDtMs) {
    if (eventDtMs == null || eventDtMs < 0) return;
    _compassEventDtSumMs += eventDtMs;
    _compassEventDtCount++;
  }

  void _recordCompassCameraInterval(Duration interval) {
    final ms = interval.inMilliseconds;
    if (ms < 0) return;
    _compassCameraIntervalSumMs += ms;
    _compassCameraIntervalCount++;
  }

  void _recordCompassLag({required double rawLag, required double cameraLag}) {
    _compassMaxRawLag = math.max(_compassMaxRawLag, rawLag.abs());
    _compassMaxCameraLag = math.max(_compassMaxCameraLag, cameraLag.abs());
  }

  String _formatCompassStat(double value) {
    if (!value.isFinite) return 'n/a';
    return value.toStringAsFixed(1);
  }

  void _logCompassStatsIfNeeded(int seq) {
    if (seq == 0 || seq % 60 != 0) return;
    final avgEventDt = _compassEventDtCount == 0
        ? double.nan
        : _compassEventDtSumMs / _compassEventDtCount;
    final avgCameraInterval = _compassCameraIntervalCount == 0
        ? double.nan
        : _compassCameraIntervalSumMs / _compassCameraIntervalCount;
    final eventHz = avgEventDt.isFinite && avgEventDt > 0
        ? 1000.0 / avgEventDt
        : double.nan;
    final cameraHz = avgCameraInterval.isFinite && avgCameraInterval > 0
        ? 1000.0 / avgCameraInterval
        : double.nan;
    final cameraPerEvent = _compassEventSeq == 0
        ? 0.0
        : _compassCameraSeq / _compassEventSeq;
    DebugConsole.log(
      'COMPASS_STATS: events=$_compassEventSeq cameras=$_compassCameraSeq '
      'renders=$_compassRenderSeq skips=$_compassSkipSeq '
      'cameraPerEvent=${cameraPerEvent.toStringAsFixed(2)} '
      'avgEventDt=${_formatCompassStat(avgEventDt)}ms '
      'eventHz=${_formatCompassStat(eventHz)} '
      'avgCameraInterval=${_formatCompassStat(avgCameraInterval)}ms '
      'cameraHz=${_formatCompassStat(cameraHz)} '
      'maxRawLag=${_compassMaxRawLag.toStringAsFixed(1)} '
      'maxCameraLag=${_compassMaxCameraLag.toStringAsFixed(1)}',
    );
  }

  void _startCompassFollow() {
    _compassSub?.cancel();
    _stopCompassRenderPump();
    _lastCompassCameraUpdate = DateTime.now().subtract(
      _minCompassCameraInterval,
    );
    _lastCompassEventAt = null;
    _lastRawCompassHeading = null;
    _compassEventSeq = 0;
    _compassCameraSeq = 0;
    _compassRenderSeq = 0;
    _compassSkipSeq = 0;
    _compassEventDtSumMs = 0;
    _compassEventDtCount = 0;
    _compassCameraIntervalSumMs = 0;
    _compassCameraIntervalCount = 0;
    _compassMaxRawLag = 0;
    _compassMaxCameraLag = 0;
    final events = FlutterCompass.events;
    if (events != null) {
      _compassSub = events.listen(_handleCompassEvent);
      _startCompassRenderPump();
    } else {
      _compassSub = null;
    }
    DebugConsole.log(
      'COMPASS_START: available=${events != null} is3d=$_is3D '
      'follow=$_gpsFollow bearing=${_lastBearing.toStringAsFixed(1)} '
      'camera=${_lastCameraBearing.toStringAsFixed(1)} '
      'eventMinInterval=${_minCompassCameraInterval.inMilliseconds}ms '
      'renderInterval=${_compassRenderInterval.inMilliseconds}ms '
      'targetGain=$_compassSmoothingGain fastTargetGain=$_compassFastTurnGain '
      'fastDelta=$_compassFastTurnDelta '
      'fastRate=$_compassFastTurnRateDegPerSec '
      'renderGains=$_compassRenderSlowGain/$_compassRenderMediumGain/$_compassRenderFastGain '
      'minDelta=$_compassMinCameraDelta',
    );
  }

  void _startCompassRenderPump() {
    _compassRenderTimer?.cancel();
    _lastCompassCameraUpdate = DateTime.now().subtract(_compassRenderInterval);
    _compassRenderTimer = Timer.periodic(_compassRenderInterval, (_) {
      _pumpCompassCamera();
    });
  }

  void _stopCompassRenderPump() {
    _compassRenderTimer?.cancel();
    _compassRenderTimer = null;
  }

  void _stopCompassFollow() {
    final wasActive = _compassSub != null || _compassRenderTimer != null;
    _compassSub?.cancel();
    _compassSub = null;
    _stopCompassRenderPump();
    if (wasActive) {
      DebugConsole.log(
        'COMPASS_STOP: events=$_compassEventSeq cameras=$_compassCameraSeq '
        'renders=$_compassRenderSeq skips=$_compassSkipSeq '
        'bearing=${_lastBearing.toStringAsFixed(1)} '
        'camera=${_lastCameraBearing.toStringAsFixed(1)} '
        'maxRawLag=${_compassMaxRawLag.toStringAsFixed(1)} '
        'maxCameraLag=${_compassMaxCameraLag.toStringAsFixed(1)}',
      );
    }
  }

  void _handleCompassEvent(CompassEvent event) {
    if (!_is3D || !_gpsFollow) return;
    final now = DateTime.now();
    final eventDt = _lastCompassEventAt == null
        ? null
        : now.difference(_lastCompassEventAt!).inMilliseconds;
    _lastCompassEventAt = now;
    final seq = ++_compassEventSeq;
    _recordCompassEventDt(eventDt);

    final rawHeading = event.heading;
    if (rawHeading == null) {
      _compassSkipSeq++;
      if (_shouldLogCompassFrame(seq)) {
        DebugConsole.log(
          'COMPASS_SKIP: seq=$seq reason=null-heading path=sensor '
          'eventDt=${eventDt ?? -1}ms',
        );
      }
      _logCompassStatsIfNeeded(seq);
      return;
    }

    final heading = _normalizeBearing(rawHeading);
    _lastRawCompassHeading = heading;
    final rawDelta = _bearingDelta(_lastBearing, heading);
    final turnRateDegPerSec = eventDt != null && eventDt > 0
        ? rawDelta / (eventDt / 1000.0)
        : 0.0;
    final gain = _compassGainFor(rawDelta, turnRateDegPerSec);
    _lastBearing = _normalizeBearing(_lastBearing + rawDelta * gain);

    final rawLag = _bearingDelta(_lastBearing, heading);
    final cameraLag = _bearingDelta(_lastCameraBearing, heading);
    final targetDelta = _bearingDelta(_lastCameraBearing, _lastBearing);
    _recordCompassLag(rawLag: rawLag, cameraLag: cameraLag);

    final shouldLog = _shouldLogCompassFrame(seq);
    if (shouldLog ||
        rawDelta.abs() >= _compassFastTurnDelta ||
        turnRateDegPerSec.abs() >= _compassFastTurnRateDegPerSec ||
        cameraLag.abs() >= 12.0) {
      DebugConsole.log(
        'COMPASS_TARGET: seq=$seq eventDt=${eventDt ?? -1}ms '
        'raw=${heading.toStringAsFixed(1)} '
        'rawDelta=${rawDelta.toStringAsFixed(1)} '
        'turnRate=${turnRateDegPerSec.toStringAsFixed(1)} '
        'target=${_lastBearing.toStringAsFixed(1)} '
        'camera=${_lastCameraBearing.toStringAsFixed(1)} '
        'targetDelta=${targetDelta.toStringAsFixed(1)} '
        'rawLag=${rawLag.toStringAsFixed(1)} '
        'cameraLag=${cameraLag.toStringAsFixed(1)} '
        'gain=$gain',
      );
    }
    _logCompassStatsIfNeeded(seq);
  }

  void _pumpCompassCamera() {
    if (!_is3D || !_gpsFollow || _compassEventSeq == 0) return;
    final now = DateTime.now();
    final interval = now.difference(_lastCompassCameraUpdate);
    final cameraDelta = _bearingDelta(_lastCameraBearing, _lastBearing);
    final renderSeq = ++_compassRenderSeq;
    final shouldLog = _shouldLogCompassFrame(renderSeq);

    if (cameraDelta.abs() < _compassMinCameraDelta) {
      _compassSkipSeq++;
      if (shouldLog || interval.inMilliseconds > 120) {
        DebugConsole.log(
          'COMPASS_SKIP: seq=$_compassEventSeq renderSeq=$renderSeq '
          'reason=render-small-delta path=render-pump '
          'interval=${interval.inMilliseconds}ms '
          'target=${_lastBearing.toStringAsFixed(1)} '
          'camera=${_lastCameraBearing.toStringAsFixed(1)} '
          'dCamera=${cameraDelta.toStringAsFixed(1)}',
        );
      }
      return;
    }

    final previousCameraBearing = _lastCameraBearing;
    final firstCameraUpdate = _compassCameraSeq == 0;
    final renderGain = _compassRenderGainFor(cameraDelta);
    final nextCameraBearing = _normalizeBearing(
      _lastCameraBearing + cameraDelta * renderGain,
    );
    _lastCameraBearing = nextCameraBearing;
    _lastCompassCameraUpdate = now;
    _compassCameraSeq++;
    if (!firstCameraUpdate) {
      _recordCompassCameraInterval(interval);
    }
    _safeMoveCamera(bearing: nextCameraBearing);

    final targetLag = _bearingDelta(nextCameraBearing, _lastBearing);
    final rawCameraLag = _lastRawCompassHeading == null
        ? double.nan
        : _bearingDelta(nextCameraBearing, _lastRawCompassHeading!);
    if (shouldLog ||
        cameraDelta.abs() >= 8.0 ||
        interval.inMilliseconds > 120 ||
        targetLag.abs() >= 8.0) {
      DebugConsole.log(
        'COMPASS_CAMERA: seq=$_compassEventSeq cameraSeq=$_compassCameraSeq '
        'renderSeq=$renderSeq path=render-pump '
        'interval=${interval.inMilliseconds}ms '
        'target=${_lastBearing.toStringAsFixed(1)} '
        'prevCamera=${previousCameraBearing.toStringAsFixed(1)} '
        'sent=${nextCameraBearing.toStringAsFixed(1)} '
        'dCamera=${cameraDelta.toStringAsFixed(1)} '
        'targetLag=${targetLag.toStringAsFixed(1)} '
        'rawCameraLag=${_formatCompassStat(rawCameraLag)} '
        'renderGain=$renderGain',
      );
    }
  }

  void _set3DMode({required bool enabled, bool compassFollow = true}) {
    _is3D = enabled;
    _lastRadiusDataHash = '';
    if (enabled) {
      _gpsFollow = compassFollow;
      _lastCameraBearing = _lastBearing;
      _safeMoveCamera(
        pitch: 45,
        bearing: compassFollow ? _lastBearing : _lastCameraBearing,
      );
      if (compassFollow) {
        _startCompassFollow();
      } else {
        _stopCompassFollow();
      }
    } else {
      _gpsFollow = false;
      _stopCompassFollow();
      _safeMoveCamera(pitch: 0, bearing: 0);
    }
  }

  void _toggle3DFixedMode() {
    if (!_is3D) {
      _set3DMode(enabled: true, compassFollow: false);
      return;
    }
    _gpsFollow = !_gpsFollow;
    if (_gpsFollow) {
      _lastCameraBearing = _lastBearing;
      _safeMoveCamera(pitch: 45, bearing: _lastBearing);
      _startCompassFollow();
    } else {
      _lastCameraBearing = _controller?.camera?.bearing ?? _lastCameraBearing;
      _stopCompassFollow();
      _safeMoveCamera(pitch: 45, bearing: _lastCameraBearing);
    }
  }

  void _suspendCompassForAssign() {
    if (!_is3D || !_gpsFollow) return;
    _resumeCompassAfterAssign = true;
    _gpsFollow = false;
    _lastCameraBearing = _controller?.camera?.bearing ?? _lastCameraBearing;
    _stopCompassFollow();
  }

  void _restoreCompassAfterAssign() {
    if (!_resumeCompassAfterAssign || !_is3D || !mounted) {
      _resumeCompassAfterAssign = false;
      return;
    }
    _resumeCompassAfterAssign = false;
    setState(() {
      _gpsFollow = true;
      _lastCameraBearing = _lastBearing;
      _safeMoveCamera(pitch: 45, bearing: _lastBearing);
      _startCompassFollow();
    });
  }

  Future<void> _registerImages(StyleController style, String styleUrl) async {
    if (_imagesRegistered && _registeredStyleUrl == styleUrl) return;
    final generation = _styleGeneration;
    try {
      final redPin = await _renderIconToPng(
        Icons.location_on,
        const Color(0xFFFF0000),
        160,
      );
      final greyPin = await _renderIconToPng(
        Icons.location_on,
        const Color(0xFF9E9E9E),
        160,
      );
      if (!mounted ||
          generation != _styleGeneration ||
          _activeStyleUrl != styleUrl)
        return;
      await style.addImage('pin-red', redPin);
      await style.addImage('pin-grey', greyPin);
      await this._initRadiusLayer(style);
      if (!mounted ||
          generation != _styleGeneration ||
          _activeStyleUrl != styleUrl)
        return;
      _imagesRegistered = true;
      _registeredStyleUrl = styleUrl;
      if (mounted) setState(() {});
      DebugConsole.log('VECTOR: images + radius layer registered');
    } catch (e) {
      DebugConsole.log('VECTOR: init error: $e');
    }
  }

  /// Radius circle version tracker for stale async rebuild detection.
  int _radiusLayerVersion = 0;
  Timer? _radiusDebounce;
  int _dragLogCounter = 0;
  int _cardRadiusLogCounter = 0;
  int _cardTimeLogCounter = 0;
  int _assignSyncSeq = 0;
  int _assignSyncSkipCount = 0;
  int _veilUpdateSeq = 0;
  int _exitDebugInputSeq = 0;
  int _exitDebugNativePaintSeq = 0;
  int _exitDebugOutlineSeq = 0;
  int _exitDebugMaskSeq = 0;
  double? _exitDebugLastInputRadiusM;
  double? _exitDebugLastInputRadiusPx;
  DateTime? _exitDebugLastInputAt;
  double? _exitDebugLastNativePaintRadiusM;
  double? _exitDebugLastOutlineRadiusM;
  double? _exitDebugLastMaskRadiusM;
  bool _assignExitNativeCircleSuppressed = false;
  String _lastVeilGeoJson = '';
  Timer? _veilSyncTimer;
  Future<void>? _veilSyncDrainFuture;
  bool _veilSyncRequested = false;
  bool _veilSyncRequestedIgnoreAssign = false;
  bool _veilSyncRequestedFullQuality = false;
  String? _veilSyncRequestedReason;
  bool _assignOverlayPending = false;
  bool _assignOverlayPendingMarker = false;
  bool _assignOverlayPendingRadiusOnly = false;
  String? _assignOverlayPendingReason;
  Timer? _assignOverlaySyncTimer;
  bool _assignOverlaySyncMarker = false;
  bool _assignOverlaySyncRadiusOnly = false;
  String? _assignOverlaySyncReason;
  bool _assignRadiusPaintSyncActive = false;
  bool _assignRadiusPaintSyncPending = false;
  String? _assignRadiusPaintSyncReason;
  Future<void>? _assignRadiusPaintSyncDrain;
  Timer? _assignCardSyncTimer;
  bool _assignCardSyncPending = false;
  DateTime? _lastOverlayMoveAt;
  String _lastRadiusDataHash = ''; // skip rebuild if alarm data unchanged
  bool _suppressRadiusSync = false;
  final Map<String, bool> _alarmInsideState = {};
  bool get _useNativeAssignCircle => true;

  bool _shouldLogAssignFrame(int frame) => frame <= 3 || frame % 15 == 0;

  String _assignDebugState() {
    final zoom = _controller?.camera?.zoom ?? _currentZoom;
    return 'existing=${_assignExisting?.id} owner=${_assignVisualOwner.name} '
        'nativeHidden=$_assignNativeHidden '
        'overlay=$_showAssignOverlay nativeExisting=$_useNativeExistingAssignLayer '
        'nativeVeil=$_assignNativeLiveVeilActive '
        'trigger=${_assignTriggerType.name} zone=${_assignZoneTrigger.name} '
        'active=$_assignActive r=${_assignRadius.round()}m '
        'px=${_radiusNotifier.value.toStringAsFixed(1)} '
        'zoom=${zoom.toStringAsFixed(2)}';
  }

  Position? _cachedUserPosition() {
    final cached = _userPos;
    if (cached != null) return cached;
    final last = _locationService.lastPosition;
    if (last == null) return null;
    return Position(last.longitude, last.latitude);
  }

  void _animateToUserPosition(Position target) {
    if (!mounted) return;
    setState(() {
      _userPos = target;
      _cameraAtUser = true;
    });
    _safeAnimateCamera(
      center: target,
      zoom: 15,
      pitch: _is3D ? 45 : null,
      bearing: _is3D ? (_gpsFollow ? _lastBearing : _lastCameraBearing) : null,
      nativeDuration: const Duration(milliseconds: 450),
    );
  }

  Future<void> _jumpToUserPosition() async {
    final cached = _cachedUserPosition();
    if (cached != null) {
      _animateToUserPosition(cached);
    }
    final fresh = await _locationService.getCurrentPosition();
    if (fresh == null || !mounted) return;
    final target = Position(fresh.longitude, fresh.latitude);
    if (cached != null &&
        AlarmService.distanceMeters(
              cached.lat.toDouble(),
              cached.lng.toDouble(),
              target.lat.toDouble(),
              target.lng.toDouble(),
            ) <
            5) {
      return;
    }
    _animateToUserPosition(target);
  }

  @override
  Widget build(BuildContext context) {
    final styleUrl = context.select<SettingsProvider, String>(
      (p) => _styleUrls[p.settings.vectorStyleUrl] ?? _styleUrls['liberty']!,
    );
    final alarmProv = context.watch<AlarmProvider>();

    this._prepareVectorStyle(styleUrl);
    this._syncRadiusSource(alarmProv);
    this._syncUserLocationSource(reason: 'build');

    return Stack(
      children: [
        // GestureDetector for immediate swipe + native projection for exact geo
        GestureDetector(
          onLongPressStart: _isAssigning
              ? null
              : (details) {
                  final haptic = context
                      .read<SettingsProvider>()
                      .settings
                      .hapticFeedback;
                  if (haptic) Vibration.vibrate(duration: 30);
                  _assignScreenCenter = details.localPosition;
                  _isDraggingRadius = true;
                  // Native fromScreenLocation expects physical pixels; Flutter gives logical
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  final geo = _controller?.toLngLatSync(
                    details.localPosition * dpr,
                  );
                  DebugConsole.log(
                    'LONGPRESS_START: pos=${details.localPosition} dpr=${dpr.toStringAsFixed(2)} '
                    'geo=${geo?.lat.toStringAsFixed(6)},${geo?.lng.toStringAsFixed(6)} '
                    'zoom=${_currentZoom.toStringAsFixed(2)} '
                    'mpp=${_vectorMetersPerPx(geo?.lat.toDouble() ?? 0.0, _currentZoom).toStringAsFixed(2)} '
                    'useNative=$_useNativeAssignCircle',
                  );
                  _dragLogCounter = 0;
                  _radiusDragStartDistancePx = null;
                  _radiusDragStartRadiusM = null;
                  _lastOverlayMoveAt = DateTime.now();
                  if (geo != null) {
                    unawaited(
                      this._startAssign(geo.lat.toDouble(), geo.lng.toDouble()),
                    );
                  } else {
                    unawaited(
                      this._startAssign(
                        _controller?.camera?.center?.lat.toDouble() ?? 0,
                        _controller?.camera?.center?.lng.toDouble() ?? 0,
                      ),
                    );
                  }
                },
          onLongPressMoveUpdate: !_isAssigning
              ? null
              : (details) {
                  if (!_isDraggingRadius || _assignScreenCenter == null) return;
                  final dist =
                      (details.localPosition - _assignScreenCenter!).distance;
                  _dragLogCounter++;
                  final now = DateTime.now();
                  final deltaMs = _lastOverlayMoveAt == null
                      ? 0
                      : now.difference(_lastOverlayMoveAt!).inMilliseconds;
                  _lastOverlayMoveAt = now;
                  if (_assignTriggerType == TriggerType.distance) {
                    final mpp = _vectorMetersPerPx(_assignLat, _currentZoom);
                    final nextRadius = (dist * mpp)
                        .clamp(100.0, 5000.0)
                        .toDouble();
                    _assignRadius = nextRadius;
                  } else {
                    _assignTimeMinutes = (dist * 0.3).clamp(5.0, 120.0).round();
                  }
                  final radiusPx = this._currentRadiusPx;
                  _radiusNotifier.value = radiusPx;
                  this._logExitRadiusInputTrace(
                    source: 'longpress',
                    frame: _dragLogCounter,
                    distPx: dist,
                    radiusPx: radiusPx,
                  );
                  if (_useNativeAssignCircle && !_assignFlutterPreviewActive) {
                    this._syncAssignRadiusPaintImmediate(
                      debugReason: 'longpress#$_dragLogCounter',
                    );
                    this._scheduleAssignOverlaySync(
                      radiusOnly: true,
                      debugReason: 'longpress#$_dragLogCounter',
                    );
                  }
                  if (_dragLogCounter == 1 || _dragLogCounter % 10 == 0) {
                    this._refreshAssignMarker();
                  }
                  if (_shouldLogAssignFrame(_dragLogCounter)) {
                    DebugConsole.log(
                      'LONGPRESS_MOVE: frame=$_dragLogCounter dist=${dist.round()} '
                      'r=${_assignRadius.round()}m px=${radiusPx.toStringAsFixed(1)} '
                      '${_assignDebugState()}',
                    );
                  }
                  this._scheduleAssignCardSync();
                },
          onLongPressEnd: !_isAssigning
              ? null
              : (details) {
                  DebugConsole.log(
                    'LONGPRESS_END: frames=$_dragLogCounter ${_assignDebugState()}',
                  );
                  _isDraggingRadius = false;
                  _radiusDragStartDistancePx = null;
                  _radiusDragStartRadiusM = null;
                  this._refreshAssignMarker();
                  unawaited(
                    this._flushAssignOverlaySync(
                      debugReason: 'longpress-end',
                      finishPreview: true,
                    ),
                  );
                  this._flushAssignCardSync();
                },
          child: MapLibreMap(
            key: ValueKey(styleUrl),
            options: MapOptions(
              initStyle: styleUrl,
              initCenter: Position(
                context.read<MapProvider>().center.longitude,
                context.read<MapProvider>().center.latitude,
              ),
              initZoom: context.read<MapProvider>().zoom,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoaded: (style) {
              unawaited(_registerImages(style, styleUrl));
              // Style JSON may override initZoom/initCenter with its defaults.
              // Restore MapProvider values after style loads.
              final mp = context.read<MapProvider>();
              DebugConsole.log(
                'STYLE_LOADED: restoring zoom=${mp.zoom.toStringAsFixed(2)} center=${mp.center}',
              );
              _safeMoveCamera(
                center: Position(mp.center.longitude, mp.center.latitude),
                zoom: mp.zoom,
              );
            },
            onEvent: _onMapEvent,
            layers: const [],
          ),
        ), // close GestureDetector
        // Capture pointer position before map processes it
        if (!_isAssigning)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) {
                _lastPointerDownPos = e.localPosition;
                DebugConsole.log(
                  'CAPTURE_POINTER: pos=${e.localPosition} pointer=${e.pointer}',
                );
              },
              child: const SizedBox.expand(),
            ),
          ),
        const OfflineIndicator(),
        // Scale bar — bottom left
        Positioned(
          bottom: 24,
          left: 12,
          child: ScaleBar(
            zoom: _currentZoom + 1, // MapLibre vector: 512px tile scale
            latitude: _userPos?.lat.toDouble() ?? 47.5,
            speedKmh: _speedKmh,
          ),
        ),
        // Debug button - top right
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 12,
          child: GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => const DebugConsoleDialog(),
            ),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.terminal,
                color: Color(0xFF2ECDC4),
                size: 18,
              ),
            ),
          ),
        ),
        // Hamburger menu + map switch — always visible
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 12,
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  if (_isAssigning) this._cancelAssign();
                  widget.scaffoldKey.currentState?.openDrawer();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[900]!.withOpacity(0.92)
                        : Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.menu,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.grey[800],
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Other controls — hidden during assign
        if (!_isAssigning)
          Selector<MapProvider, bool>(
            selector: (_, p) => p.searchActive,
            builder: (_, searchActive, __) => MapControls(
              onMenuTap: () => widget.scaffoldKey.currentState?.openDrawer(),
              onZoomIn: () => _safeMoveCamera(zoom: _currentZoom + 1),
              onZoomOut: () => _safeMoveCamera(zoom: _currentZoom - 1),
              onSearchTap: () => context.read<MapProvider>().toggleSearch(),
              searchActive: searchActive,
              myLocationIcon: Icons.my_location,
              onMyLocation: () => unawaited(_jumpToUserPosition()),
              onMapToggleTap: () async {
                final haptic = context
                    .read<SettingsProvider>()
                    .settings
                    .hapticFeedback;
                if (haptic) Vibration.vibrate(duration: 30);
                if (_isAssigning) this._cancelAssign();
                final settings = context.read<SettingsProvider>();
                await settings.updateSettings(
                  settings.settings.copyWith(mapProvider: MapTileProvider.free),
                );
              },
              onSkinTap: () async {
                final haptic = context
                    .read<SettingsProvider>()
                    .settings
                    .hapticFeedback;
                if (haptic) Vibration.vibrate(duration: 30);
                if (_isAssigning) this._cancelAssign();
                final settings = context.read<SettingsProvider>();
                final keys = _styleUrls.keys.toList();
                final currentKey = settings.settings.vectorStyleUrl;
                final idx = keys.indexOf(currentKey);
                final nextKey = keys[(idx + 1) % keys.length];
                await settings.updateSettings(
                  settings.settings.copyWith(vectorStyleUrl: nextKey),
                );
              },
              on3DTap: () => setState(
                () => _set3DMode(enabled: !_is3D, compassFollow: true),
              ),
              icon3D: _is3D ? Icons.view_in_ar : Icons.threed_rotation,
              icon3DColor: _is3D ? Colors.white : null,
              bg3DColor: _is3D ? Theme.of(context).colorScheme.primary : null,
              // Freeze button - shown when 3D is active
              showFreeze: _is3D,
              onFreezeTap: () {
                final haptic = context
                    .read<SettingsProvider>()
                    .settings
                    .hapticFeedback;
                if (haptic) Vibration.vibrate(duration: 30);
                setState(_toggle3DFixedMode);
              },
              iconFreeze: _gpsFollow ? Icons.lock_open : Icons.lock,
              iconFreezeColor: !_gpsFollow ? Colors.white : null,
              bgFreezeColor: !_gpsFollow
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
        if (!_isAssigning)
          Selector<MapProvider, bool>(
            selector: (_, p) => p.searchActive,
            builder: (_, searchActive, __) => searchActive
                ? SearchPill(
                    onResultSelected: (result) {
                      context.read<MapProvider>().goToSearchResult(result);
                      _safeMoveCamera(
                        center: Position(result.longitude, result.latitude),
                        zoom: 14,
                      );
                    },
                    onClose: () => context.read<MapProvider>().toggleSearch(),
                  )
                : const SizedBox.shrink(),
          ),
        // Radius drag overlay — blocks map gestures, 60fps via ValueNotifier
        if ((_isAssigning ||
                _closingAssignCircle ||
                _assignFlutterPreviewActive) &&
            _assignScreenCenter != null)
          Positioned.fill(
            child: RepaintBoundary(
              child: Listener(
                behavior: _isAssigning
                    ? HitTestBehavior.opaque
                    : HitTestBehavior.translucent,
                onPointerDown: (e) {
                  if (!_isAssigning) return;
                  if (_assignScreenCenter == null) {
                    DebugConsole.log('OVERLAY_DOWN: screenCenter is null!');
                    return;
                  }
                  final dist =
                      (e.localPosition - _assignScreenCenter!).distance;
                  final radiusPx = _radiusNotifier.value;
                  DebugConsole.log(
                    'OVERLAY_DOWN: pos=${e.localPosition} center=$_assignScreenCenter '
                    'dist=${dist.round()} radiusPx=${radiusPx.round()} '
                    'inside=${dist <= radiusPx * 1.5} ${_assignDebugState()}',
                  );
                  if (dist <= radiusPx * 1.5) {
                    _dragPointerId = e.pointer;
                    _isDraggingRadius = true;
                    _dragLogCounter = 0;
                    if (_assignTriggerType == TriggerType.distance) {
                      _radiusDragStartDistancePx = dist;
                      _radiusDragStartRadiusM = _assignRadius;
                    } else {
                      _radiusDragStartDistancePx = null;
                      _radiusDragStartRadiusM = null;
                    }
                    _lastOverlayMoveAt = DateTime.now();
                  }
                },
                onPointerMove: (e) {
                  if (!_isAssigning) return;
                  if (!_isDraggingRadius || _assignScreenCenter == null) return;
                  if (e.pointer != _dragPointerId) return;
                  final dist =
                      (e.localPosition - _assignScreenCenter!).distance;
                  _dragLogCounter++;
                  final now = DateTime.now();
                  final deltaMs = _lastOverlayMoveAt == null
                      ? 0
                      : now.difference(_lastOverlayMoveAt!).inMilliseconds;
                  _lastOverlayMoveAt = now;
                  if (_assignTriggerType == TriggerType.distance) {
                    final mpp = _vectorMetersPerPx(_assignLat, _currentZoom);
                    final dragStartDistancePx = _radiusDragStartDistancePx;
                    final dragStartRadiusM = _radiusDragStartRadiusM;
                    final nextRadius =
                        (dragStartDistancePx != null && dragStartRadiusM != null
                                ? dragStartRadiusM +
                                      (dist - dragStartDistancePx) * mpp
                                : dist * mpp)
                            .clamp(100.0, 5000.0)
                            .toDouble();
                    _assignRadius = nextRadius;
                  } else {
                    _assignTimeMinutes = (dist * 0.3).clamp(5.0, 120.0).round();
                  }
                  // Update overlay circle instantly (no widget rebuild)
                  final radiusPx = this._currentRadiusPx;
                  _radiusNotifier.value = radiusPx;
                  this._logExitRadiusInputTrace(
                    source: 'overlay',
                    frame: _dragLogCounter,
                    distPx: dist,
                    radiusPx: radiusPx,
                    pointer: e.pointer,
                    eventDtMs: deltaMs,
                  );
                  if (!_assignFlutterPreviewActive) {
                    this._syncAssignRadiusPaintImmediate(
                      debugReason: 'overlay#$_dragLogCounter',
                    );
                    this._scheduleAssignOverlaySync(
                      radiusOnly: true,
                      debugReason: 'overlay#$_dragLogCounter',
                    );
                  }
                  if (_dragLogCounter == 1 || _dragLogCounter % 10 == 0) {
                    this._refreshAssignMarker();
                  }
                  if (_shouldLogAssignFrame(_dragLogCounter)) {
                    DebugConsole.log(
                      'OVERLAY_MOVE: frame=$_dragLogCounter dt=${deltaMs}ms '
                      'dist=${dist.round()} r=${_assignRadius.round()}m '
                      'px=${radiusPx.toStringAsFixed(1)} ${_assignDebugState()}',
                    );
                  }
                  // Sync AlarmCard periodically; the visual radius is already native.
                  this._scheduleAssignCardSync();
                },
                onPointerUp: (e) {
                  if (!_isAssigning) return;
                  DebugConsole.log(
                    'OVERLAY_UP: pointer=${e.pointer} dragPointer=$_dragPointerId '
                    'isDragging=$_isDraggingRadius frames=$_dragLogCounter '
                    '${_assignDebugState()}',
                  );
                  if (e.pointer != _dragPointerId) return;
                  _isDraggingRadius = false;
                  _dragPointerId = null;
                  _radiusDragStartDistancePx = null;
                  _radiusDragStartRadiusM = null;
                  this._refreshAssignMarker();
                  unawaited(
                    this._flushAssignOverlaySync(
                      debugReason: 'overlay-up',
                      finishPreview: true,
                    ),
                  );
                  this._flushAssignCardSync();
                },
                child: CustomPaint(
                  painter:
                      _assignScreenCenter != null &&
                          (_assignFlutterPreviewActive ||
                              !_useNativeAssignCircle) &&
                          (_assignFlutterPreviewActive ||
                              this._showAssignOverlay ||
                              _closingAssignCircle)
                      ? _RadiusOverlayPainter(
                          center: _assignScreenCenter!,
                          radiusNotifier: _radiusNotifier,
                          isTime: _assignTriggerType == TriggerType.time,
                          isLeave: _assignZoneTrigger == ZoneTrigger.onLeave,
                          active: _assignActive,
                        )
                      : null,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        if (((_isAssigning && this._showAssignMarkerOverlay) ||
                _closingAssignMarker) &&
            _assignScreenCenter != null &&
            _assignMarkerPng != null)
          Positioned(
            left: _assignScreenCenter!.dx - _assignMarkerSize.width / 2,
            top: _assignScreenCenter!.dy - AlarmMarkerSpec.pinSize,
            child: IgnorePointer(
              child: Image.memory(
                _assignMarkerPng!,
                scale: _deviceDpr,
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        // Alarm card — unified assign/edit (same widget as raster map)
        if (_isAssigning)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AlarmCard(
              latitude: _assignLat,
              longitude: _assignLng,
              existingPoint: _assignExisting,
              radius: _assignRadius,
              onRadiusChanged: (v) {
                _assignRadius = v;
                _radiusNotifier.value = this._currentRadiusPx;
                _cardRadiusLogCounter++;
                this._logExitRadiusInputTrace(
                  source: 'card-radius',
                  frame: _cardRadiusLogCounter,
                  distPx: this._currentRadiusPx,
                  radiusPx: this._currentRadiusPx,
                );
                if (_shouldLogAssignFrame(_cardRadiusLogCounter)) {
                  DebugConsole.log(
                    'CARD_RADIUS: frame=$_cardRadiusLogCounter '
                    'r=${_assignRadius.round()}m ${_assignDebugState()}',
                  );
                }
                if (!_assignFlutterPreviewActive) {
                  this._syncAssignRadiusPaintImmediate(
                    debugReason: 'card-radius#$_cardRadiusLogCounter',
                  );
                  this._scheduleAssignOverlaySync(
                    radiusOnly: true,
                    debugReason: 'card-radius#$_cardRadiusLogCounter',
                  );
                }
                if (_cardRadiusLogCounter == 1 ||
                    _cardRadiusLogCounter % 10 == 0) {
                  this._refreshAssignMarker();
                }
              },
              onZoneTriggerChanged: (v) {
                setState(() => _assignZoneTrigger = v);
                DebugConsole.log('CARD_ZONE: ${v.name} ${_assignDebugState()}');
                unawaited(
                  this._flushAssignOverlaySync(debugReason: 'card-zone'),
                );
                this._refreshNativePreviewHiddenState('card-zone');
              },
              onTriggerTypeChanged: (v) {
                setState(() => _assignTriggerType = v);
                DebugConsole.log(
                  'CARD_TRIGGER: ${v.name} ${_assignDebugState()}',
                );
                unawaited(
                  this._flushAssignOverlaySync(
                    updateMarker: true,
                    debugReason: 'card-trigger',
                  ),
                );
                this._refreshNativePreviewHiddenState('card-trigger');
                this._refreshAssignMarker();
              },
              onTimeChanged: (v) {
                _assignTimeMinutes = v;
                _radiusNotifier.value = this._currentRadiusPx;
                _cardTimeLogCounter++;
                if (_shouldLogAssignFrame(_cardTimeLogCounter)) {
                  DebugConsole.log(
                    'CARD_TIME: frame=$_cardTimeLogCounter '
                    '${_assignTimeMinutes}min ${_assignDebugState()}',
                  );
                }
                if (!_assignFlutterPreviewActive) {
                  this._syncAssignRadiusPaintImmediate(
                    debugReason: 'card-time#$_cardTimeLogCounter',
                  );
                  this._scheduleAssignOverlaySync(
                    radiusOnly: true,
                    debugReason: 'card-time#$_cardTimeLogCounter',
                  );
                }
                if (_cardTimeLogCounter == 1 || _cardTimeLogCounter % 10 == 0) {
                  this._refreshAssignMarker();
                }
              },
              onActiveChanged: (v) {
                setState(() => _assignActive = v);
                DebugConsole.log(
                  'CARD_ACTIVE: $_assignActive ${_assignDebugState()}',
                );
                unawaited(
                  this._flushAssignOverlaySync(
                    updateMarker: true,
                    debugReason: 'card-active',
                  ),
                );
                this._refreshNativePreviewHiddenState('card-active');
                this._refreshAssignMarker();
              },
              onSave: (alarm) => this._saveAssign(alarm),
              onCancel: () => this._cancelAssign(),
              onDelete: _assignExisting != null
                  ? () async {
                      await context.read<AlarmProvider>().removeAlarmPoint(
                        _assignExisting!.id,
                      );
                      if (!mounted) return;
                      this._cancelAssign();
                    }
                  : null,
            ),
          ),
      ],
    );
  }
}
