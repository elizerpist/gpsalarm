import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/alarm_point.dart';

class AlarmProvider extends ChangeNotifier {
  static const int maxActiveAlarms = 50;
  static const double duplicateThresholdMeters = 50.0;
  static const String _boxName = 'alarmPoints';

  List<AlarmPoint> _alarmPoints = [];
  Box? _box;

  List<AlarmPoint> get alarmPoints => List.unmodifiable(_alarmPoints);
  int get activeCount => _alarmPoints.where((p) => p.isActive).length;
  bool get canAddAlarm => activeCount < maxActiveAlarms;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _loadFromBox();
  }

  void _loadFromBox() {
    if (_box == null) return;
    _alarmPoints = _box!.values
        .map((e) => AlarmPoint.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    notifyListeners();
  }

  void _saveToBox() {
    if (_box == null) return;
    _box!.clear();
    for (final point in _alarmPoints) {
      _box!.put(point.id, point.toMap());
    }
  }

  void addAlarmPoint(AlarmPoint point) {
    if (!canAddAlarm) return;
    _alarmPoints.add(point);
    _saveToBox();
    notifyListeners();
  }

  void removeAlarmPoint(String id) {
    _alarmPoints.removeWhere((p) => p.id == id);
    _saveToBox();
    notifyListeners();
  }

  void updateAlarmPoint(AlarmPoint updated) {
    final index = _alarmPoints.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      _alarmPoints[index] = updated;
      _saveToBox();
      notifyListeners();
    }
  }

  void toggleActive(String id) {
    final index = _alarmPoints.indexWhere((p) => p.id == id);
    if (index != -1) {
      final point = _alarmPoints[index];
      _alarmPoints[index] = point.copyWith(isActive: !point.isActive);
      _saveToBox();
      notifyListeners();
    }
  }

  AlarmPoint? findNearby(double lat, double lng) {
    for (final point in _alarmPoints) {
      final distance =
          _haversineMeters(lat, lng, point.latitude, point.longitude);
      if (distance < duplicateThresholdMeters) return point;
    }
    return null;
  }

  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRad(double deg) => deg * pi / 180;
}
