import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import '../models/alarm_point.dart';
import '../models/app_settings.dart';
import '../providers/map_provider.dart';
import '../providers/alarm_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/map_controls.dart';
import '../widgets/search_pill.dart';
import '../widgets/pin_marker.dart';
import '../widgets/radius_circle.dart';
import '../widgets/radius_popup.dart';
import '../widgets/user_location_marker.dart';
import '../services/location_service.dart';
import '../services/alarm_service.dart';
import 'settings_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  LatLng? _userPosition;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Fast assign state
  LatLng? _fastAssignCenter;
  double _fastAssignRadiusMeters = 500;
  bool _isFastAssigning = false;

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
        setState(() {
          _userPosition = LatLng(pos.latitude, pos.longitude);
        });
        final mapProv = context.read<MapProvider>();
        mapProv.setCenter(_userPosition!);
        _mapController.move(_userPosition!, mapProv.zoom);
      }
      _locationService.startTracking(onPosition: (position) {
        if (!mounted) return;
        setState(() {
          _userPosition = LatLng(position.latitude, position.longitude);
        });
        _checkAlarms(position.latitude, position.longitude);
      });
    }
  }

  void _checkAlarms(double userLat, double userLng) {
    final alarmProv = context.read<AlarmProvider>();
    final activePoints =
        alarmProv.alarmPoints.where((p) => p.isActive).toList();

    for (final point in activePoints) {
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
          speedKmh: _locationService.averageSpeedKmh,
        );
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

  @override
  Widget build(BuildContext context) {
    final mapProv = context.watch<MapProvider>();
    final alarmProv = context.watch<AlarmProvider>();
    final settingsProv = context.watch<SettingsProvider>();
    final tileUrl = _getTileUrl(settingsProv.settings);

    return Scaffold(
      key: _scaffoldKey,
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapProv.center,
              initialZoom: mapProv.zoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: (tapPosition, point) => _handleTap(context, point),
              onLongPress: (tapPosition, point) =>
                  _handleLongPress(context, point),
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                  mapProv.setCenter(position.center);
                  mapProv.setZoom(position.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                userAgentPackageName: 'com.gpsalarm.app',
                maxNativeZoom: 19,
                maxZoom: 22,
                keepBuffer: 2,
                panBuffer: 0,
                tileDisplay: const TileDisplay.fadeIn(
                  duration: Duration(milliseconds: 150),
                ),
              ),
              // Radius circles
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
              // Pin markers + user location
              MarkerLayer(
                markers: [
                  ...alarmProv.alarmPoints.map((p) => buildPinMarker(
                        point: p,
                        onTap: () => _showEditPopup(context, p),
                      )),
                  if (_userPosition != null)
                    buildUserLocationMarker(_userPosition!),
                  // Fast assign pin preview
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
            ],
          ),
          // Controls overlay (hidden during fast assign)
          if (!_isFastAssigning)
            MapControls(
              onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
              onZoomIn: () {
                mapProv.zoomIn();
                _mapController.move(mapProv.center, mapProv.zoom);
              },
              onZoomOut: () {
                mapProv.zoomOut();
                _mapController.move(mapProv.center, mapProv.zoom);
              },
              onSearchTap: () => mapProv.toggleSearch(),
              searchActive: mapProv.searchActive,
            ),
          // Search pill
          if (mapProv.searchActive && !_isFastAssigning)
            SearchPill(
              onResultSelected: (result) {
                mapProv.goToSearchResult(result);
                _mapController.move(
                  LatLng(result.latitude, result.longitude),
                  14.0,
                );
              },
            ),
          // Fast assign overlay with slider
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
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: Colors.orange, size: 28),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Fast Assign',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ),
                        Text(
                          '${_fastAssignRadiusMeters.round()}m',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Radius slider
                    Slider(
                      value: _fastAssignRadiusMeters,
                      min: 100,
                      max: 5000,
                      divisions: 49,
                      activeColor: Colors.orange,
                      label: '${_fastAssignRadiusMeters.round()}m',
                      onChanged: (v) =>
                          setState(() => _fastAssignRadiusMeters = v),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('100m',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                        Text('5km',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _cancelFastAssign,
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text(tr('cancel')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: _confirmFastAssign,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text(tr('save')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      drawer: _buildDrawer(context),
    );
  }

  void _handleTap(BuildContext context, LatLng point) {
    if (_isFastAssigning) return;
    final alarmProv = context.read<AlarmProvider>();
    final existing = alarmProv.findNearby(point.latitude, point.longitude);
    if (existing != null) {
      _showEditPopup(context, existing);
    } else {
      _showCreatePopup(context, point);
    }
  }

  void _handleLongPress(BuildContext context, LatLng point) {
    setState(() {
      _isFastAssigning = true;
      _fastAssignCenter = point;
      _fastAssignRadiusMeters = 500;
    });
  }

  void _cancelFastAssign() {
    setState(() {
      _isFastAssigning = false;
      _fastAssignCenter = null;
      _fastAssignRadiusMeters = 500;
    });
  }

  void _confirmFastAssign() {
    if (_fastAssignCenter == null) return;
    final alarmProv = context.read<AlarmProvider>();

    if (alarmProv.canAddAlarm) {
      final point = AlarmPoint(
        id: const Uuid().v4(),
        latitude: _fastAssignCenter!.latitude,
        longitude: _fastAssignCenter!.longitude,
        radiusMeters: _fastAssignRadiusMeters,
        triggerType: TriggerType.distance,
      );
      alarmProv.addAlarmPoint(point);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('fast_alarm',
              args: [_fastAssignRadiusMeters.round().toString()])),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    setState(() {
      _isFastAssigning = false;
      _fastAssignCenter = null;
      _fastAssignRadiusMeters = 500;
    });
  }

  void _showCreatePopup(BuildContext context, LatLng point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RadiusPopup(
        latitude: point.latitude,
        longitude: point.longitude,
      ),
    );
  }

  void _showEditPopup(BuildContext context, AlarmPoint alarmPoint) {
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

  String _getTileUrl(AppSettings settings) {
    switch (settings.mapProvider) {
      case MapTileProvider.googleMaps:
        final key = settings.googleMapsApiKey ?? '';
        return 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&key=$key';
      case MapTileProvider.mapTiler:
        final key = settings.mapTilerApiKey ?? '';
        final style = settings.mapTilerStyle;
        return 'https://api.maptiler.com/maps/$style/{z}/{x}/{y}.png?key=$key';
      case MapTileProvider.free:
        return _getFreeTileUrl(settings.mapTileStyle);
    }
  }

  String _getFreeTileUrl(MapTileStyle style) {
    switch (style) {
      case MapTileStyle.standard:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapTileStyle.humanitarian:
        return 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png';
      case MapTileStyle.topo:
        return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
      case MapTileStyle.positron:
        return 'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
      case MapTileStyle.voyager:
        return 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
      case MapTileStyle.darkMatter:
        return 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
      case MapTileStyle.wikimedia:
        return 'https://maps.wikimedia.org/osm-intl/{z}/{x}/{y}.png';
      case MapTileStyle.openfreemap:
        return 'https://tiles.openfreemap.org/natural_earth/ne2sr/{z}/{x}/{y}.png';
    }
  }

  Widget _buildDrawer(BuildContext context) {
    return const SettingsDrawer();
  }
}
