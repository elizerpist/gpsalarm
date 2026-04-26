import 'dart:async';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import 'package:vibration/vibration.dart';
import '../models/alarm_point.dart';
import '../providers/alarm_provider.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/map_controls.dart';
import '../widgets/search_pill.dart';
import '../widgets/radius_popup.dart';
import '../widgets/offline_indicator.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import '../services/debug_console.dart';

class MaplibreNewView extends StatefulWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  const MaplibreNewView({super.key, required this.scaffoldKey});

  @override
  State<MaplibreNewView> createState() => _MaplibreNewViewState();
}

class _MaplibreNewViewState extends State<MaplibreNewView> {
  MapController? _controller;
  final LocationService _locationService = LocationService();
  bool _isFastAssigning = false;
  double _fastAssignLat = 0;
  double _fastAssignLng = 0;
  double _fastAssignRadiusMeters = 500;
  double _currentZoom = 13;
  Position? _pendingTapPoint;
  Position? _userPos;

  static const _styleUrls = {
    'liberty': 'https://tiles.openfreemap.org/styles/liberty',
    'bright': 'https://tiles.openfreemap.org/styles/bright',
    'positron': 'https://tiles.openfreemap.org/styles/positron',
  };

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
        setState(() => _userPos = Position(pos.longitude, pos.latitude));
        _controller?.moveCamera(
          center: Position(pos.longitude, pos.latitude), zoom: 14);
      }
      _locationService.startTracking(onPosition: (position) {
        if (!mounted) return;
        final newPos = Position(position.longitude, position.latitude);
        if (_userPos == null ||
            AlarmService.distanceMeters(
                _userPos!.lat.toDouble(), _userPos!.lng.toDouble(),
                position.latitude, position.longitude) > 5) {
          setState(() => _userPos = newPos);
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
        final isInside = AlarmService.isWithinRadius(
          userLat: userLat, userLng: userLng,
          pointLat: point.latitude, pointLng: point.longitude,
          radiusMeters: point.radiusMeters,
        );
        shouldTrigger = point.zoneTrigger == ZoneTrigger.onEntry ? isInside : !isInside;
      }
      if (shouldTrigger) {
        alarmProv.toggleActive(point.id);
        final title = point.name ?? tr('no_name');
        final zoneText = point.zoneTrigger == ZoneTrigger.onEntry ? 'Belépés' : 'Kilépés';
        NotificationService.showAlarmNotification(
          title: 'GPS Alarm: $title',
          body: '$zoneText — ${point.radiusMeters.round()}m',
          id: point.id.hashCode,
        );
        if (mounted) {
          showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
            icon: const Icon(Icons.alarm, color: Colors.red, size: 48),
            title: Text(title),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('dismiss')))],
          ));
        }
      }
    }
  }

  @override
  void dispose() {
    _locationService.dispose();
    super.dispose();
  }

  void _onMapCreated(MapController controller) {
    _controller = controller;
    DebugConsole.log('VECTOR: MapController created');
    DebugConsole.log('VECTOR: controller type = ${controller.runtimeType}');
  }

  void _onTap(Position position) {
    DebugConsole.log('VECTOR TAP: lat=${position.lat}, lng=${position.lng}, fastAssign=$_isFastAssigning');
    if (_isFastAssigning) return;
    final lat = position.lat.toDouble();
    final lng = position.lng.toDouble();
    final alarmProv = context.read<AlarmProvider>();
    final existing = alarmProv.findNearby(lat, lng);
    if (existing != null) {
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => RadiusPopup(
          latitude: existing.latitude, longitude: existing.longitude, existingPoint: existing),
      );
    } else {
      setState(() => _pendingTapPoint = position);
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => RadiusPopup(latitude: lat, longitude: lng),
      ).whenComplete(() {
        if (mounted) setState(() => _pendingTapPoint = null);
      });
    }
  }

  void _onLongPress(Position position) {
    DebugConsole.log('VECTOR LONG PRESS: lat=${position.lat}, lng=${position.lng}');
    final haptic = context.read<SettingsProvider>().settings.hapticFeedback;
    if (haptic) Vibration.vibrate(duration: 30);
    setState(() {
      _isFastAssigning = true;
      _fastAssignLat = position.lat.toDouble();
      _fastAssignLng = position.lng.toDouble();
      _fastAssignRadiusMeters = 500;
    });
  }

  void _cancelFastAssign() => setState(() => _isFastAssigning = false);

  void _confirmFastAssign() {
    final alarmProv = context.read<AlarmProvider>();
    if (alarmProv.canAddAlarm) {
      alarmProv.addAlarmPoint(AlarmPoint(
        id: const Uuid().v4(),
        latitude: _fastAssignLat,
        longitude: _fastAssignLng,
        radiusMeters: _fastAssignRadiusMeters,
        triggerType: TriggerType.distance,
      ));
    }
    _cancelFastAssign();
  }

  // Build marker points list for the MarkerLayer
  List<Point> _buildMarkerPoints(AlarmProvider alarmProv) {
    final points = <Point>[];

    // Alarm points
    for (final p in alarmProv.alarmPoints) {
      points.add(Point(coordinates: Position(p.longitude, p.latitude)));
    }

    // Pending tap point
    if (_pendingTapPoint != null) {
      points.add(Point(coordinates: _pendingTapPoint!));
    }

    // Fast assign point
    if (_isFastAssigning) {
      points.add(Point(coordinates: Position(_fastAssignLng, _fastAssignLat)));
    }

    return points;
  }


  @override
  Widget build(BuildContext context) {
    final styleUrl = context.select<SettingsProvider, String>(
        (p) => _styleUrls[p.settings.vectorStyleUrl] ?? _styleUrls['liberty']!);
    final alarmProv = context.watch<AlarmProvider>();

    final markerPoints = _buildMarkerPoints(alarmProv);
    DebugConsole.log('VECTOR build: ${markerPoints.length} markers, style=$styleUrl');
    final userPoints = _userPos != null
        ? [Point(coordinates: _userPos!)]
        : <Point>[];

    return Stack(
      children: [
        MapLibreMap(
          key: ValueKey(styleUrl),
          options: MapOptions(
            initStyle: styleUrl,
            initCenter: Position(19.0402, 47.4979),
            initZoom: 13,
          ),
          onMapCreated: _onMapCreated,
          onEvent: (event) {
            if (event is MapEventClick) {
              _onTap(event.point);
            } else if (event is MapEventLongClick) {
              _onLongPress(event.point);
            } else if (event is MapEventCameraIdle) {
              _currentZoom = _controller?.camera?.zoom ?? _currentZoom;
            }
          },
          layers: [
            // Alarm pins as red circles
            if (markerPoints.isNotEmpty)
              CircleLayer(
                points: markerPoints,
                color: const Color(0xFFFF0000),
                radius: 10,
                strokeColor: const Color(0xFFFFFFFF),
                strokeWidth: 3,
              ),
            // User position as blue dot
            if (userPoints.isNotEmpty)
              CircleLayer(
                points: userPoints,
                color: const Color(0xFF2196F3),
                radius: 8,
                strokeColor: const Color(0xFFFFFFFF),
                strokeWidth: 3,
              ),
          ],
        ),
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
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.terminal, color: Color(0xFF2ECDC4), size: 18),
            ),
          ),
        ),
        if (!_isFastAssigning)
          Selector<MapProvider, bool>(
            selector: (_, p) => p.searchActive,
            builder: (_, searchActive, __) => MapControls(
              onMenuTap: () => widget.scaffoldKey.currentState?.openDrawer(),
              onZoomIn: () => _controller?.moveCamera(zoom: _currentZoom + 1),
              onZoomOut: () => _controller?.moveCamera(zoom: _currentZoom - 1),
              onSearchTap: () => context.read<MapProvider>().toggleSearch(),
              searchActive: searchActive,
              onMyLocation: () async {
                final pos = await _locationService.getCurrentPosition();
                if (pos != null) {
                  _controller?.moveCamera(
                    center: Position(pos.longitude, pos.latitude), zoom: 15);
                }
              },
            ),
          ),
        if (!_isFastAssigning)
          Selector<MapProvider, bool>(
            selector: (_, p) => p.searchActive,
            builder: (_, searchActive, __) => searchActive
                ? SearchPill(
                    onResultSelected: (result) {
                      context.read<MapProvider>().goToSearchResult(result);
                      _controller?.moveCamera(
                        center: Position(result.longitude, result.latitude), zoom: 14);
                    },
                  )
                : const SizedBox.shrink(),
          ),
        if (_isFastAssigning)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1a1a2e) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 28),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Fast Assign', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  Text('${_fastAssignRadiusMeters.round()}m',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red[700])),
                ]),
                const SizedBox(height: 12),
                Slider(value: _fastAssignRadiusMeters, min: 100, max: 5000, divisions: 49, activeColor: Colors.red,
                  onChanged: (v) => setState(() => _fastAssignRadiusMeters = v)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: _cancelFastAssign, child: Text(tr('cancel')))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: _confirmFastAssign, child: Text(tr('save')))),
                ]),
              ]),
            ),
          ),
      ],
    );
  }
}
