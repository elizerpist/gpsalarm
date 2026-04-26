import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
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
  _LatLng? _pendingTapPoint;
  _LatLng? _userPos;
  bool _imagesLoaded = false;

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
        setState(() => _userPos = _LatLng(pos.latitude, pos.longitude));
        _controller?.moveCamera(
          center: Position(pos.longitude, pos.latitude),
          zoom: 14,
        );
      }
      _locationService.startTracking(onPosition: (position) {
        if (!mounted) return;
        setState(() => _userPos = _LatLng(position.latitude, position.longitude));
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

  void _onStyleLoaded() async {
    if (_controller == null || _imagesLoaded) return;
    // Register marker images
    try {
      await _addMarkerImage('pin-red', Colors.red);
      await _addMarkerImage('pin-orange', Colors.orange);
      await _addMarkerImage('pin-blue', Colors.blue);
      _imagesLoaded = true;
      DebugConsole.log('Marker images loaded');
    } catch (e) {
      DebugConsole.log('Failed to load marker images: $e');
    }
  }

  Future<void> _addMarkerImage(String id, Color color) async {
    // Create a simple colored circle as marker image
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = color;
    canvas.drawCircle(const Offset(16, 16), 12, paint);
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(const Offset(16, 16), 12, borderPaint);
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 32);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      await _controller?.addImage(id, byteData.buffer.asUint8List());
    }
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
      setState(() => _pendingTapPoint = _LatLng(lat, lng));
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

  // Build GeoJSON annotation layers
  List<AnnotationLayer> _buildAnnotationLayers() {
    final alarmProv = context.watch<AlarmProvider>();
    final layers = <AnnotationLayer>[];

    // Alarm radius circles
    for (final point in alarmProv.alarmPoints) {
      layers.add(CircleAnnotation(
        point: Position(point.longitude, point.latitude),
        color: point.isActive ? Colors.red.withOpacity(0.12) : Colors.grey.withOpacity(0.05),
        radius: point.radiusMeters / 10, // approximate visual size
        strokeColor: point.isActive ? Colors.red.withOpacity(0.6) : Colors.grey.withOpacity(0.3),
        strokeWidth: point.isActive ? 2 : 1,
      ));
    }

    // Alarm markers
    for (final point in alarmProv.alarmPoints) {
      layers.add(MarkerAnnotation(
        point: Position(point.longitude, point.latitude),
        textField: point.name ?? '',
        textSize: 10,
        textOffset: const [0, 1.5],
      ));
    }

    // Pending tap pin
    if (_pendingTapPoint != null) {
      layers.add(MarkerAnnotation(
        point: Position(_pendingTapPoint!.longitude, _pendingTapPoint!.latitude),
      ));
    }

    // Fast assign pin
    if (_isFastAssigning) {
      layers.add(CircleAnnotation(
        point: Position(_fastAssignLng, _fastAssignLat),
        color: Colors.orange.withOpacity(0.15),
        radius: _fastAssignRadiusMeters / 10,
        strokeColor: Colors.orange.withOpacity(0.7),
        strokeWidth: 3,
      ));
      layers.add(MarkerAnnotation(
        point: Position(_fastAssignLng, _fastAssignLat),
      ));
    }

    // User position
    if (_userPos != null) {
      layers.add(CircleAnnotation(
        point: Position(_userPos!.longitude, _userPos!.latitude),
        color: const Color(0xFF2196F3),
        radius: 8,
        strokeColor: Colors.white,
        strokeWidth: 3,
      ));
    }

    return layers;
  }

  @override
  Widget build(BuildContext context) {
    final styleUrl = context.select<SettingsProvider, String>(
        (p) => _styleUrls[p.settings.vectorStyleUrl] ?? _styleUrls['liberty']!);
    // Watch alarm provider to rebuild annotations
    context.watch<AlarmProvider>();

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
            } else if (event is MapEventStyleLoaded) {
              _onStyleLoaded();
            } else if (event is MapEventCameraIdle) {
              _currentZoom = _controller?.camera?.zoom ?? _currentZoom;
            }
          },
          layers: _buildAnnotationLayers(),
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

class _LatLng {
  final double latitude;
  final double longitude;
  const _LatLng(this.latitude, this.longitude);
}

// Annotation layer helpers — these map to maplibre's layer system
// The maplibre ^0.2.0 package may use different class names;
// these are abstractions that will be adapted to the actual API

abstract class AnnotationLayer {}

class CircleAnnotation extends AnnotationLayer {
  final Position point;
  final Color color;
  final double radius;
  final Color strokeColor;
  final double strokeWidth;

  CircleAnnotation({
    required this.point,
    required this.color,
    required this.radius,
    this.strokeColor = Colors.transparent,
    this.strokeWidth = 0,
  });
}

class MarkerAnnotation extends AnnotationLayer {
  final Position point;
  final String? textField;
  final double? textSize;
  final List<double>? textOffset;

  MarkerAnnotation({
    required this.point,
    this.textField,
    this.textSize,
    this.textOffset,
  });
}
