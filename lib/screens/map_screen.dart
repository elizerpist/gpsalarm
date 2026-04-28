import 'dart:async';
import 'dart:math';
import 'package:vibration/vibration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import '../models/alarm_point.dart';
import '../models/app_settings.dart';
import '../providers/map_provider.dart';
import '../providers/alarm_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/map_controls.dart';
import '../widgets/search_pill.dart';
import '../widgets/pin_marker.dart';
import '../widgets/radius_circle.dart';
import '../widgets/radius_popup.dart';
import '../widgets/alarm_card.dart';
import '../widgets/user_location_marker.dart';
import '../services/location_service.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import 'settings_screen.dart';
import '../services/debug_console.dart';
import '../widgets/maplibre_new_view.dart';
import '../widgets/offline_indicator.dart';
import '../widgets/scale_bar.dart';
import '../services/cached_tile_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final CachedTileProvider _cachedTileProvider = CachedTileProvider();
  final ValueNotifier<LatLng?> _userPosition = ValueNotifier(null);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Unified assign state (replaces both fast assign + pending tap)
  bool _isAssigning = false;
  LatLng? _assignCenter;
  AlarmPoint? _assignExisting; // non-null = editing existing alarm
  double _assignRadius = 500;
  ZoneTrigger _assignZoneTrigger = ZoneTrigger.onEntry;
  TriggerType _assignTriggerType = TriggerType.distance;
  int _assignTimeMinutes = 10;
  // Long press detection
  Timer? _longPressTimer;
  Offset? _pointerDownPos;
  bool _longPressTriggered = false;

  double _rasterZoom = 13;
  final ValueNotifier<double> _speedKmh = ValueNotifier(0);

  // Speed interpolation between GPS ticks
  double _prevGpsSpeed = 0;
  double _currentGpsSpeed = 0;
  DateTime _prevGpsTime = DateTime.now();
  DateTime _currentGpsTime = DateTime.now();
  Timer? _speedInterpolTimer;

  // Frame timing
  int _frameCount = 0;
  int _slowFrames = 0;
  DateTime _lastFrameReport = DateTime.now();

  @override
  void initState() {
    super.initState();
    DebugConsole.log('initState()');
    _initLocation();
    _startFrameMonitor();
  }

  void _startFrameMonitor() {
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        _frameCount++;
        final totalMs = t.totalSpan.inMilliseconds;
        if (totalMs > 16) _slowFrames++;
        if (totalMs > 50) {
          DebugConsole.log('SLOW FRAME: build=${t.buildDuration.inMilliseconds}ms raster=${t.rasterDuration.inMilliseconds}ms total=${totalMs}ms');
        }
      }
      final now = DateTime.now();
      if (now.difference(_lastFrameReport).inSeconds >= 5) {
        final secs = now.difference(_lastFrameReport).inMilliseconds / 1000;
        final fps = _frameCount / secs;
        DebugConsole.log('FPS: ${fps.toStringAsFixed(1)} | total=$_frameCount slow=$_slowFrames');
        _frameCount = 0;
        _slowFrames = 0;
        _lastFrameReport = now;
      }
    });
  }

  /// Interpolate speed between GPS ticks for smooth time-trigger circle updates.
  /// Only runs in continuous GPS mode. Custom interval = no interpolation, no timer.
  void _startSpeedInterpolation() {
    _speedInterpolTimer?.cancel();
    _speedInterpolTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      final gpsInterval = _currentGpsTime.difference(_prevGpsTime).inMilliseconds;
      double estimated;
      if (gpsInterval <= 0) {
        estimated = _currentGpsSpeed;
      } else {
        final accelPerMs = (_currentGpsSpeed - _prevGpsSpeed) / gpsInterval;
        final elapsed = DateTime.now().difference(_currentGpsTime).inMilliseconds;
        estimated = (_currentGpsSpeed + accelPerMs * elapsed).clamp(0.0, 300.0);
        if (elapsed > gpsInterval * 2) estimated = _currentGpsSpeed;
      }
      if ((estimated - _speedKmh.value).abs() > 0.05) {
        _speedKmh.value = estimated;
      }
    });
  }

  Future<void> _initLocation() async {
    DebugConsole.log('Requesting location permission...');
    final hasPermission = await _locationService.requestPermission();
    DebugConsole.log('Permission: $hasPermission');
    if (hasPermission) {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null && mounted) {
        _userPosition.value = LatLng(pos.latitude, pos.longitude);
        _mapController.move(_userPosition.value!, _mapController.camera.zoom);
      }
      final settings = context.read<SettingsProvider>().settings;
      final isContinuous = settings.gpsPollingMode == GpsPollingMode.continuous;
      final interval = isContinuous
          ? const Duration(seconds: 3)
          : settings.customPollingInterval;
      DebugConsole.log('Starting GPS tracking (${isContinuous ? "continuous/3s" : "custom/${interval.inSeconds}s"})');
      // Speed interpolation only in continuous mode (saves battery in custom mode)
      if (isContinuous) {
        _startSpeedInterpolation();
      } else {
        _speedInterpolTimer?.cancel();
      }
      _locationService.startTracking(
        interval: interval,
        onPosition: (position) {
          if (!mounted) return;
          final newPos = LatLng(position.latitude, position.longitude);
          if (_userPosition.value == null ||
              AlarmService.distanceMeters(
                      _userPosition.value!.latitude, _userPosition.value!.longitude,
                      newPos.latitude, newPos.longitude) > 5) {
            _userPosition.value = newPos;
            DebugConsole.log('GPS: ${newPos.latitude.toStringAsFixed(4)}, ${newPos.longitude.toStringAsFixed(4)}');
          }
          _checkAlarms(position.latitude, position.longitude);
          final newSpeed = _locationService.averageSpeedKmh;
          if (isContinuous) {
            // Feed speed interpolation (timer handles setState)
            _prevGpsSpeed = _currentGpsSpeed;
            _prevGpsTime = _currentGpsTime;
            _currentGpsSpeed = newSpeed;
            _currentGpsTime = DateTime.now();
          } else {
            // Custom interval: direct speed update, no interpolation
            if ((newSpeed - _speedKmh.value).abs() > 0.1) {
              _speedKmh.value = newSpeed;
            }
          }
        },
      );
    }
  }

  void _checkAlarms(double userLat, double userLng) {
    final alarmProv = context.read<AlarmProvider>();
    final activePoints =
        alarmProv.alarmPoints.where((p) => p.isActive).toList();

    for (final point in activePoints) {
      bool shouldTrigger = false;
      final isInside = AlarmService.isWithinRadius(
        userLat: userLat,
        userLng: userLng,
        pointLat: point.latitude,
        pointLng: point.longitude,
        radiusMeters: point.radiusMeters,
      );

      if (point.triggerType == TriggerType.distance) {
        // On entry: trigger when entering the zone
        // On leave: trigger when outside the zone (was inside before)
        if (point.zoneTrigger == ZoneTrigger.onEntry) {
          shouldTrigger = isInside;
        } else {
          shouldTrigger = !isInside;
        }
      } else if (point.triggerType == TriggerType.time &&
          point.timeTrigger != null) {
        // Time-based: trigger when user is inside the dynamic radius circle.
        // The circle radius = max(200m, speed * time).
        final speedMs = _locationService.averageSpeedKmh / 3.6;
        final timeRadius = max(200.0, speedMs * point.timeTrigger!.inSeconds.toDouble());
        final dist = AlarmService.distanceMeters(
            userLat, userLng, point.latitude, point.longitude);
        final insideTimeCircle = dist <= timeRadius;
        if (point.zoneTrigger == ZoneTrigger.onEntry) {
          shouldTrigger = insideTimeCircle;
        } else {
          shouldTrigger = !insideTimeCircle;
        }
      }

      if (shouldTrigger) {
        DebugConsole.log('ALARM TRIGGERED: ${point.name ?? point.id}');
        alarmProv.toggleActive(point.id);
        _showAlarmTriggered(point);
      }
    }
  }

  void _showAlarmTriggered(AlarmPoint point) {
    if (!mounted) return;
    final title = point.name ?? tr('no_name');
    final zoneText = point.zoneTrigger == ZoneTrigger.onEntry ? 'Belépés' : 'Kilépés';
    final body = point.triggerType == TriggerType.distance
        ? '$zoneText — ${point.radiusMeters.round()}m'
        : '$zoneText — ${point.timeTrigger?.inMinutes ?? 0} min';

    // Send system notification
    NotificationService.showAlarmNotification(
      title: 'GPS Alarm: $title',
      body: body,
      id: point.id.hashCode,
    );

    // Show in-app dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.alarm, color: Colors.red, size: 48),
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('dismiss')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _speedInterpolTimer?.cancel();
    _locationService.dispose();
    _userPosition.dispose();
    _speedKmh.dispose();
    _cancelLongPressTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.select<SettingsProvider, MapTileProvider>(
        (p) => p.settings.mapProvider);

    // Vector (maplibre) — native only
    if (mapProvider == MapTileProvider.vector && !kIsWeb) {
      return Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        body: MaplibreNewView(scaffoldKey: _scaffoldKey),
        drawer: const SettingsDrawer(),
      );
    }

    final tileUrl = context.select<SettingsProvider, String>(
        (p) => _getTileUrl(p.settings));
    DebugConsole.log('build() tile=$tileUrl');

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Long press gesture layer on top of map
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: (_) {
              _activePointers = (_activePointers - 1).clamp(0, 99);
              _cancelLongPressTimer();
            },
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: context.read<MapProvider>().center,
                initialZoom: context.read<MapProvider>().zoom,
                interactionOptions: InteractionOptions(
                  flags: _isDraggingRadius
                      ? InteractiveFlag.none
                      : InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: _isAssigning
                    ? null
                    : (tapPosition, point) => _handleTap(context, point),
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture) {
                    _cancelLongPressTimer();
                  }
                  final z = position.zoom;
                  if (z != null && (z - _rasterZoom).abs() > 0.05) {
                    setState(() => _rasterZoom = z);
                  }
                },
              ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                userAgentPackageName: 'com.gpsalarm.app',
                tileProvider: kIsWeb ? null : _cachedTileProvider,
                fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                errorTileCallback: (tile, error, stackTrace) {
                  DebugConsole.log('Tile error z=${tile.coordinates.z} x=${tile.coordinates.x} y=${tile.coordinates.y}: $error');
                },
              ),
              // Radius circles — distance-based (solid)
              Consumer<AlarmProvider>(
                builder: (_, alarmProv, __) => ValueListenableBuilder<double>(
                  valueListenable: _speedKmh,
                  builder: (_, speed, __) => CircleLayer(
                    circles: [
                      ...alarmProv.alarmPoints
                          .where((p) => p.zoneTrigger != ZoneTrigger.onLeave && p.triggerType == TriggerType.distance
                              && p.id != _assignExisting?.id)
                          .map((p) => buildRadiusCircle(p, speedKmh: speed)),
                      if (_isAssigning && _assignCenter != null
                          && _assignZoneTrigger != ZoneTrigger.onLeave
                          && _assignTriggerType == TriggerType.distance)
                        CircleMarker(
                          point: _assignCenter!,
                          radius: _assignRadius,
                          useRadiusInMeter: true,
                          color: Colors.red.withOpacity(0.15),
                          borderColor: Colors.red.withOpacity(0.7),
                          borderStrokeWidth: 3,
                        ),
                    ],
                  ),
                ),
              ),
              // Radius circles — time-based (orange dashed)
              Consumer<AlarmProvider>(
                builder: (_, alarmProv, __) => ValueListenableBuilder<double>(
                  valueListenable: _speedKmh,
                  builder: (_, speed, __) {
                    final timePolygons = <Polygon>[
                      ...alarmProv.alarmPoints
                          .where((p) => p.zoneTrigger != ZoneTrigger.onLeave && p.triggerType == TriggerType.time
                              && p.id != _assignExisting?.id)
                          .map((p) => buildTimeTriggerCircle(
                            LatLng(p.latitude, p.longitude),
                            effectiveRadius(p, speed),
                            isActive: p.isActive,
                          )),
                      if (_isAssigning && _assignCenter != null
                          && _assignZoneTrigger != ZoneTrigger.onLeave
                          && _assignTriggerType == TriggerType.time)
                        buildTimeTriggerCircle(
                          _assignCenter!,
                          max(200.0, (speed / 3.6) * _assignTimeMinutes * 60),
                        ),
                    ];
                    return timePolygons.isEmpty
                        ? const SizedBox.shrink()
                        : PolygonLayer(polygons: timePolygons);
                  },
                ),
              ),
              // Inverted radius — single veil with holes for ALL onLeave circles
              Consumer<AlarmProvider>(
                builder: (_, alarmProv, __) {
                  final leaveAlarms = alarmProv.alarmPoints
                      .where((p) => p.zoneTrigger == ZoneTrigger.onLeave
                          && p.id != _assignExisting?.id)
                      .toList();
                  final hasAssignLeave = _isAssigning && _assignCenter != null && _assignZoneTrigger == ZoneTrigger.onLeave;
                  if (leaveAlarms.isEmpty && !hasAssignLeave) return const SizedBox.shrink();

                  final holes = <List<LatLng>>[
                    for (final p in leaveAlarms)
                      buildCirclePoints(LatLng(p.latitude, p.longitude), p.radiusMeters),
                    if (hasAssignLeave)
                      buildCirclePoints(_assignCenter!, _assignRadius),
                  ];

                  return PolygonLayer(polygons: [
                    Polygon(
                      points: const [LatLng(-85, -180), LatLng(-85, 180), LatLng(85, 180), LatLng(85, -180)],
                      holePointsList: holes,
                      color: Colors.red.withOpacity(0.15),
                      borderColor: Colors.red.withOpacity(0.6),
                      borderStrokeWidth: 2,
                      isFilled: true,
                    ),
                  ]);
                },
              ),
              // Pin markers
              Consumer<AlarmProvider>(
                builder: (_, alarmProv, __) =>
                    ValueListenableBuilder<LatLng?>(
                  valueListenable: _userPosition,
                  builder: (_, userPos, __) => MarkerLayer(
                    markers: [
                      ...alarmProv.alarmPoints
                          .where((p) => p.id != _assignExisting?.id)
                          .map((p) => buildPinMarker(
                            point: p,
                            onTap: () => _startAssign(p.latitude, p.longitude, existing: p),
                          )),
                      if (userPos != null)
                        buildUserLocationMarker(userPos),
                      // Assign pin — orange for time, red for distance, with live chip
                      if (_isAssigning && _assignCenter != null)
                        Marker(
                          point: _assignCenter!,
                          width: 80,
                          height: 60,
                          alignment: const Alignment(0, 0.067),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on,
                                  color: _assignTriggerType == TriggerType.time
                                      ? Colors.orange : Colors.red,
                                  size: 32),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: (_assignTriggerType == TriggerType.time
                                      ? Colors.orange : Colors.red).withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _assignTriggerType == TriggerType.distance
                                      ? (_assignRadius >= 1000
                                          ? '${(_assignRadius / 1000).toStringAsFixed(1)}km'
                                          : '${_assignRadius.round()}m')
                                      : '${_assignTimeMinutes}min',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          ), // close Listener
          // (swipe handled by Listener above)
          // Offline indicator
          const OfflineIndicator(),
          // Scale bar — bottom left
          Positioned(
            bottom: 24,
            left: 12,
            child: ScaleBar(
              zoom: _rasterZoom,
              latitude: _userPosition.value?.latitude ?? 47.5,
              speedKmh: _speedKmh.value,
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
                child: const Icon(Icons.terminal, color: Color(0xFF2ECDC4), size: 18),
              ),
            ),
          ),
          // Hamburger menu — always visible, cancels assign if active
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            child: GestureDetector(
              onTap: () {
                if (_isAssigning) _cancelAssign();
                _scaffoldKey.currentState?.openDrawer();
              },
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[900]!.withOpacity(0.92)
                      : Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Icon(Icons.menu, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.grey[800], size: 24),
              ),
            ),
          ),
          // Other controls — hidden during assign
          if (!_isAssigning)
            Selector<MapProvider, bool>(
              selector: (_, p) => p.searchActive,
              builder: (_, searchActive, __) => MapControls(
                onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                onZoomIn: () {
                  final cam = _mapController.camera;
                  _mapController.move(cam.center, (cam.zoom + 1).clamp(3, 18));
                },
                onZoomOut: () {
                  final cam = _mapController.camera;
                  _mapController.move(cam.center, (cam.zoom - 1).clamp(3, 18));
                },
                onSearchTap: () =>
                    context.read<MapProvider>().toggleSearch(),
                onMyLocation: _goToMyLocation,
                searchActive: searchActive,
              ),
            ),
          // Search pill - only when active
          if (!_isAssigning)
            Selector<MapProvider, bool>(
              selector: (_, p) => p.searchActive,
              builder: (_, searchActive, __) => searchActive
                  ? SearchPill(
                      onResultSelected: (result) {
                        context.read<MapProvider>().goToSearchResult(result);
                        _mapController.move(
                          LatLng(result.latitude, result.longitude),
                          14.0,
                        );
                      },
                      onClose: () => context.read<MapProvider>().toggleSearch(),
                    )
                  : const SizedBox.shrink(),
            ),
          // Alarm card — unified assign/edit
          if (_isAssigning && _assignCenter != null)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: AlarmCard(
                latitude: _assignCenter!.latitude,
                longitude: _assignCenter!.longitude,
                existingPoint: _assignExisting,
                radius: _assignRadius,
                onRadiusChanged: (v) => setState(() => _assignRadius = v),
                onZoneTriggerChanged: (v) => setState(() => _assignZoneTrigger = v),
                onTriggerTypeChanged: (v) => setState(() => _assignTriggerType = v),
                onTimeChanged: (v) => setState(() => _assignTimeMinutes = v),
                onSave: _saveAssign,
                onCancel: _cancelAssign,
                onDelete: _assignExisting != null ? () {
                  context.read<AlarmProvider>().removeAlarmPoint(_assignExisting!.id);
                  _cancelAssign();
                } : null,
              ),
            ),
        ],
      ),
      drawer: const SettingsDrawer(),
    );
  }

  int _activePointers = 0;
  bool _isDraggingRadius = false;
  Offset? _longPressScreenOffset;

  Offset? _getAssignCenterScreen() {
    if (_assignCenter == null) return null;
    final screenPt = _mapController.camera.latLngToScreenPoint(_assignCenter!);
    return Offset(screenPt.x.toDouble(), screenPt.y.toDouble());
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers > 1) {
      _cancelLongPressTimer();
      return;
    }

    // Assign mode: check if touch is inside the radius circle for swipe
    if (_isAssigning && _assignCenter != null) {
      final center = _getAssignCenterScreen();
      if (center != null) {
        final dist = (event.localPosition - center).distance;
        final currentRadius = _assignTriggerType == TriggerType.time
            ? max(200.0, (_speedKmh.value / 3.6) * _assignTimeMinutes * 60)
            : _assignRadius;
        final radiusPx = currentRadius / _pixelsToMeters(1);
        if (dist <= radiusPx * 1.5) {
          _isDraggingRadius = true;
          return;
        }
      }
      return;
    }

    // Normal mode: long press detection
    _pointerDownPos = event.position;
    _longPressTriggered = false;
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (_pointerDownPos == null) return;
      _longPressTriggered = true;
      final screenPoint = Point<double>(event.localPosition.dx, event.localPosition.dy);
      final latLng = _mapController.camera.pointToLatLng(screenPoint);
      final haptic = context.read<SettingsProvider>().settings.hapticFeedback;
      if (haptic) Vibration.vibrate(duration: 30);
      _longPressScreenOffset = event.position;
      _startAssign(latLng.latitude, latLng.longitude);
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    // Radius drag mode (circle swipe)
    if (_isDraggingRadius && _assignCenter != null) {
      final center = _getAssignCenterScreen();
      if (center != null) {
        final dist = (event.localPosition - center).distance;
        if (_assignTriggerType == TriggerType.distance) {
          final meters = _pixelsToMeters(dist).clamp(100.0, 5000.0);
          setState(() => _assignRadius = meters);
        } else {
          final minutes = (dist * 0.3).clamp(5.0, 120.0).round();
          setState(() => _assignTimeMinutes = minutes);
        }
      }
      return;
    }

    // Long press not yet triggered — check if moved too far
    if (!_longPressTriggered && _pointerDownPos != null) {
      final dist = (event.position - _pointerDownPos!).distance;
      if (dist > 20) _cancelLongPressTimer();
      return;
    }

    // Initial long press swipe — update radius immediately
    if (_isAssigning && _longPressScreenOffset != null) {
      final dx = event.position.dx - _longPressScreenOffset!.dx;
      final dy = event.position.dy - _longPressScreenOffset!.dy;
      final pixelDist = sqrt(dx * dx + dy * dy);
      final meters = _pixelsToMeters(pixelDist).clamp(100.0, 5000.0);
      setState(() => _assignRadius = meters);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 99);
    _cancelLongPressTimer();
    if (_isDraggingRadius) {
      _isDraggingRadius = false;
      return;
    }
    if (_longPressTriggered) {
      _longPressScreenOffset = null;
    }
    _longPressTriggered = false;
    _pointerDownPos = null;
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  double _pixelsToMeters(double pixels) {
    final zoom = _mapController.camera.zoom;
    final metersPerPixel = 156543.03392 * cos(_mapController.camera.center.latitude * pi / 180) / pow(2, zoom);
    return pixels * metersPerPixel;
  }

  void _goToMyLocation() {
    final pos = _userPosition.value;
    if (pos != null) {
      _mapController.move(pos, 15);
    }
  }

  void _handleTap(BuildContext context, LatLng point) {
    if (_isAssigning) return;
    final alarmProv = context.read<AlarmProvider>();
    final existing = alarmProv.findNearby(point.latitude, point.longitude);
    _startAssign(point.latitude, point.longitude, existing: existing);
  }

  /// Unified assign start — used by both tap and long press.
  void _startAssign(double lat, double lng, {AlarmPoint? existing}) {
    setState(() {
      _isAssigning = true;
      _assignCenter = LatLng(lat, lng);
      _assignExisting = existing;
      _assignRadius = existing?.radiusMeters ?? 500;
      _assignTriggerType = existing?.triggerType ?? TriggerType.distance;
      _assignZoneTrigger = existing?.zoneTrigger ?? ZoneTrigger.onEntry;
      _assignTimeMinutes = existing?.timeTrigger?.inMinutes ?? 10;
    });
  }

  void _saveAssign(AlarmPoint alarm) {
    final alarmProv = context.read<AlarmProvider>();
    if (_assignExisting != null) {
      alarmProv.updateAlarmPoint(alarm);
    } else if (alarmProv.canAddAlarm) {
      alarmProv.addAlarmPoint(alarm);
    }
    _cancelAssign();
  }

  void _cancelAssign() {
    setState(() {
      _isAssigning = false;
      _assignCenter = null;
      _assignExisting = null;
      _assignRadius = 500;
      _assignZoneTrigger = ZoneTrigger.onEntry;
      _assignTriggerType = TriggerType.distance;
      _assignTimeMinutes = 10;
      _longPressTriggered = false;
      _longPressScreenOffset = null;
      _pointerDownPos = null;
      _activePointers = 0;
    });
  }

  String _getTileUrl(AppSettings settings) {
    switch (settings.mapProvider) {
      case MapTileProvider.googleMaps:
        final key = settings.googleMapsApiKey ?? '';
        return 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&scale=2&key=$key';
      case MapTileProvider.mapTiler:
        final key = settings.mapTilerApiKey ?? '';
        final style = settings.mapTilerStyle;
        return 'https://api.maptiler.com/maps/$style/{z}/{x}/{y}@2x.png?key=$key';
      case MapTileProvider.free:
        return _getFreeTileUrl(settings.mapTileStyle);
      case MapTileProvider.vector:
        return '';
    }
  }

  String _getFreeTileUrl(MapTileStyle style) {
    switch (style) {
      case MapTileStyle.standard:
        // OSM standard nem támogat @2x, CartoDB Voyager az OSM-hez legközelebbi @2x
        return 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png';
      case MapTileStyle.humanitarian:
        // HOT stílus nem támogat @2x, CartoDB light az ehhez legközelebbi
        return 'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png';
      case MapTileStyle.topo:
        // OpenTopoMap nem támogat @2x — marad eredeti
        return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
      case MapTileStyle.positron:
        return 'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png';
      case MapTileStyle.voyager:
        return 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png';
      case MapTileStyle.darkMatter:
        return 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png';
    }
  }
}
