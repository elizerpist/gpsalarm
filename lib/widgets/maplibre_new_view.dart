import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
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
import '../widgets/alarm_card.dart';
import '../widgets/offline_indicator.dart';
import '../services/location_service.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import '../services/debug_console.dart';
import '../widgets/scale_bar.dart';

class MaplibreNewView extends StatefulWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  const MaplibreNewView({super.key, required this.scaffoldKey});

  @override
  State<MaplibreNewView> createState() => _MaplibreNewViewState();
}

class _MaplibreNewViewState extends State<MaplibreNewView> {
  MapController? _controller;
  bool _imagesRegistered = false;
  bool _radiusLayerReady = false;
  final LocationService _locationService = LocationService();
  // Unified assign state
  bool _isAssigning = false;
  AlarmPoint? _assignExisting;
  double _assignLat = 0;
  double _assignLng = 0;
  double _assignRadius = 500;
  TriggerType _assignTriggerType = TriggerType.distance;
  ZoneTrigger _assignZoneTrigger = ZoneTrigger.onEntry;
  int _assignTimeMinutes = 10;
  Offset? _assignScreenCenter;
  bool _isDraggingRadius = false;
  int? _dragPointerId;
  double _currentZoom = 13;
  double _speedKmh = 0;
  Position? _userPos;
  // Overlay radius notifier — drives CustomPainter repaint without setState
  final ValueNotifier<double> _radiusNotifier = ValueNotifier(500);
  // Speed interpolation
  double _prevGpsSpeed = 0;
  double _currentGpsSpeed = 0;
  DateTime _prevGpsTime = DateTime.now();
  DateTime _currentGpsTime = DateTime.now();
  Timer? _speedInterpolTimer;

  static const _styleUrls = {
    'liberty': 'https://tiles.openfreemap.org/styles/liberty',
    'bright': 'https://tiles.openfreemap.org/styles/bright',
    'positron': 'https://tiles.openfreemap.org/styles/positron',
  };

  @override
  void initState() {
    super.initState();
    _initLocation();
    _startSpeedInterpolation();
  }

  /// 60fps speed interpolation between GPS ticks.
  void _startSpeedInterpolation() {
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
      if ((estimated - _speedKmh).abs() > 0.05) {
        _speedKmh = estimated;
        // Update overlay radius if time-based trigger is active
        if (_isAssigning && _assignTriggerType == TriggerType.time) {
          _radiusNotifier.value = _currentRadiusPx;
        }
      }
    });
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
        // Feed speed interpolation
        final newSpeed = _locationService.averageSpeedKmh;
        _prevGpsSpeed = _currentGpsSpeed;
        _prevGpsTime = _currentGpsTime;
        _currentGpsSpeed = newSpeed;
        _currentGpsTime = DateTime.now();
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
    _radiusDebounce?.cancel();
    _fastCircleDebounce?.cancel();
    _speedInterpolTimer?.cancel();
    _radiusNotifier.dispose();
    _locationService.dispose();
    super.dispose();
  }

  void _onMapCreated(MapController controller) {
    _controller = controller;
    DebugConsole.log('VECTOR: MapController created');
    DebugConsole.log('VECTOR: controller type = ${controller.runtimeType}');
  }

  Future<void> _registerImages(StyleController style) async {
    if (_imagesRegistered) return;
    try {
      final redPin = await _renderIconToPng(Icons.location_on, const Color(0xFFFF0000), 160);
      final greyPin = await _renderIconToPng(Icons.location_on, const Color(0xFF9E9E9E), 160);
      await style.addImage('pin-red', redPin);
      await style.addImage('pin-grey', greyPin);
      await _initRadiusLayer(style);
      _imagesRegistered = true;
      if (mounted) setState(() {});
      DebugConsole.log('VECTOR: images + radius layer registered');
    } catch (e) {
      DebugConsole.log('VECTOR: init error: $e');
    }
  }

  /// Radius circle version tracker for stale async rebuild detection.
  int _radiusLayerVersion = 0;
  Timer? _radiusDebounce;
  Timer? _fastCircleDebounce;
  int _fastCircleVersion = 0;
  bool _fastCircleUpdating = false; // guard against concurrent async updates
  int _dragLogCounter = 0;

  static const _emptyGeoJson = '{"type":"FeatureCollection","features":[]}';

  Future<void> _initRadiusLayer(StyleController style) async {
    // Inverted veil source for onLeave triggers
    await style.addSource(GeoJsonSource(id: 'veil-src', data: _emptyGeoJson));
    await style.addLayer(FillStyleLayer(
      id: 'veil-fill',
      sourceId: 'veil-src',
      paint: { 'fill-color': '#FF0000', 'fill-opacity': 0.15 },
    ));
    // Persistent source for fast assign circle (updated via updateGeoJsonSource)
    await style.addSource(GeoJsonSource(id: 'fast-src', data: _emptyGeoJson));
    _radiusLayerReady = true;
    DebugConsole.log('VECTOR: radius layer system ready');
  }

  /// Recreate fast assign CircleStyleLayer with current radius.
  /// Only ONE layer to remove+add — much faster than rebuilding all alarms.
  Future<void> _updateFastCircleLayer(StyleController style) async {
    if (_fastCircleUpdating) return; // skip if previous update still in flight
    _fastCircleUpdating = true;
    try { await style.removeLayer('fast-circle'); } catch (_) {}

    // Update point source position
    style.updateGeoJsonSource(
      id: 'fast-src',
      data: _pointGeoJson(_assignLng, _assignLat),
    );

    final isTime = _assignTriggerType == TriggerType.time;
    double radius = _assignRadius;
    if (isTime) {
      radius = math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60);
    }
    final basePx = radius / (156543.03392 * math.cos(_assignLat * math.pi / 180));
    final fillColor = isTime ? 'rgba(255,152,0,0.10)' : 'rgba(255,0,0,0.12)';
    final strokeColor = isTime ? 'rgba(255,152,0,0.7)' : 'rgba(255,0,0,0.6)';

    await style.addLayer(CircleStyleLayer(
      id: 'fast-circle',
      sourceId: 'fast-src',
      paint: {
        'circle-radius': [
          'interpolate', ['exponential', 2.0], ['zoom'],
          0.0, basePx,
          22.0, basePx * 4194304.0,
        ],
        'circle-color': fillColor,
        'circle-stroke-color': strokeColor,
        'circle-stroke-width': 2.0,
      },
    ));
    _fastCircleUpdating = false;
  }

  /// Sync radius circles.
  /// Fast assign + pending: dedicated CircleStyleLayer, debounced per-frame.
  /// Alarm circles: debounced rebuild, SKIPPED during drag (they don't change).
  void _syncRadiusSource(AlarmProvider alarmProv) {
    if (!_radiusLayerReady) return;
    final style = _controller?.style;
    if (style == null) return;

    // --- Fast assign circle ---
    // onLeave: skip CircleStyleLayer — the veil hole IS the visual boundary
    // During drag: skip native layer update — Flutter overlay circle provides instant feedback
    // --- Fast assign circle: Flutter overlay handles the visual during assign.
    // Native CircleStyleLayer is NOT used during assign (causes double circle
    // because overlay is at fixed screen position, native layer is geo-referenced).
    // Clean up any leftover native layer when assigning.
    _fastCircleDebounce?.cancel();
    if (_fastCircleVersion > 0) {
      _fastCircleVersion = 0;
      _fastCircleUpdating = false;
      try { style.removeLayer('fast-circle'); } catch (_) {}
      style.updateGeoJsonSource(id: 'fast-src', data: _emptyGeoJson);
    }

    // --- Veil (onLeave overlay) — instant updateGeoJsonSource ---
    _updateVeil(style, alarmProv);

    // --- Alarm circles: skip rebuild during drag (alarm data doesn't change) ---
    if (_isDraggingRadius) return;

    _radiusLayerVersion++;
    final v = _radiusLayerVersion;
    final alarmCircles = <({String id, double lng, double lat, double radiusMeters, bool active, bool isTime, bool isLeave})>[];
    for (int i = 0; i < alarmProv.alarmPoints.length; i++) {
      final p = alarmProv.alarmPoints[i];
      double radius = p.radiusMeters;
      final isTime = p.triggerType == TriggerType.time;
      if (isTime && p.timeTrigger != null) {
        radius = math.max(200.0, (_speedKmh / 3.6) * p.timeTrigger!.inSeconds.toDouble());
      }
      alarmCircles.add((id: 'alarm-$i', lng: p.longitude, lat: p.latitude, radiusMeters: radius, active: p.isActive, isTime: isTime, isLeave: p.zoneTrigger == ZoneTrigger.onLeave));
    }
    _radiusDebounce?.cancel();
    _radiusDebounce = Timer(const Duration(milliseconds: 50), () {
      if (v == _radiusLayerVersion) {
        _rebuildRadiusLayers(style, alarmCircles, v);
      }
    });
  }

  String _pointGeoJson(double lng, double lat) {
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [{
        'type': 'Feature',
        'geometry': {'type': 'Point', 'coordinates': [lng, lat]},
        'properties': {},
      }],
    });
  }

  void _updateVeil(StyleController style, AlarmProvider alarmProv) {
    final leaveAlarms = alarmProv.alarmPoints
        .where((p) => p.zoneTrigger == ZoneTrigger.onLeave)
        .toList();
    final hasFastLeave = _isAssigning && _assignZoneTrigger == ZoneTrigger.onLeave;

    if (leaveAlarms.isEmpty && !hasFastLeave) {
      style.updateGeoJsonSource(id: 'veil-src', data: '{"type":"FeatureCollection","features":[]}');
      return;
    }

    // World polygon with holes for each onLeave circle
    final holes = <List<List<double>>>[];
    for (final p in leaveAlarms) {
      double r = p.radiusMeters;
      if (p.triggerType == TriggerType.time && p.timeTrigger != null) {
        r = math.max(200.0, (_speedKmh / 3.6) * p.timeTrigger!.inSeconds.toDouble());
      }
      holes.add(_geoCircle(p.longitude, p.latitude, r));
    }
    if (hasFastLeave) {
      final r = _assignTriggerType == TriggerType.time
          ? math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60)
          : _assignRadius;
      holes.add(_geoCircle(_assignLng, _assignLat, r));
    }

    final coords = <List<List<double>>>[
      [[-180, -85], [180, -85], [180, 85], [-180, 85], [-180, -85]],
      ...holes,
    ];

    style.updateGeoJsonSource(
      id: 'veil-src',
      data: jsonEncode({
        'type': 'FeatureCollection',
        'features': [{
          'type': 'Feature',
          'geometry': {'type': 'Polygon', 'coordinates': coords},
          'properties': {},
        }],
      }),
    );
  }

  /// Rebuild ONLY alarm circle layers using per-alarm CircleStyleLayer with
  /// literal interpolate expression (the ONLY approach that produces perfect
  /// geometric circles — see docs/vector-map-radius-circles.md).
  /// onLeave alarms are SKIPPED — the veil hole provides their visual boundary.
  Future<void> _rebuildRadiusLayers(StyleController style, List<({String id, double lng, double lat, double radiusMeters, bool active, bool isTime, bool isLeave})> circles, int version) async {
    // Remove old alarm layers and sources
    for (int i = 0; i < 20; i++) {
      final id = 'alarm-$i';
      try { await style.removeLayer('radius-circle-$id'); } catch (_) {}
      try { await style.removeSource('radius-pt-$id'); } catch (_) {}
    }

    if (version != _radiusLayerVersion) return;

    for (final c in circles) {
      if (version != _radiusLayerVersion) return;
      // onLeave alarms: the veil hole provides the visual — skip CircleStyleLayer
      // to avoid double circle (veil polygon vs CircleStyleLayer mismatch)
      if (c.isLeave) continue;

      final basePx = c.radiusMeters / (156543.03392 * math.cos(c.lat * math.pi / 180));
      final String fillColor = c.isTime
          ? (c.active ? 'rgba(255,152,0,0.10)' : 'rgba(158,158,158,0.05)')
          : (c.active ? 'rgba(255,0,0,0.12)' : 'rgba(158,158,158,0.05)');
      final String strokeColor = c.isTime
          ? (c.active ? 'rgba(255,152,0,0.7)' : 'rgba(158,158,158,0.3)')
          : (c.active ? 'rgba(255,0,0,0.6)' : 'rgba(158,158,158,0.3)');
      final strokeWidth = c.active ? 2.0 : 1.0;

      try {
        await style.addSource(GeoJsonSource(
          id: 'radius-pt-${c.id}',
          data: _pointGeoJson(c.lng, c.lat),
        ));
        await style.addLayer(CircleStyleLayer(
          id: 'radius-circle-${c.id}',
          sourceId: 'radius-pt-${c.id}',
          paint: {
            'circle-radius': [
              'interpolate', ['exponential', 2.0], ['zoom'],
              0.0, basePx,
              22.0, basePx * 4194304.0,
            ],
            'circle-color': fillColor,
            'circle-stroke-color': strokeColor,
            'circle-stroke-width': strokeWidth,
          },
        ));
      } catch (e) {
        DebugConsole.log('VECTOR: radius layer error for ${c.id}: $e');
      }
    }
  }

  /// Render a Material icon to PNG bytes using PictureRecorder.
  static Future<Uint8List> _renderIconToPng(IconData icon, Color color, int size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size.toDouble(),
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Find closest alarm within the pin's visual tap area (zoom-dependent).
  AlarmPoint? _findTappedAlarm(double tapLat, double tapLng, AlarmProvider alarmProv) {
    // Pin is ~64px tall (160 icon * 0.4 scale), anchor at bottom.
    // Allow tapping within 40px of the anchor point.
    final metersPerPx = 156543.03392 * math.cos(tapLat * math.pi / 180) / math.pow(2, _currentZoom);
    final thresholdMeters = math.max(50.0, 40 * metersPerPx);
    AlarmPoint? closest;
    double closestDist = double.infinity;
    for (final p in alarmProv.alarmPoints) {
      final dist = AlarmService.distanceMeters(tapLat, tapLng, p.latitude, p.longitude);
      if (dist < thresholdMeters && dist < closestDist) {
        closest = p;
        closestDist = dist;
      }
    }
    return closest;
  }

  void _onTap(Position position) {
    if (_isAssigning) return;
    final lat = position.lat.toDouble();
    final lng = position.lng.toDouble();
    final alarmProv = context.read<AlarmProvider>();
    final existing = _findTappedAlarm(lat, lng, alarmProv);
    _startAssign(lat, lng, existing: existing);
  }

  void _startAssign(double lat, double lng, {AlarmPoint? existing}) {
    Offset? screenCenter;
    final cam = _controller?.camera;
    if (cam != null) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        final size = box.size;
        final camLat = cam.center?.lat.toDouble() ?? 47.5;
        final camLng = cam.center?.lng.toDouble() ?? 19.0;
        final zoom = cam.zoom ?? _currentZoom;
        final metersPerPx = 156543.03392 * math.cos(camLat * math.pi / 180) / math.pow(2, zoom);
        final dLng = (lng - camLng);
        final dLat = (lat - camLat);
        final dx = dLng * math.cos(camLat * math.pi / 180) * (111320.0 / metersPerPx);
        final dy = -dLat * (110540.0 / metersPerPx);
        screenCenter = Offset(size.width / 2 + dx, size.height / 2 + dy);
      }
    }
    setState(() {
      _isAssigning = true;
      _assignExisting = existing;
      _assignLat = lat;
      _assignLng = lng;
      _assignRadius = existing?.radiusMeters ?? 500;
      _assignTriggerType = existing?.triggerType ?? TriggerType.distance;
      _assignZoneTrigger = existing?.zoneTrigger ?? ZoneTrigger.onEntry;
      _assignTimeMinutes = existing?.timeTrigger?.inMinutes ?? 10;
      _assignScreenCenter = screenCenter;
    });
    // Initialize overlay radius
    _radiusNotifier.value = _currentRadiusPx;
  }

  void _onLongPress(Position position) {
    final haptic = context.read<SettingsProvider>().settings.hapticFeedback;
    if (haptic) Vibration.vibrate(duration: 30);
    _startAssign(position.lat.toDouble(), position.lng.toDouble());
    _isDraggingRadius = true; // Allow immediate swipe without lifting finger
  }

  void _cancelAssign() {
    _controller?.style?.updateGeoJsonSource(id: 'fast-src', data: _emptyGeoJson);
    setState(() {
      _isAssigning = false;
      _assignExisting = null;
      _assignScreenCenter = null;
      _isDraggingRadius = false;
      _dragPointerId = null;
      _assignTriggerType = TriggerType.distance;
      _assignZoneTrigger = ZoneTrigger.onEntry;
      _assignTimeMinutes = 10;
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


  /// Current fast assign radius in screen pixels (for overlay painter).
  double get _currentRadiusPx {
    final isTime = _assignTriggerType == TriggerType.time;
    double radius = _assignRadius;
    if (isTime) {
      radius = math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60);
    }
    final metersPerPx = 156543.03392 * math.cos(_assignLat * math.pi / 180) / math.pow(2, _currentZoom);
    return radius / metersPerPx;
  }

  // Build separate marker point lists for active (red) and inactive (grey) pins
  ({List<Point> active, List<Point> inactive}) _buildMarkerPoints(AlarmProvider alarmProv) {
    final active = <Point>[];
    final inactive = <Point>[];

    for (final p in alarmProv.alarmPoints) {
      final point = Point(coordinates: Position(p.longitude, p.latitude));
      if (p.isActive) {
        active.add(point);
      } else {
        inactive.add(point);
      }
    }

    // Assign point (new or editing) — always red
    if (_isAssigning) {
      active.add(Point(coordinates: Position(_assignLng, _assignLat)));
    }

    return (active: active, inactive: inactive);
  }


  @override
  Widget build(BuildContext context) {
    final styleUrl = context.select<SettingsProvider, String>(
        (p) => _styleUrls[p.settings.vectorStyleUrl] ?? _styleUrls['liberty']!);
    final alarmProv = context.watch<AlarmProvider>();

    final markers = _buildMarkerPoints(alarmProv);
    _syncRadiusSource(alarmProv);

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
          onStyleLoaded: (style) => _registerImages(style),
          onEvent: (event) {
            if (event is MapEventClick) {
              _onTap(event.point);
            } else if (event is MapEventLongClick) {
              _onLongPress(event.point);
            } else if (event is MapEventMoveCamera || event is MapEventCameraIdle) {
              final newZoom = _controller?.camera?.zoom ?? _currentZoom;
              if ((newZoom - _currentZoom).abs() > 0.05) {
                setState(() => _currentZoom = newZoom);
              }
            }
          },
          layers: [
            // Pin markers
            if (_imagesRegistered && markers.active.isNotEmpty)
              MarkerLayer(
                points: markers.active,
                iconImage: 'pin-red',
                iconSize: 0.4,
                iconAnchor: IconAnchor.bottom,
                iconAllowOverlap: true,
              ),
            if (_imagesRegistered && markers.inactive.isNotEmpty)
              MarkerLayer(
                points: markers.inactive,
                iconImage: 'pin-grey',
                iconSize: 0.35,
                iconAnchor: IconAnchor.bottom,
                iconAllowOverlap: true,
              ),
            // User position — blue dot with white border + glow
            if (_userPos != null) ...[
              CircleLayer(
                points: [Point(coordinates: _userPos!)],
                radius: 16,
                color: const Color(0x262196F3),
                strokeColor: const Color(0x00000000),
                strokeWidth: 0,
              ),
              CircleLayer(
                points: [Point(coordinates: _userPos!)],
                radius: 8,
                color: const Color(0xFF2196F3),
                strokeColor: const Color(0xFFFFFFFF),
                strokeWidth: 3,
              ),
            ],
          ],
        ),
        const OfflineIndicator(),
        // Scale bar — bottom left
        Positioned(
          bottom: 24,
          left: 12,
          child: ScaleBar(
            zoom: _currentZoom,
            latitude: _userPos?.lat.toDouble() ?? 47.5,
            speedKmh: _speedKmh,
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
              width: 36, height: 36,
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
              widget.scaffoldKey.currentState?.openDrawer();
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
        if (!_isAssigning)
          Selector<MapProvider, bool>(
            selector: (_, p) => p.searchActive,
            builder: (_, searchActive, __) => searchActive
                ? SearchPill(
                    onResultSelected: (result) {
                      context.read<MapProvider>().goToSearchResult(result);
                      _controller?.moveCamera(
                        center: Position(result.longitude, result.latitude), zoom: 14);
                    },
                    onClose: () => context.read<MapProvider>().toggleSearch(),
                  )
                : const SizedBox.shrink(),
          ),
        // Radius drag overlay — blocks map gestures, 60fps via ValueNotifier
        if (_isAssigning && _assignScreenCenter != null)
          Positioned.fill(
            child: RepaintBoundary(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  if (_assignScreenCenter == null) return;
                  _dragPointerId = e.pointer;
                  _isDraggingRadius = true;
                  _dragLogCounter = 0;
                },
                onPointerMove: (e) {
                  if (!_isDraggingRadius || _assignScreenCenter == null) return;
                  if (e.pointer != _dragPointerId) return;
                  final dist = (e.localPosition - _assignScreenCenter!).distance;
                  if (_assignTriggerType == TriggerType.distance) {
                    final metersPerPx = 156543.03392 * math.cos(_assignLat * math.pi / 180) / math.pow(2, _currentZoom);
                    _assignRadius = (dist * metersPerPx).clamp(100.0, 5000.0);
                  } else {
                    _assignTimeMinutes = (dist * 0.3).clamp(5.0, 120.0).round();
                  }
                  // Update overlay circle instantly (no widget rebuild)
                  _radiusNotifier.value = _currentRadiusPx;
                  // Sync slider in AlarmCard (setState only rebuilds card, not overlay)
                  setState(() {});
                },
                onPointerUp: (e) {
                  if (e.pointer != _dragPointerId) return;
                  _isDraggingRadius = false;
                  _dragPointerId = null;
                },
                child: CustomPaint(
                  painter: _assignScreenCenter != null && _assignZoneTrigger != ZoneTrigger.onLeave
                      ? _RadiusOverlayPainter(
                          center: _assignScreenCenter!,
                          radiusNotifier: _radiusNotifier,
                          isTime: _assignTriggerType == TriggerType.time,
                        )
                      : null,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        // Alarm card — unified assign/edit (same widget as raster map)
        if (_isAssigning)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: AlarmCard(
              latitude: _assignLat,
              longitude: _assignLng,
              existingPoint: _assignExisting,
              radius: _assignRadius,
              onRadiusChanged: (v) {
                setState(() => _assignRadius = v);
                _radiusNotifier.value = _currentRadiusPx;
              },
              onZoneTriggerChanged: (v) => setState(() => _assignZoneTrigger = v),
              onTriggerTypeChanged: (v) => setState(() => _assignTriggerType = v),
              onTimeChanged: (v) {
                setState(() => _assignTimeMinutes = v);
                _radiusNotifier.value = _currentRadiusPx;
              },
              onSave: _saveAssign,
              onCancel: _cancelAssign,
              onDelete: _assignExisting != null ? () {
                context.read<AlarmProvider>().removeAlarmPoint(_assignExisting!.id);
                _cancelAssign();
              } : null,
            ),
          ),
      ],
    );
  }

  /// 64-point polygon circle for veil hole geometry.
  static List<List<double>> _geoCircle(double lng, double lat, double radiusMeters) {
    const segments = 64;
    final coords = <List<double>>[];
    final angDist = radiusMeters / 6371000.0;
    final latR = lat * math.pi / 180;
    final lngR = lng * math.pi / 180;
    final sinLat = math.sin(latR);
    final cosLat = math.cos(latR);
    final sinAng = math.sin(angDist);
    final cosAng = math.cos(angDist);
    for (int i = 0; i <= segments; i++) {
      final bearing = 2 * math.pi * i / segments;
      final pLat = math.asin(sinLat * cosAng + cosLat * sinAng * math.cos(bearing));
      final pLng = lngR + math.atan2(
        math.sin(bearing) * sinAng * cosLat,
        cosAng - sinLat * math.sin(pLat),
      );
      coords.add([pLng * 180 / math.pi, pLat * 180 / math.pi]);
    }
    return coords;
  }
}

/// Flutter-side circle painter driven by ValueNotifier for 60fps updates
/// without widget rebuilds. Dashed border for time-based triggers.
class _RadiusOverlayPainter extends CustomPainter {
  final Offset center;
  final ValueNotifier<double> radiusNotifier;
  final bool isTime;

  _RadiusOverlayPainter({
    required this.center,
    required this.radiusNotifier,
    required this.isTime,
  }) : super(repaint: radiusNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    final radiusPx = radiusNotifier.value;
    final fillColor = isTime
        ? const Color(0x1AFF9800)
        : const Color(0x1FFF0000);
    final strokeColor = isTime
        ? const Color(0xB3FF9800)
        : const Color(0x99FF0000);

    // Fill
    canvas.drawCircle(center, radiusPx, Paint()..color = fillColor);

    // Stroke — dashed for time, solid for distance
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (isTime) {
      final path = Path()..addOval(Rect.fromCircle(center: center, radius: radiusPx));
      final dashed = dashPath(path, dashArray: CircularIntervalList<double>([8.0, 4.0]));
      canvas.drawPath(dashed, strokePaint);
    } else {
      canvas.drawCircle(center, radiusPx, strokePaint);
    }
  }

  @override
  bool shouldRepaint(_RadiusOverlayPainter oldDelegate) => true;
}

