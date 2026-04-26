import 'dart:async';
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

class MaplibreNewView extends StatefulWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  const MaplibreNewView({super.key, required this.scaffoldKey});

  @override
  State<MaplibreNewView> createState() => _MaplibreNewViewState();
}

class _MaplibreNewViewState extends State<MaplibreNewView> {
  MapController? _controller;
  bool _imagesRegistered = false;
  final LocationService _locationService = LocationService();
  bool _isFastAssigning = false;
  double _fastAssignLat = 0;
  double _fastAssignLng = 0;
  final ValueNotifier<double> _fastAssignRadius = ValueNotifier(500);
  double _currentZoom = 13;
  Position? _pendingTapPoint;
  final ValueNotifier<double> _pendingRadius = ValueNotifier(500);
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
    _fastAssignRadius.dispose();
    _pendingRadius.dispose();
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
      final blueDot = await _renderIconToPng(Icons.circle, const Color(0xFF2196F3), 64);
      await style.addImage('pin-red', redPin);
      await style.addImage('pin-grey', greyPin);
      await style.addImage('dot-blue', blueDot);
      _imagesRegistered = true;
      if (mounted) setState(() {});
      DebugConsole.log('VECTOR: images registered (pin-red, pin-grey, dot-blue)');
    } catch (e) {
      DebugConsole.log('VECTOR: addImage error: $e');
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

  void _onTap(Position position) {
    DebugConsole.log('VECTOR TAP: lat=${position.lat}, lng=${position.lng}, fastAssign=$_isFastAssigning');
    if (_isFastAssigning) return;
    final lat = position.lat.toDouble();
    final lng = position.lng.toDouble();
    final alarmProv = context.read<AlarmProvider>();
    final existing = alarmProv.findNearby(lat, lng);
    if (existing != null) {
      _pendingRadius.value = existing.radiusMeters;
      setState(() => _pendingTapPoint = position);
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => RadiusPopup(
          latitude: existing.latitude, longitude: existing.longitude, existingPoint: existing,
          onRadiusChanged: (v) { if (mounted) _pendingRadius.value = v; },
        ),
      ).whenComplete(() {
        if (mounted) setState(() => _pendingTapPoint = null);
      });
    } else {
      _pendingRadius.value = 500;
      setState(() => _pendingTapPoint = position);
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => RadiusPopup(
          latitude: lat, longitude: lng,
          onRadiusChanged: (v) { if (mounted) _pendingRadius.value = v; },
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
    _fastAssignRadius.value = 500;
    setState(() {
      _isFastAssigning = true;
      _fastAssignLat = position.lat.toDouble();
      _fastAssignLng = position.lng.toDouble();
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
        radiusMeters: _fastAssignRadius.value,
        triggerType: TriggerType.distance,
      ));
    }
    _cancelFastAssign();
  }

  /// Convert meters to pixels at a given latitude and zoom level.
  double _metersToPixels(double meters, double lat, double zoom) {
    final metersPerPixel = 156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);
    return meters / metersPerPixel;
  }

  /// Build a WidgetLayer Marker that draws a translucent radius circle.
  Marker _buildRadiusMarker(double lat, double lng, double radiusMeters, bool isActive) {
    final diameterPx = _metersToPixels(radiusMeters, lat, _currentZoom) * 2;
    final clampedSize = diameterPx.clamp(4.0, 2000.0);
    final color = isActive ? Colors.red : Colors.grey;
    return Marker(
      point: Position(lng, lat),
      size: Size.square(clampedSize),
      alignment: Alignment.center,
      child: Container(
        width: clampedSize,
        height: clampedSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(isActive ? 0.12 : 0.05),
          border: Border.all(
            color: color.withOpacity(isActive ? 0.6 : 0.3),
            width: isActive ? 2 : 1,
          ),
        ),
      ),
    );
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
    DebugConsole.log('VECTOR build: ${markers.active.length} active + ${markers.inactive.length} inactive markers, style=$styleUrl');

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
              if ((newZoom - _currentZoom).abs() > 0.01) {
                setState(() => _currentZoom = newZoom);
              }
            }
          },
          layers: [
            // Active alarm pins — red
            if (_imagesRegistered && markers.active.isNotEmpty)
              MarkerLayer(
                points: markers.active,
                iconImage: 'pin-red',
                iconSize: 0.4,
                iconAnchor: IconAnchor.bottom,
                iconAllowOverlap: true,
              ),
            // Inactive alarm pins — grey
            if (_imagesRegistered && markers.inactive.isNotEmpty)
              MarkerLayer(
                points: markers.inactive,
                iconImage: 'pin-grey',
                iconSize: 0.35,
                iconAnchor: IconAnchor.bottom,
                iconAllowOverlap: true,
              ),
            // User position — native blue dot
            if (_imagesRegistered && _userPos != null)
              MarkerLayer(
                points: [Point(coordinates: _userPos!)],
                iconImage: 'dot-blue',
                iconSize: 0.5,
                iconAnchor: IconAnchor.center,
                iconAllowOverlap: true,
              ),
          ],
          children: [
            // Radius circles — WidgetLayer, rebuilt only on radius notifier changes
            ListenableBuilder(
              listenable: Listenable.merge([_fastAssignRadius, _pendingRadius]),
              builder: (_, __) => WidgetLayer(
                markers: [
                  ...alarmProv.alarmPoints.map((p) => _buildRadiusMarker(p.latitude, p.longitude, p.radiusMeters, p.isActive)),
                  if (_isFastAssigning)
                    _buildRadiusMarker(_fastAssignLat, _fastAssignLng, _fastAssignRadius.value, true),
                  if (_pendingTapPoint != null)
                    _buildRadiusMarker(_pendingTapPoint!.lat.toDouble(), _pendingTapPoint!.lng.toDouble(), _pendingRadius.value, true),
                ],
              ),
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
            child: _VectorFastAssignCard(
              initialRadius: _fastAssignRadius.value,
              onRadiusChanged: (v) => _fastAssignRadius.value = v,
              onSave: _confirmFastAssign,
              onCancel: _cancelFastAssign,
            ),
          ),
      ],
    );
  }
}

/// Vector map fast assign card — own state to avoid parent rebuild on slider drag.
class _VectorFastAssignCard extends StatefulWidget {
  final double initialRadius;
  final ValueChanged<double> onRadiusChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _VectorFastAssignCard({
    required this.initialRadius,
    required this.onRadiusChanged,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_VectorFastAssignCard> createState() => _VectorFastAssignCardState();
}

class _VectorFastAssignCardState extends State<_VectorFastAssignCard> {
  late double _radius;

  @override
  void initState() {
    super.initState();
    _radius = widget.initialRadius;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPad),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1a1a2e) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.location_on, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            const Expanded(child: Text('Fast Assign',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            Text('${_radius.round()}m',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red[700])),
          ]),
          const SizedBox(height: 8),
          Slider(
            value: _radius, min: 100, max: 5000, divisions: 49,
            activeColor: Colors.red,
            onChanged: (v) {
              setState(() => _radius = v);
              widget.onRadiusChanged(v);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('100m', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                Text('5km', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: widget.onCancel, child: Text(tr('cancel')))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: widget.onSave, child: Text(tr('save')))),
          ]),
        ]),
      ),
    );
  }
}
