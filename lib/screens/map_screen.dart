import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import '../models/alarm_point.dart';
import '../providers/map_provider.dart';
import '../providers/alarm_provider.dart';
import '../widgets/map_controls.dart';
import '../widgets/search_pill.dart';
import '../widgets/pin_marker.dart';
import '../widgets/radius_circle.dart';
import '../widgets/radius_popup.dart';
import '../widgets/user_location_marker.dart';
import '../services/location_service.dart';
import '../services/alarm_service.dart';
import 'settings_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  LatLng? _userPosition;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Fast assign state
  LatLng? _fastAssignCenter;
  double _fastAssignRadiusMeters = 0;
  bool _isFastAssigning = false;
  Offset? _fastAssignStartPixel;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final hasPermission = await _locationService.requestPermission();
    if (hasPermission) {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null && mounted) {
        setState(() {
          _userPosition = LatLng(pos.latitude, pos.longitude);
        });
        final mapProv = context.read<MapProvider>();
        mapProv.setCenter(_userPosition!);
        _mapController.move(_userPosition!, mapProv.zoom);
      }
      // Start continuous GPS tracking for alarm monitoring
      _locationService.startTracking(onPosition: (position) {
        if (!mounted) return;
        setState(() {
          _userPosition = LatLng(position.latitude, position.longitude);
        });
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
        // Deactivate alarm
        alarmProv.toggleActive(point.id);
        // Show alarm notification
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
    super.dispose();
  }

  double _pixelsToMeters(double pixels) {
    final zoom = _mapController.camera.zoom;
    // At zoom 0, 1 pixel ≈ 156543 meters at equator
    // meters per pixel = 156543 / 2^zoom
    final metersPerPixel = 156543.03392 / pow(2, zoom);
    return pixels * metersPerPixel;
  }

  @override
  Widget build(BuildContext context) {
    final mapProv = context.watch<MapProvider>();
    final alarmProv = context.watch<AlarmProvider>();

    return Scaffold(
      key: _scaffoldKey,
      body: Stack(
        children: [
          // Map with gesture detector for fast assign
          GestureDetector(
            onPanUpdate: _isFastAssigning ? _onFastAssignPan : null,
            onPanEnd: _isFastAssigning ? _onFastAssignEnd : null,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: mapProv.center,
                initialZoom: mapProv.zoom,
                interactionOptions: InteractionOptions(
                  flags: _isFastAssigning
                      ? InteractiveFlag.none
                      : InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (tapPosition, point) => _handleTap(context, point),
                onLongPress: (tapPosition, point) =>
                    _handleLongPressStart(tapPosition, point),
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture && !_isFastAssigning) {
                    mapProv.setCenter(position.center);
                    mapProv.setZoom(position.zoom);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.gpsalarm.app',
                ),
                // Radius circles
                CircleLayer(
                  circles: [
                    ...alarmProv.alarmPoints
                        .map((p) => buildRadiusCircle(p)),
                    // Fast assign preview circle
                    if (_isFastAssigning && _fastAssignCenter != null)
                      CircleMarker(
                        point: _fastAssignCenter!,
                        radius: _fastAssignRadiusMeters.clamp(100, 5000),
                        useRadiusInMeter: true,
                        color: Colors.orange.withOpacity(0.15),
                        borderColor: Colors.orange.withOpacity(0.7),
                        borderStrokeWidth: 3,
                      ),
                  ],
                ),
                // Pin markers + user location
                MarkerLayer(
                  markers: [
                    ...alarmProv.alarmPoints.map((p) => buildPinMarker(
                          point: p,
                          onTap: () => _showEditPopup(context, p),
                        )),
                    if (_userPosition != null)
                      buildUserLocationMarker(_userPosition!),
                  ],
                ),
              ],
            ),
          ),
          // Controls overlay
          MapControls(
            onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
            onZoomIn: () {
              mapProv.zoomIn();
              _mapController.move(mapProv.center, mapProv.zoom);
            },
            onZoomOut: () {
              mapProv.zoomOut();
              _mapController.move(mapProv.center, mapProv.zoom);
            },
            onSearchTap: () => mapProv.toggleSearch(),
            searchActive: mapProv.searchActive,
          ),
          // Search pill
          if (mapProv.searchActive)
            SearchPill(
              onResultSelected: (result) {
                mapProv.goToSearchResult(result);
                _mapController.move(
                  LatLng(result.latitude, result.longitude),
                  14.0,
                );
              },
            ),
          // Fast assign radius display
          if (_isFastAssigning)
            Positioned(
              bottom: 100,
              left: 50,
              right: 50,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_fastAssignRadiusMeters.clamp(100, 5000).round()}m',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Húzd kifelé a sugár beállításához',
                      style: TextStyle(
                          color: Colors.orange[200], fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      drawer: _buildDrawer(context),
    );
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

  void _handleLongPressStart(TapPosition tapPosition, LatLng point) {
    setState(() {
      _isFastAssigning = true;
      _fastAssignCenter = point;
      _fastAssignRadiusMeters = 200;
      _fastAssignStartPixel = tapPosition.global;
    });
  }

  void _onFastAssignPan(DragUpdateDetails details) {
    if (_fastAssignStartPixel == null) return;
    final dx = details.globalPosition.dx - _fastAssignStartPixel!.dx;
    final dy = details.globalPosition.dy - _fastAssignStartPixel!.dy;
    final pixelDistance = sqrt(dx * dx + dy * dy);
    setState(() {
      _fastAssignRadiusMeters = _pixelsToMeters(pixelDistance).clamp(100, 5000);
    });
  }

  void _onFastAssignEnd(DragEndDetails details) {
    if (_fastAssignCenter == null) return;
    final alarmProv = context.read<AlarmProvider>();
    final radius = _fastAssignRadiusMeters.clamp(100.0, 5000.0);

    if (alarmProv.canAddAlarm) {
      final point = AlarmPoint(
        id: const Uuid().v4(),
        latitude: _fastAssignCenter!.latitude,
        longitude: _fastAssignCenter!.longitude,
        radiusMeters: radius,
        triggerType: TriggerType.distance,
      );
      alarmProv.addAlarmPoint(point);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('fast_alarm', args: [radius.round().toString()])),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    setState(() {
      _isFastAssigning = false;
      _fastAssignCenter = null;
      _fastAssignRadiusMeters = 0;
      _fastAssignStartPixel = null;
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

  Widget _buildDrawer(BuildContext context) {
    return const SettingsDrawer();
  }
}
