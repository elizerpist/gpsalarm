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
    final dataHash = circles.map((c) => '${c.lng},${c.lat},${c.radiusMeters.toStringAsFixed(1)},${c.active},${c.isTime},${c.isLeave}').join('|');
    return editingId == null ? dataHash : '$dataHash|e$editingId';
  }
}
