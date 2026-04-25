import 'dart:math';
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
import 'settings_screen.dart';
import '../services/debug_console.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final ValueNotifier<LatLng?> _userPosition = ValueNotifier(null);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Fast assign state
  LatLng? _fastAssignCenter;
  double _fastAssignRadiusMeters = 500;
  bool _isFastAssigning = false;

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

      if (point.triggerType == TriggerType.distance) {
        shouldTrigger = AlarmService.isWithinRadius(
          userLat: userLat,
          userLng: userLng,
          pointLat: point.latitude,
          pointLng: point.longitude,
          radiusMeters: point.radiusMeters,
        );
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.alarm, color: Colors.red, size: 48),
        title: Text(point.name ?? tr('no_name')),
        content: Text(point.triggerType == TriggerType.distance
            ? '${point.radiusMeters.round()}m'
            : '${point.timeTrigger?.inMinutes ?? 0} min'),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();
    final tileUrl = context.select<SettingsProvider, String>(
        (p) => _getTileUrl(p.settings));
    DebugConsole.log('build() tile=$tileUrl');

    return Scaffold(
      key: _scaffoldKey,
      body: Stack(
        children: [
          // Map - uses read, not watch, for providers accessed via callbacks
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: context.read<MapProvider>().center,
              initialZoom: context.read<MapProvider>().zoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: (tapPosition, point) => _handleTap(context, point),
              onLongPress: (tapPosition, point) =>
                  _handleLongPress(context, point),
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                  // DON'T update providers on every pan/zoom frame - causes rebuilds
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                userAgentPackageName: 'com.gpsalarm.app',
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
                        color: Colors.orange.withOpacity(0.15),
                        borderColor: Colors.orange.withOpacity(0.7),
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
                      if (_isFastAssigning && _fastAssignCenter != null)
                        Marker(
                          point: _fastAssignCenter!,
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_on,
                              color: Colors.orange, size: 32),
                        ),
                    ],
                  ),
                ),
              ),
            ],
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
          // Fast assign overlay
          if (_isFastAssigning) _buildFastAssignOverlay(),
        ],
      ),
      drawer: const SettingsDrawer(),
    );
  }

  Widget _buildFastAssignOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1a1a2e)
              : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on,
                    color: Colors.orange, size: 28),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Fast Assign',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Text(
                  '${_fastAssignRadiusMeters.round()}m',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Slider(
              value: _fastAssignRadiusMeters,
              min: 100,
              max: 5000,
              divisions: 49,
              activeColor: Colors.orange,
              label: '${_fastAssignRadiusMeters.round()}m',
              onChanged: (v) =>
                  setState(() => _fastAssignRadiusMeters = v),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('100m',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[500])),
                Text('5km',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelFastAssign,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(tr('cancel')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _confirmFastAssign,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(tr('save')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
      _showCreatePopup(context, point);
    }
  }

  void _handleLongPress(BuildContext context, LatLng point) {
    setState(() {
      _isFastAssigning = true;
      _fastAssignCenter = point;
      _fastAssignRadiusMeters = 500;
    });
  }

  void _cancelFastAssign() {
    setState(() {
      _isFastAssigning = false;
      _fastAssignCenter = null;
      _fastAssignRadiusMeters = 500;
    });
  }

  void _confirmFastAssign() {
    if (_fastAssignCenter == null) return;
    final alarmProv = context.read<AlarmProvider>();

    if (alarmProv.canAddAlarm) {
      final point = AlarmPoint(
        id: const Uuid().v4(),
        latitude: _fastAssignCenter!.latitude,
        longitude: _fastAssignCenter!.longitude,
        radiusMeters: _fastAssignRadiusMeters,
        triggerType: TriggerType.distance,
      );
      alarmProv.addAlarmPoint(point);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('fast_alarm',
              args: [_fastAssignRadiusMeters.round().toString()])),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    setState(() {
      _isFastAssigning = false;
      _fastAssignCenter = null;
      _fastAssignRadiusMeters = 500;
    });
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
    );
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
        return 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&key=$key';
      case MapTileProvider.mapTiler:
        final key = settings.mapTilerApiKey ?? '';
        final style = settings.mapTilerStyle;
        return 'https://api.maptiler.com/maps/$style/{z}/{x}/{y}.png?key=$key';
      case MapTileProvider.free:
        return _getFreeTileUrl(settings.mapTileStyle);
    }
  }

  String _getFreeTileUrl(MapTileStyle style) {
    switch (style) {
      case MapTileStyle.standard:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapTileStyle.humanitarian:
        return 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png';
      case MapTileStyle.topo:
        return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
      case MapTileStyle.positron:
        return 'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
      case MapTileStyle.voyager:
        return 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
      case MapTileStyle.darkMatter:
        return 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
    }
  }
}
