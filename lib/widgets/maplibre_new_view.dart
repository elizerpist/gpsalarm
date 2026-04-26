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
import '../widgets/radius_popup.dart';
import '../widgets/search_pill.dart';
import '../widgets/offline_indicator.dart';
import '../services/geocoding_service.dart';
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
  bool _isFastAssigning = false;
  double _fastAssignLat = 0;
  double _fastAssignLng = 0;
  double _fastAssignRadiusMeters = 500;
  double _currentZoom = 13;
  LatLng? _pendingTapPoint;

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
        _controller?.moveCamera(
          center: Position(pos.longitude, pos.latitude),
          zoom: 14,
        );
      }
      _locationService.startTracking(onPosition: (position) {
        if (!mounted) return;
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
  }

  void _onTap(Position position) {
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
      setState(() => _pendingTapPoint = LatLng(lat, lng));
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => RadiusPopup(latitude: lat, longitude: lng),
      ).whenComplete(() {
        if (mounted) setState(() => _pendingTapPoint = null);
      });
    }
  }

  void _onLongPress(Position position) {
    final haptic = context.read<SettingsProvider>().settings.hapticFeedback;
    if (haptic) Vibration.vibrate(duration: 30);
    setState(() {
      _isFastAssigning = true;
      _fastAssignLat = position.lat.toDouble();
      _fastAssignLng = position.lng.toDouble();
      _fastAssignRadiusMeters = 500;
    });
  }

  void _cancelFastAssign() {
    setState(() => _isFastAssigning = false);
  }

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

  @override
  Widget build(BuildContext context) {
    final styleUrl = context.select<SettingsProvider, String>(
        (p) => _styleUrls[p.settings.vectorStyleUrl] ?? _styleUrls['liberty']!);

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
            }
          },
        ),
        // Pending tap pin overlay
        if (_pendingTapPoint != null)
          Positioned(
            top: 0, left: 0, right: 0, bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -20),
                  child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                ),
              ),
            ),
          ),
        // Fast assign pin overlay
        if (_isFastAssigning)
          Positioned(
            top: 0, left: 0, right: 0, bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -20),
                  child: const Icon(Icons.location_on, color: Colors.orange, size: 40),
                ),
              ),
            ),
          ),
        const OfflineIndicator(),
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
                  center: Position(pos.longitude, pos.latitude),
                  zoom: 15,
                );
              }
            },
          ),
          ),
        // Search pill
        if (!_isFastAssigning)
          Selector<MapProvider, bool>(
            selector: (_, p) => p.searchActive,
            builder: (_, searchActive, __) => searchActive
                ? SearchPill(
                    onResultSelected: (result) {
                      context.read<MapProvider>().goToSearchResult(result);
                      _controller?.moveCamera(
                        center: Position(result.longitude, result.latitude),
                        zoom: 14,
                      );
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
                  const Icon(Icons.location_on, color: Colors.orange, size: 28),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Fast Assign', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  Text('${_fastAssignRadiusMeters.round()}m',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange[700])),
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
              ]),
            ),
          ),
      ],
    );
  }
}

// Helper class for tap position
class LatLng {
  final double latitude;
  final double longitude;
  const LatLng(this.latitude, this.longitude);
}
