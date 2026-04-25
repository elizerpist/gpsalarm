import 'dart:async';
import 'dart:math' show cos, pi, pow, sqrt;
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
import '../widgets/radius_popup.dart';
import '../widgets/offline_indicator.dart';
import '../services/location_service.dart';
import '../services/alarm_service.dart';
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
  Position? _userPosition;
  bool _isFastAssigning = false;
  Position? _fastAssignCenter;
  double _fastAssignRadiusMeters = 500;

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
        _userPosition = Position(pos.longitude, pos.latitude);
        _controller?.flyTo(
          center: _userPosition!,
          zoom: 14,
        );
      }
      _locationService.startTracking(onPosition: (position) {
        if (!mounted) return;
        _userPosition = Position(position.longitude, position.latitude);
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
      }
      if (shouldTrigger) {
        alarmProv.toggleActive(point.id);
        if (mounted) {
          showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
            icon: const Icon(Icons.alarm, color: Colors.red, size: 48),
            title: Text(point.name ?? tr('no_name')),
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
    DebugConsole.log('MapLibre (new) map created');
    if (_userPosition != null) {
      controller.flyTo(center: _userPosition!, zoom: 14);
    }
  }

  void _onTap(Position position) {
    if (_isFastAssigning) return;
    final alarmProv = context.read<AlarmProvider>();
    final existing = alarmProv.findNearby(position.lat.toDouble(), position.lng.toDouble());
    if (existing != null) {
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => RadiusPopup(
          latitude: existing.latitude, longitude: existing.longitude, existingPoint: existing,
        ),
      );
    } else {
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => RadiusPopup(latitude: position.lat.toDouble(), longitude: position.lng.toDouble()),
      );
    }
  }

  void _onLongPress(Position position) {
    final haptic = context.read<SettingsProvider>().settings.hapticFeedback;
    if (haptic) Vibration.vibrate(duration: 30);
    setState(() {
      _isFastAssigning = true;
      _fastAssignCenter = position;
      _fastAssignRadiusMeters = 500;
    });
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
        latitude: _fastAssignCenter!.lat.toDouble(),
        longitude: _fastAssignCenter!.lng.toDouble(),
        radiusMeters: _fastAssignRadiusMeters,
        triggerType: TriggerType.distance,
      ));
    }
    _cancelFastAssign();
  }

  String _getStyleUrl() {
    final key = context.read<SettingsProvider>().settings.vectorStyleUrl;
    return _styleUrls[key] ?? _styleUrls['liberty']!;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MapLibreMap(
          options: MapOptions(
            style: StyleString(string: _getStyleUrl()),
            center: const Position(19.0402, 47.4979),
            zoom: 13,
          ),
          onMapCreated: _onMapCreated,
          onEvent: (event) {
            if (event is MapEventClick) {
              _onTap(event.point);
            } else if (event is MapEventLongClick) {
              _onLongPress(event.point);
            }
          },
        ),
        const OfflineIndicator(),
        if (!_isFastAssigning)
          MapControls(
            onMenuTap: () => widget.scaffoldKey.currentState?.openDrawer(),
            onZoomIn: () => _controller?.flyTo(zoom: (_controller?.camera.zoom ?? 13) + 1),
            onZoomOut: () => _controller?.flyTo(zoom: (_controller?.camera.zoom ?? 13) - 1),
            onSearchTap: () => context.read<MapProvider>().toggleSearch(),
            onMyLocation: () {
              if (_userPosition != null) {
                _controller?.flyTo(center: _userPosition!, zoom: 15);
              }
            },
            searchActive: false,
          ),
        if (_isFastAssigning)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1a1a2e) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Icon(Icons.location_on, color: Colors.orange, size: 28),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Fast Assign',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  Text('${_fastAssignRadiusMeters.round()}m',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange[700])),
                ]),
                const SizedBox(height: 12),
                Slider(value: _fastAssignRadiusMeters, min: 100, max: 5000,
                  divisions: 49, activeColor: Colors.orange,
                  onChanged: (v) => setState(() => _fastAssignRadiusMeters = v)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: _cancelFastAssign, child: Text(tr('cancel')))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: _confirmFastAssign,
                    style: FilledButton.styleFrom(backgroundColor: Colors.orange), child: Text(tr('save')))),
                ]),
              ]),
            ),
          ),
      ],
    );
  }
}
