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
import '../widgets/user_location_marker.dart';
import '../services/location_service.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import 'settings_screen.dart';
import '../services/debug_console.dart';
import '../widgets/maplibre_new_view.dart';
import '../widgets/offline_indicator.dart';
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

  // Pending tap pin (shown while create popup is open)
  LatLng? _pendingTapPoint;

  // Fast assign state
  LatLng? _fastAssignCenter;
  double _fastAssignRadiusMeters = 500;
  bool _isFastAssigning = false;
  Offset? _fastAssignStartOffset; // screen position of long press
  // Long press timer for custom detection
  Timer? _longPressTimer;
  Offset? _pointerDownPos;
  bool _longPressTriggered = false;

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
      DebugConsole.log('Starting GPS tracking');
      _locationService.startTracking(onPosition: (position) {
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
      });
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
        final dist = AlarmService.distanceMeters(
            userLat, userLng, point.latitude, point.longitude);
        final eta = AlarmService.calculateEtaMinutes(
          distanceMeters: dist,
          speedKmh: _locationService.averageSpeedKmh,
        );
        if (eta != null && eta <= point.timeTrigger!.inMinutes) {
          shouldTrigger = true;
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
    _locationService.dispose();
    _userPosition.dispose();
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
        body: MaplibreNewView(scaffoldKey: _scaffoldKey),
        drawer: const SettingsDrawer(),
      );
    }

    final tileUrl = context.select<SettingsProvider, String>(
        (p) => _getTileUrl(p.settings));
    DebugConsole.log('build() tile=$tileUrl');

    return Scaffold(
      key: _scaffoldKey,
      body: Stack(
        children: [
          // Long press gesture layer on top of map
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _isFastAssigning ? null : _onPointerDown,
            onPointerMove: _isFastAssigning ? null : _onPointerMove,
            onPointerUp: _isFastAssigning ? null : _onPointerUp,
            onPointerCancel: _isFastAssigning ? null : (_) {
              _activePointers = (_activePointers - 1).clamp(0, 99);
              _cancelLongPressTimer();
            },
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: context.read<MapProvider>().center,
                initialZoom: context.read<MapProvider>().zoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: _isFastAssigning
                    ? null
                    : (tapPosition, point) => _handleTap(context, point),
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture) {
                    _cancelLongPressTimer();
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
              // Radius circles - only rebuilds when alarms change
              Consumer<AlarmProvider>(
                builder: (_, alarmProv, __) => CircleLayer(
                  circles: [
                    ...alarmProv.alarmPoints
                        .map((p) => buildRadiusCircle(p)),
                    if (_isFastAssigning && _fastAssignCenter != null)
                      CircleMarker(
                        point: _fastAssignCenter!,
                        radius: _fastAssignRadiusMeters,
                        useRadiusInMeter: true,
                        color: Colors.red.withOpacity(0.15),
                        borderColor: Colors.red.withOpacity(0.7),
                        borderStrokeWidth: 3,
                      ),
                  ],
                ),
              ),
              // Pin markers - rebuilds only on alarm or GPS change
              Consumer<AlarmProvider>(
                builder: (_, alarmProv, __) =>
                    ValueListenableBuilder<LatLng?>(
                  valueListenable: _userPosition,
                  builder: (_, userPos, __) => MarkerLayer(
                    markers: [
                      ...alarmProv.alarmPoints.map((p) => buildPinMarker(
                            point: p,
                            onTap: () => _showEditPopup(context, p),
                          )),
                      if (userPos != null)
                        buildUserLocationMarker(userPos),
                      // Pending tap pin
                      if (_pendingTapPoint != null)
                        Marker(
                          point: _pendingTapPoint!,
                          width: 40,
                          height: 50,
                          // Icon tip at y=36 in 50px box → alignment y = (36-25)/25 = 0.44
                          alignment: const Alignment(0, 0.44),
                          child: const Icon(Icons.location_on,
                              color: Colors.red, size: 36),
                        ),
                      // Fast assign pin
                      if (_isFastAssigning && _fastAssignCenter != null)
                        Marker(
                          point: _fastAssignCenter!,
                          width: 40,
                          height: 40,
                          // Icon tip at y=32 in 40px box → alignment y = (32-20)/20 = 0.6
                          alignment: const Alignment(0, 0.6),
                          child: const Icon(Icons.location_on,
                              color: Colors.red, size: 32),
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
          // Controls - only rebuilds when search state changes
          if (!_isFastAssigning)
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
          if (!_isFastAssigning)
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
                    )
                  : const SizedBox.shrink(),
            ),
          // Fast assign card — Positioned overlay, does NOT block map gestures
          if (_isFastAssigning)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _FastAssignCard(
                initialRadius: _fastAssignRadiusMeters,
                onRadiusChanged: (v) => setState(() => _fastAssignRadiusMeters = v),
                onSave: _saveFastAssign,
                onCancel: _cancelFastAssign,
              ),
            ),
        ],
      ),
      drawer: const SettingsDrawer(),
    );
  }

  int _activePointers = 0;

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    // Multi-touch (pinch zoom) — cancel long press
    if (_activePointers > 1) {
      _cancelLongPressTimer();
      return;
    }
    if (_isFastAssigning) return;
    _pointerDownPos = event.position;
    _longPressTriggered = false;
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (_pointerDownPos == null) return;
      _longPressTriggered = true;
      final screenPoint = Point<double>(
          event.localPosition.dx, event.localPosition.dy);
      final latLng = _mapController.camera.pointToLatLng(screenPoint);
      DebugConsole.log('LONG PRESS START at ${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}');
      // Haptic feedback
      final haptic = context.read<SettingsProvider>().settings.hapticFeedback;
      if (haptic) {
        Vibration.vibrate(duration: 30);
      }
      _handleLongPress(context, latLng, event.position);
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    // If long press not yet triggered, check if moved too far (cancel)
    if (!_longPressTriggered && _pointerDownPos != null) {
      final dist = (event.position - _pointerDownPos!).distance;
      if (dist > 20) {
        _cancelLongPressTimer();
      }
      return;
    }
    // Long press active — update radius based on swipe distance
    if (_isFastAssigning && _fastAssignStartOffset != null) {
      final dx = event.position.dx - _fastAssignStartOffset!.dx;
      final dy = event.position.dy - _fastAssignStartOffset!.dy;
      final pixelDist = sqrt(dx * dx + dy * dy);
      final meters = _pixelsToMeters(pixelDist).clamp(100.0, 5000.0);
      setState(() => _fastAssignRadiusMeters = meters);
      DebugConsole.log('SWIPE radius: ${meters.round()}m (${pixelDist.round()}px)');
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 99);
    _cancelLongPressTimer();
    if (_longPressTriggered && _isFastAssigning) {
      DebugConsole.log('LONG PRESS RELEASED — radius: ${_fastAssignRadiusMeters.round()}m');
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
      DebugConsole.log('Jump to my location: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}');
    }
  }

  void _handleTap(BuildContext context, LatLng point) {
    if (_isFastAssigning) return;
    final alarmProv = context.read<AlarmProvider>();
    final existing = alarmProv.findNearby(point.latitude, point.longitude);
    if (existing != null) {
      _showEditPopup(context, existing);
    } else {
      // Show pending pin on map
      setState(() => _pendingTapPoint = point);
      _showCreatePopup(context, point);
    }
  }

  void _handleLongPress(BuildContext context, LatLng point, Offset screenOffset) {
    setState(() {
      _isFastAssigning = true;
      _fastAssignCenter = point;
      _fastAssignRadiusMeters = 200;
      _fastAssignStartOffset = screenOffset;
    });
  }

  void _saveFastAssign(String? name, TriggerType triggerType, ZoneTrigger zoneTrigger, int timeMinutes) {
    if (_fastAssignCenter == null) return;
    final alarmProv = context.read<AlarmProvider>();
    if (alarmProv.canAddAlarm) {
      alarmProv.addAlarmPoint(AlarmPoint(
        id: const Uuid().v4(),
        name: name,
        latitude: _fastAssignCenter!.latitude,
        longitude: _fastAssignCenter!.longitude,
        radiusMeters: triggerType == TriggerType.distance ? _fastAssignRadiusMeters : 0,
        triggerType: triggerType,
        zoneTrigger: zoneTrigger,
        timeTrigger: triggerType == TriggerType.time ? Duration(minutes: timeMinutes) : null,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('fast_alarm', args: [_fastAssignRadiusMeters.round().toString()]))),
      );
    }
    _cancelFastAssign();
  }

  void _cancelFastAssign() {
    setState(() {
      _isFastAssigning = false;
      _fastAssignCenter = null;
      _fastAssignRadiusMeters = 500;
      _fastAssignStartOffset = null;
      _longPressTriggered = false;
      _pointerDownPos = null;
      _activePointers = 0;
    });
    DebugConsole.log('Fast assign closed, state reset');
  }



  void _showCreatePopup(BuildContext context, LatLng point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RadiusPopup(
        latitude: point.latitude,
        longitude: point.longitude,
      ),
    ).whenComplete(() {
      // Clear pending pin when popup closes (saved or cancelled)
      if (mounted) setState(() => _pendingTapPoint = null);
    });
  }

  void _showEditPopup(BuildContext context, AlarmPoint alarmPoint) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RadiusPopup(
        latitude: alarmPoint.latitude,
        longitude: alarmPoint.longitude,
        existingPoint: alarmPoint,
      ),
    );
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

/// Fast assign card — inline Positioned overlay, NO showBottomSheet.
/// Has its own state so slider doesn't trigger parent rebuild (no build spam).
/// Expandable: tap chevron to reveal name/trigger options.
class _FastAssignCard extends StatefulWidget {
  final double initialRadius;
  final ValueChanged<double> onRadiusChanged;
  final void Function(String? name, TriggerType triggerType, ZoneTrigger zoneTrigger, int timeMinutes) onSave;
  final VoidCallback onCancel;

  const _FastAssignCard({
    required this.initialRadius,
    required this.onRadiusChanged,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_FastAssignCard> createState() => _FastAssignCardState();
}

class _FastAssignCardState extends State<_FastAssignCard> {
  late double _radius;
  bool _expanded = false;
  final _nameController = TextEditingController();
  TriggerType _triggerType = TriggerType.distance;
  ZoneTrigger _zoneTrigger = ZoneTrigger.onEntry;
  int _timeMinutes = 10;

  @override
  void initState() {
    super.initState();
    _radius = widget.initialRadius;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1a1a2e) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Drag handle — tap to expand/collapse
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Compact header: icon + "Fast Assign" + radius + expand chevron
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
              child: Row(children: [
                const Icon(Icons.location_on, color: Colors.red, size: 28),
                const SizedBox(width: 8),
                const Expanded(child: Text('Fast Assign',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                Text('${_radius.round()}m',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red[700])),
                IconButton(
                  icon: Icon(_expanded ? Icons.expand_more : Icons.expand_less, size: 24),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ]),
            ),
            // Slider — always visible
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Slider(
                value: _radius, min: 100, max: 5000, divisions: 49,
                activeColor: Colors.red,
                onChanged: (v) {
                  setState(() => _radius = v);
                  widget.onRadiusChanged(v);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('100m', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  Text('5km', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            // Expanded section
            if (_expanded) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: tr('name_optional')),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('trigger_type'),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  Row(children: [
                    _chip(tr('distance'), Icons.straighten, _triggerType == TriggerType.distance,
                        () => setState(() => _triggerType = TriggerType.distance)),
                    const SizedBox(width: 8),
                    _chip(tr('time'), Icons.timer, _triggerType == TriggerType.time,
                        () => setState(() => _triggerType = TriggerType.time)),
                  ]),
                  if (_triggerType == TriggerType.time) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: Slider(
                        value: _timeMinutes.toDouble(), min: 5, max: 120, divisions: 23,
                        onChanged: (v) => setState(() => _timeMinutes = v.round()),
                      )),
                      Text('$_timeMinutes min',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    _chip(tr('on_entry'), Icons.login, _zoneTrigger == ZoneTrigger.onEntry,
                        () => setState(() => _zoneTrigger = ZoneTrigger.onEntry)),
                    const SizedBox(width: 8),
                    _chip(tr('on_leave'), Icons.logout, _zoneTrigger == ZoneTrigger.onLeave,
                        () => setState(() => _zoneTrigger = ZoneTrigger.onLeave)),
                  ]),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            // Buttons — always visible
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottomPad),
              child: Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: widget.onCancel,
                  child: Text(tr('cancel')),
                )),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(
                  onPressed: () {
                    final name = _nameController.text.isEmpty ? null : _nameController.text;
                    widget.onSave(name, _triggerType, _zoneTrigger, _timeMinutes);
                  },
                  child: Text(tr('save')),
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.grey[300]!,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Icon(icon, color: selected ? Theme.of(context).colorScheme.primary : Colors.grey),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
            )),
          ]),
        ),
      ),
    );
  }
}
