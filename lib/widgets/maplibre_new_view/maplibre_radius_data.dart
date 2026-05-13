part of '../maplibre_new_view.dart';

typedef _RadiusCircleData = ({
  String id,
  double lng,
  double lat,
  double radiusMeters,
  bool active,
  bool isTime,
  bool isLeave,
});

extension _MaplibreRadiusData on _MaplibreNewViewState {
  List<_RadiusCircleData> _buildRadiusCircles(
    AlarmProvider alarmProv, {
    required bool excludeEditing,
    String? excludeAlarmId,
  }) {
    final circles = <_RadiusCircleData>[];
    for (int i = 0; i < alarmProv.alarmPoints.length; i++) {
      final p = alarmProv.alarmPoints[i];
      if (excludeAlarmId != null && p.id == excludeAlarmId) continue;
      if (excludeEditing &&
          _isAssigning &&
          _assignNativeHidden &&
          _assignExisting != null &&
          _assignExisting!.id == p.id) {
        continue;
      }
      double radius = p.radiusMeters;
      final isTime = p.triggerType == TriggerType.time;
      if (isTime && p.timeTrigger != null) {
        radius = math.max(200.0, (_speedKmh / 3.6) * p.timeTrigger!.inSeconds.toDouble());
      }
      circles.add((
        id: 'alarm-$i',
        lng: p.longitude,
        lat: p.latitude,
        radiusMeters: radius,
        active: p.isActive,
        isTime: isTime,
        isLeave: p.zoneTrigger == ZoneTrigger.onLeave,
      ));
    }
    return circles;
  }

  String _radiusHash(List<_RadiusCircleData> circles, {String? editingId}) {
    final dataHash = circles
        .map((c) =>
            '${c.lng},${c.lat},${c.radiusMeters.toStringAsFixed(1)},${c.active},${c.isTime},${c.isLeave}')
        .join('|');
    final modeHash = _is3D ? '3d' : '2d';
    return editingId == null ? '$modeHash|$dataHash' : '$modeHash|$dataHash|e$editingId';
  }

  String? _alarmLayerId(AlarmProvider alarmProv, String alarmId) {
    final index = alarmProv.alarmPoints.indexWhere((p) => p.id == alarmId);
    return index < 0 ? null : 'alarm-$index';
  }

  _RadiusCircleData? _circleForAlarmId(
    AlarmProvider alarmProv,
    String alarmId, {
    List<_RadiusCircleData>? circles,
  }) {
    final id = _alarmLayerId(alarmProv, alarmId);
    if (id == null) return null;
    final source = circles ?? _buildRadiusCircles(alarmProv, excludeEditing: false);
    for (final circle in source) {
      if (circle.id == id) return circle;
    }
    return null;
  }

  _RadiusCircleData? _currentAssignCircle(AlarmProvider alarmProv) {
    final existing = _assignExisting;
    if (existing == null) return null;
    final id = _alarmLayerId(alarmProv, existing.id) ?? _assignNativeAlarmLayerId;
    return _assignCircleForVisualId(id);
  }

  _RadiusCircleData? _currentAssignPreviewCircle(AlarmProvider alarmProv) {
    final existing = _assignExisting;
    final id = _assignNativeAlarmLayerId ??
        (existing == null ? null : _alarmLayerId(alarmProv, existing.id));
    return _assignCircleForVisualId(id);
  }

  _RadiusCircleData? _assignCircleForVisualId(String? id) {
    if (id == null) return null;
    double radius = _assignRadius;
    final isTime = _assignTriggerType == TriggerType.time;
    if (isTime) {
      radius = math.max(200.0, (_speedKmh / 3.6) * _assignTimeMinutes * 60);
    }
    return (
      id: id,
      lng: _assignLng,
      lat: _assignLat,
      radiusMeters: radius,
      active: _assignActive,
      isTime: isTime,
      isLeave: _assignZoneTrigger == ZoneTrigger.onLeave,
    );
  }
}
