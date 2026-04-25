import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import '../models/alarm_point.dart';
import '../models/app_settings.dart';
import '../providers/alarm_provider.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/map_controls.dart';
import '../widgets/radius_popup.dart';
import '../services/location_service.dart';
import '../services/alarm_service.dart';
import '../services/debug_console.dart';

class VectorMapView extends StatefulWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;

  const VectorMapView({super.key, required this.scaffoldKey});

  @override
  State<VectorMapView> createState() => _VectorMapViewState();
}

class _VectorMapViewState extends State<VectorMapView> {
  MapLibreMapController? _controller;
  final LocationService _locationService = LocationService();
  LatLng? _userPosition;

  // Fast assign
  bool _isFastAssigning = false;
  LatLng? _fastAssignCenter;
  double _fastAssignRadiusMeters = 500;

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
        _userPosition = LatLng(pos.latitude, pos.longitude);
        _controller?.animateCamera(
          CameraUpdate.newLatLng(_userPosition!),
        );
      }
      _locationService.startTracking(onPosition: (position) {
        if (!mounted) return;
        _userPosition = LatLng(position.latitude, position.longitude);
        _checkAlarms(position.latitude, position.longitude);
      });
    }
  }

  void _checkAlarms(double userLat, double userLng) {
    final alarmProv = context.read<AlarmProvider>();
    for (final point in alarmProv.alarmPoints.where((p) => p.isActive)) {
      bool shouldTrigger = false;
      if (point.triggerType == TriggerType.distance) {
        shouldTrigger = AlarmService.isWithinRadius(
          userLat: userLat, userLng: userLng,
          pointLat: point.latitude, pointLng: point.longitude,
          radiusMeters: point.radiusMeters,
        );
      } else if (point.triggerType == TriggerType.time && point.timeTrigger != null) {
        final dist = AlarmService.distanceMeters(userLat, userLng, point.latitude, point.longitude);
        final eta = AlarmService.calculateEtaMinutes(distanceMeters: dist, speedKmh: _locationService.averageSpeedKmh);
        if (eta != null && eta <= point.timeTrigger!.inMinutes) shouldTrigger = true;
      }
      if (shouldTrigger) {
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
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    DebugConsole.log('Vector map created');
    if (_userPosition != null) {
      controller.animateCamera(CameraUpdate.newLatLng(_userPosition!));
    }
  }

  void _onMapClick(Point<double> point, LatLng coordinates) {
    if (_isFastAssigning) return;
    final alarmProv = context.read<AlarmProvider>();
    final existing = alarmProv.findNearby(coordinates.latitude, coordinates.longitude);
    if (existing != null) {
      _showEditPopup(existing);
    } else {
      _showCreatePopup(coordinates);
    }
  }

  void _onMapLongClick(Point<double> point, LatLng coordinates) {
    setState(() {
      _isFastAssigning = true;
      _fastAssignCenter = coordinates;
      _fastAssignRadiusMeters = 500;
    });
  }

  void _showCreatePopup(LatLng point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RadiusPopup(latitude: point.latitude, longitude: point.longitude),
    );
  }

  void _showEditPopup(AlarmPoint alarmPoint) {
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

  void _goToMyLocation() {
    if (_userPosition != null) {
      _controller?.animateCamera(CameraUpdate.newLatLngZoom(_userPosition!, 15));
    }
  }

  void _cancelFastAssign() {
    setState(() {
      _isFastAssigning = false;
      _fastAssignCenter = null;
    });
  }

  void _confirmFastAssign() {
    if (_fastAssignCenter == null) return;
    final alarmProv = context.read<AlarmProvider>();
    if (alarmProv.canAddAlarm) {
      alarmProv.addAlarmPoint(AlarmPoint(
        id: const Uuid().v4(),
        latitude: _fastAssignCenter!.latitude,
        longitude: _fastAssignCenter!.longitude,
        radiusMeters: _fastAssignRadiusMeters,
        triggerType: TriggerType.distance,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('fast_alarm', args: [_fastAssignRadiusMeters.round().toString()]))),
      );
    }
    setState(() {
      _isFastAssigning = false;
      _fastAssignCenter = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final styleUrl = context.select<SettingsProvider, String>(
        (p) => p.settings.vectorStyleUrl);

    return Stack(
      children: [
        MapLibreMap(
          styleString: styleUrl,
          initialCameraPosition: const CameraPosition(
            target: LatLng(47.4979, 19.0402),
            zoom: 13,
          ),
          onMapCreated: _onMapCreated,
          onMapClick: _onMapClick,
          onMapLongClick: _onMapLongClick,
          rotateGesturesEnabled: false,
          myLocationEnabled: true,
          myLocationTrackingMode: MyLocationTrackingMode.none,
        ),
        // Controls
        if (!_isFastAssigning)
          MapControls(
            onMenuTap: () => widget.scaffoldKey.currentState?.openDrawer(),
            onZoomIn: () => _controller?.animateCamera(CameraUpdate.zoomIn()),
            onZoomOut: () => _controller?.animateCamera(CameraUpdate.zoomOut()),
            onSearchTap: () => context.read<MapProvider>().toggleSearch(),
            onMyLocation: _goToMyLocation,
            searchActive: false,
          ),
        // Fast assign overlay
        if (_isFastAssigning)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1a1a2e) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    const Icon(Icons.location_on, color: Colors.orange, size: 28),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Fast Assign', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    Text('${_fastAssignRadiusMeters.round()}m', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange[700])),
                  ]),
                  const SizedBox(height: 12),
                  Slider(value: _fastAssignRadiusMeters, min: 100, max: 5000, divisions: 49, activeColor: Colors.orange,
                    onChanged: (v) => setState(() => _fastAssignRadiusMeters = v)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: _cancelFastAssign, child: Text(tr('cancel')))),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton(onPressed: _confirmFastAssign,
                      style: FilledButton.styleFrom(backgroundColor: Colors.orange), child: Text(tr('save')))),
                  ]),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
