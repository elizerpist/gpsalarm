import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/alarm_point.dart';
import '../services/database_service.dart';
import '../services/debug_console.dart';

class AlarmProvider extends ChangeNotifier {
  static const int maxActiveAlarms = 50;
  static const double duplicateThresholdMeters = 50.0;
  static const String _hiveBoxName = 'alarmPoints';

  List<AlarmPoint> _alarmPoints = [];
  Box? _hiveBox;

  List<AlarmPoint> get alarmPoints => List.unmodifiable(_alarmPoints);
  int get activeCount => _alarmPoints.where((p) => p.isActive).length;
  bool get canAddAlarm => activeCount < maxActiveAlarms;

  Future<void> init() async {
    _hiveBox = await Hive.openBox(_hiveBoxName);

    // Try SQLite first
    bool loadedFromDb = false;
    try {
      final rows = await DatabaseService.getAllAlarmPoints();
      if (rows.isNotEmpty) {
        _alarmPoints = rows
            .map((r) => AlarmPoint.fromMap(DatabaseService.fromDbRow(r)))
            .toList();
        loadedFromDb = true;
        DebugConsole.log('Alarms loaded from SQLite: ${_alarmPoints.length} points');
      }
    } catch (e) {
      DebugConsole.log('SQLite alarm load failed: $e');
    }

    // Fallback: Hive
    if (!loadedFromDb) {
      try {
        _alarmPoints = _hiveBox!.values
            .map((e) => AlarmPoint.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (_alarmPoints.isNotEmpty) {
          DebugConsole.log('Alarms loaded from Hive (fallback): ${_alarmPoints.length} points');
          _saveToDb();
        } else {
          DebugConsole.log('Alarms: empty (first run)');
        }
      } catch (e) {
        DebugConsole.log('Hive alarm load failed: $e');
        _alarmPoints = [];
      }
    }

    notifyListeners();
  }

  void addAlarmPoint(AlarmPoint point) {
    if (!canAddAlarm) return;
    _alarmPoints.add(point);
    _saveAll();
    DebugConsole.log('Alarm added: ${point.name ?? point.id} (${point.radiusMeters.round()}m)');
    notifyListeners();
  }

  void removeAlarmPoint(String id) {
    _alarmPoints.removeWhere((p) => p.id == id);
    _saveAll();
    _deleteFromDb(id);
    DebugConsole.log('Alarm removed: $id');
    notifyListeners();
  }

  void updateAlarmPoint(AlarmPoint updated) {
    final index = _alarmPoints.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      _alarmPoints[index] = updated;
      _saveAll();
      DebugConsole.log('Alarm updated: ${updated.name ?? updated.id}');
      notifyListeners();
    }
  }

  void toggleActive(String id) {
    final index = _alarmPoints.indexWhere((p) => p.id == id);
    if (index != -1) {
      final point = _alarmPoints[index];
      _alarmPoints[index] = point.copyWith(isActive: !point.isActive);
      _saveAll();
      DebugConsole.log('Alarm toggled: ${point.name ?? id} → ${!point.isActive ? "ACTIVE" : "INACTIVE"}');
      notifyListeners();
    }
  }

  AlarmPoint? findNearby(double lat, double lng) {
    for (final point in _alarmPoints) {
      final distance = _haversineMeters(lat, lng, point.latitude, point.longitude);
      if (distance < duplicateThresholdMeters) return point;
    }
    return null;
  }

  // ─── Persistence ────────────────────────────────

  void _saveAll() {
    _saveToHive();
    _saveToDb();
  }

  void _saveToHive() {
    if (_hiveBox == null) return;
    _hiveBox!.clear();
    for (final point in _alarmPoints) {
      _hiveBox!.put(point.id, point.toMap());
    }
  }

  void _saveToDb() {
    try {
      DatabaseService.replaceAllAlarmPoints(
          _alarmPoints.map((p) => p.toMap()).toList());
    } catch (e) {
      DebugConsole.log('SQLite alarm save failed: $e');
    }
  }

  void _deleteFromDb(String id) {
    try {
      DatabaseService.deleteAlarmPoint(id);
    } catch (e) {
      DebugConsole.log('SQLite alarm delete failed: $e');
    }
  }

  // ─── Haversine ──────────────────────────────────

  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
        sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRad(double deg) => deg * pi / 180;
}
