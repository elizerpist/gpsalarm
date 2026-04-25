import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/map_provider.dart';
import '../providers/alarm_provider.dart';
import '../widgets/map_controls.dart';
import '../widgets/search_pill.dart';
import '../widgets/pin_marker.dart';
import '../widgets/radius_circle.dart';
import '../widgets/radius_popup.dart';
import '../widgets/user_location_marker.dart';
import '../services/location_service.dart';

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
    }
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
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.gpsalarm.app',
              ),
              // Radius circles
              CircleLayer(
                circles: alarmProv.alarmPoints
                    .map((p) => buildRadiusCircle(p))
                    .toList(),
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
                ],
              ),
            ],
          ),
          // Controls overlay
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
          if (mapProv.searchActive)
            SearchPill(
              onResultSelected: (result) {
                mapProv.goToSearchResult(result);
                _mapController.move(
                  LatLng(result.latitude, result.longitude),
                  14.0,
                );
              },
            ),
        ],
      ),
      drawer: _buildDrawer(context),
    );
  }

  void _handleTap(BuildContext context, LatLng point) {
    final alarmProv = context.read<AlarmProvider>();
    final existing = alarmProv.findNearby(point.latitude, point.longitude);
    if (existing != null) {
      _showEditPopup(context, existing);
    } else {
      _showCreatePopup(context, point);
    }
  }

  void _handleLongPress(BuildContext context, LatLng point) {
    // Fast assign placeholder - will be implemented in Task 10
    _showCreatePopup(context, point);
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

  void _showEditPopup(BuildContext context, dynamic alarmPoint) {
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

  Widget _buildDrawer(BuildContext context) {
    return const Drawer(
      child: SafeArea(
        child: Center(
          child: Text('Settings - TODO'),
        ),
      ),
    );
  }
}
