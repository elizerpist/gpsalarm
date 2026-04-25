import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import '../models/alarm_point.dart';
import '../models/app_settings.dart';
import '../providers/alarm_provider.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/map_controls.dart';
import '../widgets/radius_popup.dart';
import '../widgets/pin_marker.dart';
import '../widgets/radius_circle.dart';
import '../widgets/user_location_marker.dart';
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
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final ValueNotifier<LatLng?> _userPosition = ValueNotifier(null);

  // Fast assign
  bool _isFastAssigning = false;
  LatLng? _fastAssignCenter;
  double _fastAssignRadiusMeters = 500;
  Offset? _fastAssignStartOffset;
  Timer? _longPressTimer;
  Offset? _pointerDownPos;
  bool _longPressTriggered = false;

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
        _userPosition.value = LatLng(pos.latitude, pos.longitude);
        _mapController.move(_userPosition.value!, 14);
      }
      _locationService.startTracking(onPosition: (position) {
        if (!mounted) return;
        final newPos = LatLng(position.latitude, position.longitude);
        if (_userPosition.value == null ||
            AlarmService.distanceMeters(
                    _userPosition.value!.latitude,
                    _userPosition.value!.longitude,
                    newPos.latitude,
                    newPos.longitude) >
                5) {
          _userPosition.value = newPos;
        }
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
            speedKmh: _locationService.averageSpeedKmh);
        if (eta != null && eta <= point.timeTrigger!.inMinutes) {
          shouldTrigger = true;
        }
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
    _longPressTimer?.cancel();
    super.dispose();
  }

  // --- Long press + swipe ---

  void _onPointerDown(PointerDownEvent event) {
    if (_isFastAssigning) return;
    _pointerDownPos = event.position;
    _longPressTriggered = false;
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (_pointerDownPos == null) return;
      _longPressTriggered = true;
      final screenPoint = Point<double>(
          event.localPosition.dx, event.localPosition.dy);
      final latLng = _mapController.camera.pointToLatLng(screenPoint);
      setState(() {
        _isFastAssigning = true;
        _fastAssignCenter = latLng;
        _fastAssignRadiusMeters = 200;
        _fastAssignStartOffset = event.position;
      });
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_longPressTriggered && _pointerDownPos != null) {
      if ((event.position - _pointerDownPos!).distance > 20) {
        _longPressTimer?.cancel();
      }
      return;
    }
    if (_isFastAssigning && _fastAssignStartOffset != null) {
      final dx = event.position.dx - _fastAssignStartOffset!.dx;
      final dy = event.position.dy - _fastAssignStartOffset!.dy;
      final pixelDist = sqrt(dx * dx + dy * dy);
      final zoom = _mapController.camera.zoom;
      final metersPerPixel = 156543.03392 *
          cos(_mapController.camera.center.latitude * pi / 180) /
          pow(2, zoom);
      final meters = (pixelDist * metersPerPixel).clamp(100.0, 5000.0);
      setState(() => _fastAssignRadiusMeters = meters);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _longPressTimer?.cancel();
    _longPressTriggered = false;
    _pointerDownPos = null;
  }

  void _cancelFastAssign() {
    setState(() {
      _isFastAssigning = false;
      _fastAssignCenter = null;
      _fastAssignStartOffset = null;
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
        SnackBar(
            content: Text(tr('fast_alarm',
                args: [_fastAssignRadiusMeters.round().toString()]))),
      );
    }
    _cancelFastAssign();
  }

  void _handleTap(BuildContext context, LatLng point) {
    if (_isFastAssigning) return;
    final alarmProv = context.read<AlarmProvider>();
    final existing =
        alarmProv.findNearby(point.latitude, point.longitude);
    if (existing != null) {
      _showEditPopup(existing);
    } else {
      _showCreatePopup(point);
    }
  }

  void _showCreatePopup(LatLng point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          RadiusPopup(latitude: point.latitude, longitude: point.longitude),
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
    final pos = _userPosition.value;
    if (pos != null) _mapController.move(pos, 15);
  }

  // --- Vector tile style ---

  Style _getVectorStyle(String styleUrl) {
    // OpenFreeMap and Versatiles use standard MVT
    if (styleUrl.contains('versatiles')) {
      return Style(
        theme: ProvidedThemes.versatiles(),
        sources: {
          'versatiles': VectorTileProvider(
            urlTemplate:
                'https://tiles.versatiles.org/tiles/osm/{z}/{x}/{y}',
            maximumZoom: 14,
          ),
        },
      );
    }
    // Default: OpenFreeMap liberty style via style URL
    return Style(
      theme: ProvidedThemes.openStreetMap(),
      sources: {
        'openmaptiles': VectorTileProvider(
          urlTemplate:
              'https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf',
          maximumZoom: 14,
        ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final styleUrl = context.select<SettingsProvider, String>(
        (p) => p.settings.vectorStyleUrl);
    final alarmProv = context.watch<AlarmProvider>();

    return Stack(
      children: [
        Listener(
          behavior: _isFastAssigning
              ? HitTestBehavior.opaque
              : HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: (_) => _longPressTimer?.cancel(),
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(47.4979, 19.0402),
              initialZoom: 13,
              interactionOptions: InteractionOptions(
                flags: _isFastAssigning
                    ? InteractiveFlag.none
                    : InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: _isFastAssigning
                  ? null
                  : (tapPosition, point) => _handleTap(context, point),
            ),
            children: [
              VectorTileLayer(
                tileProviders:
                    _getVectorStyle(styleUrl).sources.cast(),
                theme: _getVectorStyle(styleUrl).theme,
              ),
              CircleLayer(
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
              Consumer<AlarmProvider>(
                builder: (_, ap, __) => ValueListenableBuilder<LatLng?>(
                  valueListenable: _userPosition,
                  builder: (_, userPos, __) => MarkerLayer(
                    markers: [
                      ...ap.alarmPoints.map((p) => buildPinMarker(
                            point: p,
                            onTap: () => _showEditPopup(p),
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
        ),
        // Controls
        if (!_isFastAssigning)
          MapControls(
            onMenuTap: () =>
                widget.scaffoldKey.currentState?.openDrawer(),
            onZoomIn: () {
              final cam = _mapController.camera;
              _mapController.move(
                  cam.center, (cam.zoom + 1).clamp(3, 18));
            },
            onZoomOut: () {
              final cam = _mapController.camera;
              _mapController.move(
                  cam.center, (cam.zoom - 1).clamp(3, 18));
            },
            onSearchTap: () =>
                context.read<MapProvider>().toggleSearch(),
            onMyLocation: _goToMyLocation,
            searchActive: false,
          ),
        // Fast assign panel
        if (_isFastAssigning)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1a1a2e)
                    : Colors.white,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, -4))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    const Icon(Icons.location_on,
                        color: Colors.orange, size: 28),
                    const SizedBox(width: 8),
                    const Expanded(
                        child: Text('Fast Assign',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold))),
                    Text('${_fastAssignRadiusMeters.round()}m',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700])),
                  ]),
                  const SizedBox(height: 12),
                  Slider(
                    value: _fastAssignRadiusMeters,
                    min: 100,
                    max: 5000,
                    divisions: 49,
                    activeColor: Colors.orange,
                    onChanged: (v) =>
                        setState(() => _fastAssignRadiusMeters = v),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: _cancelFastAssign,
                            child: Text(tr('cancel')))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: FilledButton(
                            onPressed: _confirmFastAssign,
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange),
                            child: Text(tr('save')))),
                  ]),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
