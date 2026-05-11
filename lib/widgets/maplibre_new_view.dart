import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:maplibre/maplibre.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import 'package:vibration/vibration.dart';
import '../models/alarm_point.dart';
import '../models/app_settings.dart';
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
import '../widgets/alarm_marker_renderer.dart';
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
  bool _isDraggingRadius = false;
  int? _dragPointerId;
  double _currentZoom = 13;
  bool _zoomInitialized = false;
  double _deviceDpr = 1.0;
  double _speedKmh = 0;
  Position? _userPos;
  Offset? _lastPointerDownPos;
  Offset? _assignScreenCenter;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _deviceDpr = MediaQuery.devicePixelRatioOf(context);
    if (!_zoomInitialized) {
      _zoomInitialized = true;
      _currentZoom = context.read<MapProvider>().zoom;
      DebugConsole.log('VECTOR_INIT: zoom from MapProvider=${_currentZoom.toStringAsFixed(2)} center=${context.read<MapProvider>().center} dpr=$_deviceDpr');
    }
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
      } else if (point.triggerType == TriggerType.time && point.timeTrigger != null) {
        final speedMs = _speedKmh / 3.6;
        final timeRadius = math.max(200.0, speedMs * point.timeTrigger!.inSeconds.toDouble());
        final dist = AlarmService.distanceMeters(userLat, userLng, point.latitude, point.longitude);
        final insideTimeCircle = dist <= timeRadius;
        shouldTrigger = point.zoneTrigger == ZoneTrigger.onEntry ? insideTimeCircle : !insideTimeCircle;
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
  String _lastRadiusDataHash = ''; // skip rebuild if alarm data unchanged

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
    // Pre-create alarm sources at init (style is guaranteed loaded here)
    // Layers are added/removed dynamically, but sources persist — avoids
    // silent addSource failures when style is transiently unavailable.
    for (int i = 0; i < 20; i++) {
      await style.addSource(GeoJsonSource(id: 'radius-pt-alarm-$i', data: _emptyGeoJson));
    }
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
    // 512px vector tile scale: basePx needs 2× vs 256px slippy-map formula
    final basePx = 2 * radius / (156543.03392 * math.cos(_assignLat * math.pi / 180));
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

    final alarmCircles = <({String id, double lng, double lat, double radiusMeters, bool active, bool isTime, bool isLeave})>[];
    for (int i = 0; i < alarmProv.alarmPoints.length; i++) {
      final p = alarmProv.alarmPoints[i];
      // Skip the alarm being edited — its overlay handles the visual
      if (_isAssigning && _assignExisting != null && _assignExisting!.id == p.id) continue;
      double radius = p.radiusMeters;
      final isTime = p.triggerType == TriggerType.time;
      if (isTime && p.timeTrigger != null) {
        radius = math.max(200.0, (_speedKmh / 3.6) * p.timeTrigger!.inSeconds.toDouble());
      }
      alarmCircles.add((id: 'alarm-$i', lng: p.longitude, lat: p.latitude, radiusMeters: radius, active: p.isActive, isTime: isTime, isLeave: p.zoneTrigger == ZoneTrigger.onLeave));
    }
    // Skip rebuild if alarm data unchanged (prevents circle flash on map pan/zoom)
    final dataHash = alarmCircles.map((c) => '${c.lng},${c.lat},${c.radiusMeters.toStringAsFixed(1)},${c.active},${c.isTime},${c.isLeave}').join('|');
    final editHash = _isAssigning ? 'e${_assignExisting?.id}' : '';
    final fullHash = '$dataHash|$editHash';
    if (fullHash == _lastRadiusDataHash) return;
    _lastRadiusDataHash = fullHash;

    _radiusLayerVersion++;
    final v = _radiusLayerVersion;
    _radiusDebounce?.cancel();
    _radiusDebounce = Timer(const Duration(milliseconds: 200), () {
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
        .where((p) => p.zoneTrigger == ZoneTrigger.onLeave
            && !(_isAssigning && _assignExisting?.id == p.id))
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

  /// Rebuild alarm circle + label layers using per-alarm CircleStyleLayer with
  /// literal interpolate expression (see docs/vector-map-radius-circles.md).
  /// onLeave alarms get stroke-only circle (transparent fill); the veil provides the fill.
  Future<void> _rebuildRadiusLayers(StyleController style, List<({String id, double lng, double lat, double radiusMeters, bool active, bool isTime, bool isLeave})> circles, int version) async {
    DebugConsole.log('REBUILD_LAYERS: START ${circles.length} circles v=$version');
    // Pre-render all marker bitmaps BEFORE removing old layers (minimize flash gap)
    final markerImages = <String, Uint8List>{};
    for (final c in circles) {
      final labelText = c.isTime
          ? '${(c.radiusMeters / 1000).toStringAsFixed(1)}km'
          : AlarmMarkerRenderer.formatDistance(c.radiusMeters);
      final markerColor = c.isTime
          ? (c.active ? Colors.orange : Colors.grey)
          : (c.active ? Colors.red : Colors.grey);
      markerImages['alarm-marker-${c.id}'] = await AlarmMarkerRenderer.render(
        label: labelText, color: markerColor, dpr: _deviceDpr,
      );
    }

    if (version != _radiusLayerVersion) return;

    // Now swap layers: remove old, add new (images already prepared)
    for (int i = 0; i < 20; i++) {
      final id = 'alarm-$i';
      try { await style.removeLayer('radius-label-$id'); } catch (_) {}
      try { await style.removeLayer('radius-circle-$id'); } catch (_) {}
      style.updateGeoJsonSource(id: 'radius-pt-$id', data: _emptyGeoJson);
    }

    for (final c in circles) {
      // 512px vector tile scale: basePx needs 2× vs 256px slippy-map formula
      final basePx = 2 * c.radiusMeters / (156543.03392 * math.cos(c.lat * math.pi / 180));
      // onLeave: veil provides fill, but we still add stroke-only circle for border
      final String fillColor = c.isLeave
          ? 'rgba(0,0,0,0)'
          : (c.isTime
              ? (c.active ? 'rgba(255,152,0,0.10)' : 'rgba(158,158,158,0.05)')
              : (c.active ? 'rgba(255,0,0,0.12)' : 'rgba(158,158,158,0.05)'));
      final String strokeColor = c.isTime
          ? (c.active ? 'rgba(255,152,0,0.7)' : 'rgba(158,158,158,0.3)')
          : (c.active ? 'rgba(255,0,0,0.6)' : 'rgba(158,158,158,0.3)');
      final strokeWidth = c.active ? 2.0 : 1.0;

      try {
        style.updateGeoJsonSource(
          id: 'radius-pt-${c.id}',
          data: _pointGeoJson(c.lng, c.lat),
        );
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
        // Composite pin+chip bitmap marker (pre-rendered above, matches raster design)
        final imageId = 'alarm-marker-${c.id}';
        final markerPng = markerImages[imageId];
        if (markerPng != null) {
          try { await style.removeImage(imageId); } catch (_) {}
          await style.addImage(imageId, markerPng);
        }
        await style.addLayer(SymbolStyleLayer(
          id: 'radius-label-${c.id}',
          sourceId: 'radius-pt-${c.id}',
          layout: {
            'icon-image': imageId,
            'icon-size': 1.0,
            'icon-anchor': 'bottom',
            'icon-allow-overlap': true,
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
    final metersPerPx = _vectorMetersPerPx(tapLat, _currentZoom);
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
    DebugConsole.log('TAP: lat=${position.lat} lng=${position.lng} isAssigning=$_isAssigning lastPointer=$_lastPointerDownPos');
    if (_isAssigning) return;
    final tapLat = position.lat.toDouble();
    final tapLng = position.lng.toDouble();
    final alarmProv = context.read<AlarmProvider>();
    final existing = _findTappedAlarm(tapLat, tapLng, alarmProv);
    if (existing != null) {
      // Use alarm's original coordinates, not tap coordinates (avoids pixel offset drift)
      _startAssign(existing.latitude, existing.longitude, existing: existing);
    } else {
      _startAssign(tapLat, tapLng);
    }
  }

  /// Project geo coordinates to screen position (inverse of toLngLatSync).
  /// Returns null if controller not available.
  Offset? _geoToScreen(double lat, double lng) {
    final screen = _controller?.toScreenLocationSync(Position(lng, lat));
    if (screen == null) return null;
    // toScreenLocationSync returns physical pixels on Android; convert to logical
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return screen / dpr;
  }

  void _startAssign(double lat, double lng, {AlarmPoint? existing}) {
    _assignScreenCenter = existing != null
        ? (_geoToScreen(existing.latitude, existing.longitude) ?? _lastPointerDownPos)
        : _lastPointerDownPos;
    setState(() {
      _isAssigning = true;
      _assignExisting = existing;
      _assignLat = lat;
      _assignLng = lng;
      _assignRadius = existing?.radiusMeters ?? 500;
      _assignTriggerType = existing?.triggerType ?? TriggerType.distance;
      _assignZoneTrigger = existing?.zoneTrigger ?? ZoneTrigger.onEntry;
      _assignTimeMinutes = existing?.timeTrigger?.inMinutes ?? 10;
    });
    _radiusNotifier.value = _currentRadiusPx;
    DebugConsole.log('ASSIGN_START: lat=$lat lng=$lng existing=${existing?.id} screenCenter=$_assignScreenCenter radiusPx=${_currentRadiusPx.toStringAsFixed(1)} radiusM=$_assignRadius');
    // Immediately update veil+layers for edit (hide edited alarm's native layers, show edit veil)
    final style = _controller?.style;
    if (style != null) {
      DebugConsole.log('ASSIGN_START: updating veil immediately');
      _updateVeil(style, context.read<AlarmProvider>());
    }
    // Force hash invalidation so native layers update for the edit state
    _lastRadiusDataHash = '';
  }


  Future<void> _cancelAssign() async {
    DebugConsole.log('CANCEL_ASSIGN: isAssigning=$_isAssigning existing=${_assignExisting?.id}');
    _controller?.style?.updateGeoJsonSource(id: 'fast-src', data: _emptyGeoJson);
    final wasExisting = _assignExisting;

    // If editing existing alarm: rebuild native layers BEFORE hiding overlay
    if (wasExisting != null && _controller?.style != null && _radiusLayerReady) {
      final style = _controller!.style!;
      final alarmProv = context.read<AlarmProvider>();
      // Temporarily clear edit state so rebuild includes the alarm again
      _assignExisting = null;
      _lastRadiusDataHash = '';
      _updateVeil(style, alarmProv);
      // Build circles for all alarms (including the one we were editing)
      final circles = <({String id, double lng, double lat, double radiusMeters, bool active, bool isTime, bool isLeave})>[];
      for (int i = 0; i < alarmProv.alarmPoints.length; i++) {
        final p = alarmProv.alarmPoints[i];
        double r = p.radiusMeters;
        if (p.triggerType == TriggerType.time && p.timeTrigger != null) {
          r = math.max(200.0, (_speedKmh / 3.6) * p.timeTrigger!.inSeconds.toDouble());
        }
        circles.add((id: 'alarm-$i', lng: p.longitude, lat: p.latitude, radiusMeters: r, active: p.isActive, isTime: p.triggerType == TriggerType.time, isLeave: p.zoneTrigger == ZoneTrigger.onLeave));
      }
      _radiusLayerVersion++;
      await _rebuildRadiusLayers(style, circles, _radiusLayerVersion);
      _lastRadiusDataHash = circles.map((c) => '${c.lng},${c.lat},${c.radiusMeters.toStringAsFixed(1)},${c.active},${c.isTime},${c.isLeave}').join('|');
      await Future.delayed(const Duration(milliseconds: 100));
    } else {
      final style = _controller?.style;
      if (style != null) _updateVeil(style, context.read<AlarmProvider>());
    }

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

  Future<void> _saveAssign(AlarmPoint alarm) async {
    DebugConsole.log('SAVE_ASSIGN: existing=${_assignExisting?.id} lat=${alarm.latitude} lng=${alarm.longitude} r=${alarm.radiusMeters.round()}m');
    final alarmProv = context.read<AlarmProvider>();
    if (_assignExisting != null) {
      alarmProv.updateAlarmPoint(alarm);
    } else if (alarmProv.canAddAlarm) {
      alarmProv.addAlarmPoint(alarm);
    }
    // Build native layers BEFORE hiding overlay to avoid flash gap
    _lastRadiusDataHash = '';
    final style = _controller?.style;
    if (style != null && _radiusLayerReady) {
      final circles = <({String id, double lng, double lat, double radiusMeters, bool active, bool isTime, bool isLeave})>[];
      for (int i = 0; i < alarmProv.alarmPoints.length; i++) {
        final p = alarmProv.alarmPoints[i];
        double r = p.radiusMeters;
        if (p.triggerType == TriggerType.time && p.timeTrigger != null) {
          r = math.max(200.0, (_speedKmh / 3.6) * p.timeTrigger!.inSeconds.toDouble());
        }
        circles.add((id: 'alarm-$i', lng: p.longitude, lat: p.latitude, radiusMeters: r, active: p.isActive, isTime: p.triggerType == TriggerType.time, isLeave: p.zoneTrigger == ZoneTrigger.onLeave));
      }
      _radiusLayerVersion++;
      await _rebuildRadiusLayers(style, circles, _radiusLayerVersion);
      _lastRadiusDataHash = circles.map((c) => '${c.lng},${c.lat},${c.radiusMeters.toStringAsFixed(1)},${c.active},${c.isTime},${c.isLeave}').join('|');
      // Wait 2 frames for MapLibre to render the native layers before hiding overlay
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _cancelAssign();
  }


  /// Meters per pixel for MapLibre vector tiles (512px effective tile size).
  /// Standard slippy-map formula uses 256px; MapLibre vector renders at 512px scale,
  /// so we use zoom+1 to get the correct conversion.
  double _vectorMetersPerPx(double lat, double zoom) {
    return 156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom + 1);
  }

  /// Current fast assign radius in screen pixels (for overlay painter).
  double get _currentRadiusPx {
    final isTime = _assignTriggerType == TriggerType.time;
    double radius = _assignRadius;
    if (isTime) {
      radius = math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60);
    }
    final actualZoom = _controller?.camera?.zoom ?? _currentZoom;
    return radius / _vectorMetersPerPx(_assignLat, actualZoom);
  }

  // Build separate marker point lists for active (red) and inactive (grey) pins
  ({List<Point> active, List<Point> inactive}) _buildMarkerPoints(AlarmProvider alarmProv) {
    final active = <Point>[];
    final inactive = <Point>[];

    for (final p in alarmProv.alarmPoints) {
      // Skip the alarm being edited — overlay draws its pin
      if (_isAssigning && _assignExisting != null && _assignExisting!.id == p.id) continue;
      final point = Point(coordinates: Position(p.longitude, p.latitude));
      if (p.isActive) {
        active.add(point);
      } else {
        inactive.add(point);
      }
    }

    // Assign pin is drawn in the Flutter overlay (not MarkerLayer)
    // to avoid geo conversion offset — both pin and circle use screen coords

    return (active: active, inactive: inactive);
  }



  @override
  Widget build(BuildContext context) {
    final styleUrl = context.select<SettingsProvider, String>(
        (p) => _styleUrls[p.settings.vectorStyleUrl] ?? _styleUrls['liberty']!);
    final alarmProv = context.watch<AlarmProvider>();

    _syncRadiusSource(alarmProv);

    return Stack(
      children: [
        // GestureDetector for immediate swipe + native projection for exact geo
        GestureDetector(
          onLongPressStart: _isAssigning ? null : (details) {
            final haptic = context.read<SettingsProvider>().settings.hapticFeedback;
            if (haptic) Vibration.vibrate(duration: 30);
            _assignScreenCenter = details.localPosition;
            _isDraggingRadius = true;
            // Native fromScreenLocation expects physical pixels; Flutter gives logical
            final dpr = MediaQuery.devicePixelRatioOf(context);
            final geo = _controller?.toLngLatSync(details.localPosition * dpr);
            if (geo != null) {
              _startAssign(geo.lat.toDouble(), geo.lng.toDouble());
            } else {
              _startAssign(
                _controller?.camera?.center?.lat.toDouble() ?? 0,
                _controller?.camera?.center?.lng.toDouble() ?? 0,
              );
            }
          },
          onLongPressMoveUpdate: !_isAssigning ? null : (details) {
            if (!_isDraggingRadius || _assignScreenCenter == null) return;
            final dist = (details.localPosition - _assignScreenCenter!).distance;
            if (_assignTriggerType == TriggerType.distance) {
              _assignRadius = (dist * _vectorMetersPerPx(_assignLat, _currentZoom)).clamp(100.0, 5000.0);
            } else {
              _assignTimeMinutes = (dist * 0.3).clamp(5.0, 120.0).round();
            }
            _radiusNotifier.value = _currentRadiusPx;
            setState(() {});
          },
          onLongPressEnd: !_isAssigning ? null : (details) {
            _isDraggingRadius = false;
          },
          child: MapLibreMap(
            key: ValueKey(styleUrl),
            options: MapOptions(
              initStyle: styleUrl,
              initCenter: Position(
                context.read<MapProvider>().center.longitude,
                context.read<MapProvider>().center.latitude,
              ),
              initZoom: context.read<MapProvider>().zoom,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoaded: (style) {
              _registerImages(style);
              // Style JSON may override initZoom/initCenter with its defaults.
              // Restore MapProvider values after style loads.
              final mp = context.read<MapProvider>();
              DebugConsole.log('STYLE_LOADED: restoring zoom=${mp.zoom.toStringAsFixed(2)} center=${mp.center}');
              _controller?.moveCamera(
                center: Position(mp.center.longitude, mp.center.latitude),
                zoom: mp.zoom,
              );
            },
            onEvent: (event) {
              if (event is MapEventClick) {
                _onTap(event.point);
              } else if (event is MapEventMoveCamera || event is MapEventCameraIdle) {
                final newZoom = _controller?.camera?.zoom ?? _currentZoom;
                if ((newZoom - _currentZoom).abs() > 0.05) {
                  setState(() => _currentZoom = newZoom);
                }
                // Only sync to MapProvider AFTER images registered (style fully loaded).
                // Before that, camera events carry the style's default zoom, not the user's.
                if (_imagesRegistered) {
                  final mp = context.read<MapProvider>();
                  mp.updateZoomSilent(newZoom);
                  final cam = _controller?.camera;
                  if (cam?.center != null) {
                    mp.updateCenterSilent(LatLng(
                      cam!.center.lat.toDouble(),
                      cam.center.lng.toDouble(),
                    ));
                  }
                }
              }
            },
          layers: [
            // Pin+chip markers are rendered as bitmap icons in _rebuildRadiusLayers
            // (SymbolStyleLayer with composite icon-image, not MarkerLayer)
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
        ), // close GestureDetector
        // Capture pointer position before map processes it
        if (!_isAssigning)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) {
                _lastPointerDownPos = e.localPosition;
                DebugConsole.log('CAPTURE_POINTER: pos=${e.localPosition} pointer=${e.pointer}');
              },
              child: const SizedBox.expand(),
            ),
          ),
        const OfflineIndicator(),
        // Scale bar — bottom left
        Positioned(
          bottom: 24,
          left: 12,
          child: ScaleBar(
            zoom: _currentZoom + 1, // MapLibre vector: 512px tile scale
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
        // Hamburger menu + map switch — always visible
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 12,
          child: Column(
            children: [
              GestureDetector(
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
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  if (_isAssigning) _cancelAssign();
                  final settings = context.read<SettingsProvider>();
                  final current = settings.settings.mapProvider;
                  final next = current == MapTileProvider.vector ? MapTileProvider.free : MapTileProvider.vector;
                  settings.updateSettings(settings.settings.copyWith(mapProvider: next));
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
                  child: Icon(Icons.layers, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.grey[800], size: 22),
                ),
              ),
            ],
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
                  if (_assignScreenCenter == null) {
                    DebugConsole.log('OVERLAY_DOWN: screenCenter is null!');
                    return;
                  }
                  final dist = (e.localPosition - _assignScreenCenter!).distance;
                  final radiusPx = _radiusNotifier.value;
                  DebugConsole.log('OVERLAY_DOWN: pos=${e.localPosition} center=$_assignScreenCenter dist=${dist.round()} radiusPx=${radiusPx.round()} inside=${dist <= radiusPx * 1.5}');
                  if (dist <= radiusPx * 1.5) {
                    _dragPointerId = e.pointer;
                    _isDraggingRadius = true;
                    _dragLogCounter = 0;
                  }
                },
                onPointerMove: (e) {
                  if (!_isDraggingRadius || _assignScreenCenter == null) return;
                  if (e.pointer != _dragPointerId) return;
                  final dist = (e.localPosition - _assignScreenCenter!).distance;
                  if (_assignTriggerType == TriggerType.distance) {
                    _assignRadius = (dist * _vectorMetersPerPx(_assignLat, _currentZoom)).clamp(100.0, 5000.0);
                  } else {
                    _assignTimeMinutes = (dist * 0.3).clamp(5.0, 120.0).round();
                  }
                  // Update overlay circle instantly (no widget rebuild)
                  _radiusNotifier.value = _currentRadiusPx;
                  // Sync slider in AlarmCard (setState only rebuilds card, not overlay)
                  setState(() {});
                },
                onPointerUp: (e) {
                  DebugConsole.log('OVERLAY_UP: pointer=${e.pointer} dragPointer=$_dragPointerId isDragging=$_isDraggingRadius');
                  if (e.pointer != _dragPointerId) return;
                  _isDraggingRadius = false;
                  _dragPointerId = null;
                },
                child: CustomPaint(
                  painter: _assignScreenCenter != null
                      ? _RadiusOverlayPainter(
                          center: _assignScreenCenter!,
                          radiusNotifier: _radiusNotifier,
                          isTime: _assignTriggerType == TriggerType.time,
                          isLeave: _assignZoneTrigger == ZoneTrigger.onLeave,
                          radiusMeters: _assignRadius,
                          timeMinutes: _assignTimeMinutes,
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
              onCancel: () => _cancelAssign(),
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
  final bool isLeave;
  final double radiusMeters;
  final int timeMinutes;

  _RadiusOverlayPainter({
    required this.center,
    required this.radiusNotifier,
    required this.isTime,
    this.isLeave = false,
    required this.radiusMeters,
    required this.timeMinutes,
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

    // Circle fill — skip for onLeave (veil provides the red fill outside)
    if (!isLeave) {
      canvas.drawCircle(center, radiusPx, Paint()..color = fillColor);
    }
    // Circle stroke/border — always drawn (onLeave needs it as veil boundary)
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

    // Pin marker at circle center — uses AlarmMarkerSpec for consistency with saved/raster
    final pinColor = isTime ? const Color(0xFFFF9800) : const Color(0xFFFF0000);
    const ps = AlarmMarkerSpec.pinSize;
    final pinTp = TextPainter(textDirection: ui.TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(Icons.location_on.codePoint),
        style: TextStyle(
          fontSize: ps,
          fontFamily: Icons.location_on.fontFamily,
          package: Icons.location_on.fontPackage,
          color: pinColor,
        ),
      )
      ..layout();
    pinTp.paint(canvas, Offset(center.dx - ps / 2, center.dy - ps));

    // Chip below pin — same spec as AlarmMarkerRenderer / raster pin_marker
    final chipText = isTime
        ? '${timeMinutes}min'
        : AlarmMarkerRenderer.formatDistance(radiusMeters);
    final chipTp = TextPainter(textDirection: ui.TextDirection.ltr)
      ..text = TextSpan(
        text: chipText,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: AlarmMarkerSpec.chipFontSize,
          fontWeight: FontWeight.bold,
        ),
      )
      ..layout();
    final chipW = chipTp.width + AlarmMarkerSpec.chipPaddingX * 2;
    final chipH = chipTp.height + AlarmMarkerSpec.chipPaddingY * 2;
    final chipTop = center.dy + AlarmMarkerSpec.chipGap;
    final chipRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(center.dx, chipTop + chipH / 2), width: chipW, height: chipH),
      const Radius.circular(AlarmMarkerSpec.chipRadius),
    );
    canvas.drawRRect(chipRect, Paint()..color = pinColor.withOpacity(0.8));
    chipTp.paint(canvas, Offset(center.dx - chipTp.width / 2, chipTop + (chipH - chipTp.height) / 2));
  }

  @override
  bool shouldRepaint(_RadiusOverlayPainter oldDelegate) => true;
}

