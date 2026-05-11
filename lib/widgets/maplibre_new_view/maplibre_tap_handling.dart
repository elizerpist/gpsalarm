part of '../maplibre_new_view.dart';

extension _MaplibreTapHandling on _MaplibreNewViewState {
  AlarmPoint? _findTappedAlarm(double tapLat, double tapLng, AlarmProvider alarmProv) {
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
      unawaited(this._startAssign(existing.latitude, existing.longitude, existing: existing));
    } else {
      unawaited(this._startAssign(tapLat, tapLng));
    }
  }

  Offset? _geoToScreen(double lat, double lng) {
    final screen = _controller?.toScreenLocationSync(Position(lng, lat));
    if (screen == null) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return screen / dpr;
  }
}
