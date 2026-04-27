import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
import '../services/location_service.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import '../services/debug_console.dart';
import '../widgets/scale_bar.dart';
import '../widgets/fast_assign_card.dart';

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
  bool _isFastAssigning = false;
  double _fastAssignLat = 0;
  double _fastAssignLng = 0;
  double _fastAssignRadiusMeters = 500;
  TriggerType _fastAssignTriggerType = TriggerType.distance;
  ZoneTrigger _fastAssignZoneTrigger = ZoneTrigger.onEntry;
  int _fastAssignTimeMinutes = 10;
  Offset? _fastAssignScreenCenter;
  bool _isDraggingRadius = false;
  int? _dragPointerId; // Track single pointer to avoid multitouch chaos
  double _currentZoom = 13;
  double _speedKmh = 0;
  Position? _pendingTapPoint;
  double _pendingRadius = 500;
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
        final newSpeed = _locationService.averageSpeedKmh;
        if ((newSpeed - _speedKmh).abs() > 0.5) {
          setState(() => _speedKmh = newSpeed);
        }
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
    // Persistent source for pending tap circle
    await style.addSource(GeoJsonSource(id: 'pending-src', data: _emptyGeoJson));
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
      data: _pointGeoJson(_fastAssignLng, _fastAssignLat),
    );

    final isTime = _fastAssignTriggerType == TriggerType.time;
    double radius = _fastAssignRadiusMeters;
    if (isTime) {
      radius = math.max(200.0, (_speedKmh / 3.6) * _fastAssignTimeMinutes * 60);
    }
    final basePx = radius / (156543.03392 * math.cos(_fastAssignLat * math.pi / 180));
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

  /// Recreate pending tap CircleStyleLayer with current radius.
  Future<void> _updatePendingCircleLayer(StyleController style) async {
    try { await style.removeLayer('pending-circle'); } catch (_) {}

    final lat = _pendingTapPoint!.lat.toDouble();
    final basePx = _pendingRadius / (156543.03392 * math.cos(lat * math.pi / 180));

    await style.addLayer(CircleStyleLayer(
      id: 'pending-circle',
      sourceId: 'pending-src',
      paint: {
        'circle-radius': [
          'interpolate', ['exponential', 2.0], ['zoom'],
          0.0, basePx,
          22.0, basePx * 4194304.0,
        ],
        'circle-color': 'rgba(255,0,0,0.12)',
        'circle-stroke-color': 'rgba(255,0,0,0.6)',
        'circle-stroke-width': 2.0,
      },
    ));
  }

  /// Sync radius circles.
  /// Fast assign + pending: dedicated CircleStyleLayer, debounced per-frame.
  /// Alarm circles: debounced rebuild, SKIPPED during drag (they don't change).
  void _syncRadiusSource(AlarmProvider alarmProv) {
    if (!_radiusLayerReady) return;
    final style = _controller?.style;
    if (style == null) return;

    // --- Fast assign circle: debounced 16ms (1 frame) ---
    if (_isFastAssigning) {
      _fastCircleVersion++;
      final fv = _fastCircleVersion;
      _fastCircleDebounce?.cancel();
      _fastCircleDebounce = Timer(const Duration(milliseconds: 16), () {
        if (fv == _fastCircleVersion) {
          _updateFastCircleLayer(style);
        }
      });
    } else if (_fastCircleVersion > 0) {
      _fastCircleDebounce?.cancel();
      _fastCircleVersion = 0;
      try { style.removeLayer('fast-circle'); } catch (_) {}
      style.updateGeoJsonSource(id: 'fast-src', data: _emptyGeoJson);
    }

    // --- Pending tap circle: debounced 16ms ---
    if (_pendingTapPoint != null) {
      style.updateGeoJsonSource(
        id: 'pending-src',
        data: _pointGeoJson(
          _pendingTapPoint!.lng.toDouble(),
          _pendingTapPoint!.lat.toDouble(),
        ),
      );
      _updatePendingCircleLayer(style);
    } else {
      try { style.removeLayer('pending-circle'); } catch (_) {}
      style.updateGeoJsonSource(id: 'pending-src', data: _emptyGeoJson);
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
    final hasFastLeave = _isFastAssigning && _fastAssignZoneTrigger == ZoneTrigger.onLeave;

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
      final r = _fastAssignTriggerType == TriggerType.time
          ? math.max(200.0, (_speedKmh / 3.6) * _fastAssignTimeMinutes * 60)
          : _fastAssignRadiusMeters;
      holes.add(_geoCircle(_fastAssignLng, _fastAssignLat, r));
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
    DebugConsole.log('VECTOR TAP: lat=${position.lat}, lng=${position.lng}, fastAssign=$_isFastAssigning');
    if (_isFastAssigning) return;
    final lat = position.lat.toDouble();
    final lng = position.lng.toDouble();
    final alarmProv = context.read<AlarmProvider>();
    final existing = _findTappedAlarm(lat, lng, alarmProv);
    if (existing != null) {
      setState(() {
        _pendingTapPoint = position;
        _pendingRadius = existing.radiusMeters;
      });
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => RadiusPopup(
          latitude: existing.latitude, longitude: existing.longitude, existingPoint: existing,
          onRadiusChanged: (v) { if (mounted) setState(() => _pendingRadius = v); },
        ),
      ).whenComplete(() {
        if (mounted) setState(() => _pendingTapPoint = null);
      });
    } else {
      setState(() {
        _pendingTapPoint = position;
        _pendingRadius = 500;
      });
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => RadiusPopup(
          latitude: lat, longitude: lng,
          onRadiusChanged: (v) { if (mounted) setState(() => _pendingRadius = v); },
        ),
      ).whenComplete(() {
        if (mounted) setState(() => _pendingTapPoint = null);
      });
    }
  }

  void _onLongPress(Position position) {
    DebugConsole.log('VECTOR LONG PRESS: lat=${position.lat}, lng=${position.lng}');
    final haptic = context.read<SettingsProvider>().settings.hapticFeedback;
    if (haptic) Vibration.vibrate(duration: 30);

    // Estimate screen position of the long-press point from camera state.
    // MapLibre 0.2.2 doesn't expose latLngToScreenPoint, so we calculate from
    // the camera center and zoom level.
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
        // Approximate pixel offset from camera center
        final dLng = (position.lng.toDouble() - camLng);
        final dLat = (position.lat.toDouble() - camLat);
        final dx = dLng * math.cos(camLat * math.pi / 180) * (111320.0 / metersPerPx);
        final dy = -dLat * (110540.0 / metersPerPx);
        screenCenter = Offset(size.width / 2 + dx, size.height / 2 + dy);
      }
    }

    DebugConsole.log('FAST_ASSIGN: activated at ($screenCenter), lat=${position.lat.toStringAsFixed(4)}, lng=${position.lng.toStringAsFixed(4)}');
    setState(() {
      _isFastAssigning = true;
      _isDraggingRadius = true; // Allow immediate swipe without lifting finger
      _fastAssignLat = position.lat.toDouble();
      _fastAssignLng = position.lng.toDouble();
      _fastAssignRadiusMeters = 500;
      _fastAssignScreenCenter = screenCenter;
    });
  }

  void _cancelFastAssign() {
    DebugConsole.log('FAST_ASSIGN: cancelled');
    // Clear fast circle source
    _controller?.style?.updateGeoJsonSource(id: 'fast-src', data: _emptyGeoJson);
    setState(() {
      _isFastAssigning = false;
      _fastAssignScreenCenter = null;
      _isDraggingRadius = false;
      _dragPointerId = null;
      _fastAssignTriggerType = TriggerType.distance;
      _fastAssignZoneTrigger = ZoneTrigger.onEntry;
      _fastAssignTimeMinutes = 10;
    });
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

    // Pending tap point — always red
    if (_pendingTapPoint != null) {
      active.add(Point(coordinates: _pendingTapPoint!));
    }

    // Fast assign point — always red
    if (_isFastAssigning) {
      active.add(Point(coordinates: Position(_fastAssignLng, _fastAssignLat)));
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
                    onClose: () => context.read<MapProvider>().toggleSearch(),
                  )
                : const SizedBox.shrink(),
          ),
        // Radius drag overlay for vector map — blocks map gestures
        if (_isFastAssigning && _fastAssignScreenCenter != null)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                if (_fastAssignScreenCenter == null) return;
                // Track this pointer — ignore all others
                _dragPointerId = e.pointer;
                _isDraggingRadius = true;
                _dragLogCounter = 0;
                DebugConsole.log('VECTOR_DRAG: start pointer=${e.pointer}');
              },
              onPointerMove: (e) {
                if (!_isDraggingRadius || _fastAssignScreenCenter == null) return;
                if (e.pointer != _dragPointerId) return; // ignore other fingers
                final dist = (e.localPosition - _fastAssignScreenCenter!).distance;
                if (_fastAssignTriggerType == TriggerType.distance) {
                  final metersPerPx = 156543.03392 * math.cos(_fastAssignLat * math.pi / 180) / math.pow(2, _currentZoom);
                  final meters = (dist * metersPerPx).clamp(100.0, 5000.0);
                  setState(() => _fastAssignRadiusMeters = meters);
                  // Throttled log: every 10th event
                  if (++_dragLogCounter % 10 == 0) {
                    DebugConsole.log('VECTOR_DRAG: ${dist.round()}px → ${meters.round()}m (updating=$_fastCircleUpdating)');
                  }
                } else {
                  final minutes = (dist * 0.3).clamp(5.0, 120.0).round();
                  setState(() => _fastAssignTimeMinutes = minutes);
                  if (++_dragLogCounter % 10 == 0) {
                    DebugConsole.log('VECTOR_DRAG: ${dist.round()}px → ${minutes}min');
                  }
                }
              },
              onPointerUp: (e) {
                if (e.pointer != _dragPointerId) return;
                DebugConsole.log('VECTOR_DRAG: end');
                _isDraggingRadius = false;
                _dragPointerId = null;
              },
              child: const SizedBox.expand(),
            ),
          ),
        // Fast assign card — shared widget, same as raster map
        if (_isFastAssigning)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: FastAssignCard(
              initialRadius: _fastAssignRadiusMeters,
              onRadiusChanged: (v) => setState(() => _fastAssignRadiusMeters = v),
              onZoneTriggerChanged: (v) => setState(() => _fastAssignZoneTrigger = v),
              onTriggerTypeChanged: (v) => setState(() => _fastAssignTriggerType = v),
              onTimeChanged: (v) => setState(() => _fastAssignTimeMinutes = v),
              onSave: (name, triggerType, zoneTrigger, timeMinutes) {
                _confirmFastAssign();
              },
              onCancel: _cancelFastAssign,
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

