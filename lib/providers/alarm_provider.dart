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

  final bool enablePersistence;
  List<AlarmPoint> _alarmPoints = [];
  Box? _hiveBox;

  AlarmProvider({this.enablePersistence = true});

  List<AlarmPoint> get alarmPoints => List.unmodifiable(_alarmPoints);
  int get activeCount => _alarmPoints.where((p) => p.isActive).length;
  bool get canAddAlarm => activeCount < maxActiveAlarms;

  Future<void> init() async {
    if (!enablePersistence) {
      notifyListeners();
      return;
    }

    _hiveBox = await Hive.openBox(_hiveBoxName);

    var loadedFromDb = false;
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

    if (!loadedFromDb) {
      try {
        _alarmPoints = _hiveBox!.values
            .map((e) => AlarmPoint.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (_alarmPoints.isNotEmpty) {
          DebugConsole.log('Alarms loaded from Hive (fallback): ${_alarmPoints.length} points');
          await _saveToDb();
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

  Future<void> addAlarmPoint(AlarmPoint point) async {
    if (!canAddAlarm) return;
    _alarmPoints.add(point);
    await _saveAll();
    DebugConsole.log('Alarm added: ${point.name ?? point.id} (${point.radiusMeters.round()}m)');
    notifyListeners();
  }

  Future<void> removeAlarmPoint(String id) async {
    _alarmPoints.removeWhere((p) => p.id == id);
    await _saveAll();
    DebugConsole.log('Alarm removed: $id');
    notifyListeners();
  }

  Future<void> clearAll() async {
    final count = _alarmPoints.length;
    _alarmPoints.clear();
    await _saveAll();
    DebugConsole.log('All alarms cleared ($count points)');
    notifyListeners();
  }

  Future<void> updateAlarmPoint(AlarmPoint updated) async {
    final index = _alarmPoints.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      _alarmPoints[index] = updated;
      await _saveAll();
      DebugConsole.log('Alarm updated: ${updated.name ?? updated.id}');
      notifyListeners();
    }
  }

  Future<void> toggleActive(String id) async {
    final index = _alarmPoints.indexWhere((p) => p.id == id);
    if (index != -1) {
      final point = _alarmPoints[index];
      final next = !point.isActive;
      _alarmPoints[index] = point.copyWith(isActive: next);
      await _saveAll();
      DebugConsole.log('Alarm toggled: ${point.name ?? id} -> ${next ? "ACTIVE" : "INACTIVE"}');
      notifyListeners();
    }
  }

  Future<void> setActive(String id, bool isActive) async {
    final index = _alarmPoints.indexWhere((p) => p.id == id);
    if (index == -1 || _alarmPoints[index].isActive == isActive) return;
    final point = _alarmPoints[index];
    _alarmPoints[index] = point.copyWith(isActive: isActive);
    await _saveAll();
    DebugConsole.log('Alarm active state: ${point.name ?? id} -> ${isActive ? "ACTIVE" : "INACTIVE"}');
    notifyListeners();
  }

  AlarmPoint? findNearby(double lat, double lng) {
    for (final point in _alarmPoints) {
      final distance = _haversineMeters(lat, lng, point.latitude, point.longitude);
      if (distance < duplicateThresholdMeters) return point;
    }
    return null;
  }

  Future<void> _saveAll() async {
    if (!enablePersistence) return;
    await _saveToHive();
    await _saveToDb();
  }

  Future<void> _saveToHive() async {
    if (_hiveBox == null) return;
    await _hiveBox!.clear();
    for (final point in _alarmPoints) {
      await _hiveBox!.put(point.id, point.toMap());
    }
  }

  Future<void> _saveToDb() async {
    if (!enablePersistence) return;
    try {
      await DatabaseService.replaceAllAlarmPoints(
        _alarmPoints.map((p) => p.toMap()).toList(),
      );
    } catch (e) {
      DebugConsole.log('SQLite alarm save failed: $e');
    }
  }

  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
            sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * pi / 180;
}
