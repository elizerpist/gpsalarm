import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'debug_console.dart';

class DatabaseService {
  static Database? _db;
  static const _dbName = 'gpsalarm.db';
  static const _version = 1;

  static bool get _isAvailable => !kIsWeb;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = p.join(await getDatabasesPath(), _dbName);
    DebugConsole.log('DB init: $path');
    return openDatabase(
      path,
      version: _version,
      onCreate: (db, version) async {
        DebugConsole.log('DB creating tables...');

        // Settings table - key/value pairs
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');

        // Alarm points table
        await db.execute('''
          CREATE TABLE alarm_points (
            id TEXT PRIMARY KEY,
            name TEXT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            radius_meters REAL NOT NULL,
            time_trigger_minutes INTEGER,
            trigger_type INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            custom_alarm_sound TEXT,
            custom_alarm_type INTEGER,
            created_at TEXT NOT NULL
          )
        ''');

        DebugConsole.log('DB tables created');
      },
    );
  }

  // ─── Settings ──────────────────────────────────────────────

  static Future<void> saveSetting(String key, String value) async {
    if (!_isAvailable) return;
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<String?> getSetting(String key) async {
    if (!_isAvailable) return null;
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  static Future<Map<String, String>> getAllSettings() async {
    if (!_isAvailable) return {};
    final db = await database;
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  static Future<void> saveAllSettings(Map<String, String> settings) async {
    if (!_isAvailable) return;
    final db = await database;
    final batch = db.batch();
    for (final e in settings.entries) {
      batch.insert(
        'settings',
        {'key': e.key, 'value': e.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ─── Alarm Points ─────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAllAlarmPoints() async {
    if (!_isAvailable) return [];
    final db = await database;
    return db.query('alarm_points', orderBy: 'created_at DESC');
  }

  static Future<void> insertAlarmPoint(Map<String, dynamic> point) async {
    if (!_isAvailable) return;
    final db = await database;
    await db.insert('alarm_points', _toDbRow(point),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateAlarmPoint(Map<String, dynamic> point) async {
    if (!_isAvailable) return;
    final db = await database;
    await db.update('alarm_points', _toDbRow(point),
        where: 'id = ?', whereArgs: [point['id']]);
  }

  static Future<void> deleteAlarmPoint(String id) async {
    if (!_isAvailable) return;
    final db = await database;
    await db.delete('alarm_points', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> replaceAllAlarmPoints(
      List<Map<String, dynamic>> points) async {
    if (!_isAvailable) return;
    final db = await database;
    final batch = db.batch();
    batch.delete('alarm_points');
    for (final p in points) {
      batch.insert('alarm_points', _toDbRow(p));
    }
    await batch.commit(noResult: true);
  }

  // Convert AlarmPoint.toMap() format to DB column format
  static Map<String, dynamic> _toDbRow(Map<String, dynamic> point) => {
        'id': point['id'],
        'name': point['name'],
        'latitude': point['latitude'],
        'longitude': point['longitude'],
        'radius_meters': point['radiusMeters'],
        'time_trigger_minutes': point['timeTriggerMinutes'],
        'trigger_type': point['triggerType'],
        'zone_trigger': point['zoneTrigger'] ?? 0,
        'is_active': (point['isActive'] as bool) ? 1 : 0,
        'custom_alarm_sound': point['customAlarmSound'],
        'custom_alarm_type': point['customAlarmType'],
        'created_at': point['createdAt'],
      };

  // Convert DB row to AlarmPoint.fromMap() format
  static Map<String, dynamic> fromDbRow(Map<String, dynamic> row) => {
        'id': row['id'],
        'name': row['name'],
        'latitude': row['latitude'],
        'longitude': row['longitude'],
        'radiusMeters': row['radius_meters'],
        'timeTriggerMinutes': row['time_trigger_minutes'],
        'triggerType': row['trigger_type'],
        'zoneTrigger': row['zone_trigger'] ?? 0,
        'isActive': (row['is_active'] as int) == 1,
        'customAlarmSound': row['custom_alarm_sound'],
        'customAlarmType': row['custom_alarm_type'],
        'createdAt': row['created_at'],
      };
}
