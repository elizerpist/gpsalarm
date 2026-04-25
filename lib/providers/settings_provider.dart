import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/debug_console.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _hiveBoxName = 'settings';
  static const String _hiveKey = 'appSettings';
  static const String _dbKey = 'appSettings';

  AppSettings _settings = AppSettings();
  Box? _hiveBox;

  AppSettings get settings => _settings;

  Future<void> init() async {
    // Open Hive
    _hiveBox = await Hive.openBox(_hiveBoxName);

    // Try loading from SQLite first (primary), fallback to Hive
    bool loadedFromDb = false;
    try {
      final dbJson = await DatabaseService.getSetting(_dbKey);
      if (dbJson != null) {
        final map = json.decode(dbJson) as Map<String, dynamic>;
        _settings = AppSettings.fromMap(map);
        loadedFromDb = true;
        DebugConsole.log('Settings loaded from SQLite');
      }
    } catch (e) {
      DebugConsole.log('SQLite load failed: $e');
    }

    // Fallback: load from Hive
    if (!loadedFromDb) {
      try {
        final raw = _hiveBox!.get(_hiveKey);
        if (raw != null) {
          _settings = AppSettings.fromMap(Map<String, dynamic>.from(raw as Map));
          DebugConsole.log('Settings loaded from Hive (fallback)');
          // Mirror to SQLite
          _saveToDb();
        } else {
          DebugConsole.log('Settings: using defaults (first run)');
        }
      } catch (e) {
        DebugConsole.log('Hive load failed: $e — using defaults');
        _settings = AppSettings();
      }
    }

    _logCurrentSettings();
    notifyListeners();
  }

  void updateSettings(AppSettings updated) {
    _settings = updated;
    _saveToHive();
    _saveToDb();
    notifyListeners();
  }

  void _saveToHive() {
    _hiveBox?.put(_hiveKey, _settings.toMap());
  }

  void _saveToDb() {
    try {
      final jsonStr = json.encode(_settings.toMap());
      DatabaseService.saveSetting(_dbKey, jsonStr);
    } catch (e) {
      DebugConsole.log('SQLite save failed: $e');
    }
  }

  void _logCurrentSettings() {
    final s = _settings;
    DebugConsole.log('Settings: provider=${s.mapProvider.name} tile=${s.mapTileStyle.name} '
        'gApiKey=${s.googleMapsApiKey != null ? "set(${s.googleMapsApiKey!.length}ch)" : "null"} '
        'mtApiKey=${s.mapTilerApiKey != null ? "set(${s.mapTilerApiKey!.length}ch)" : "null"} '
        'alarm=${s.defaultAlarmSound} theme=${s.themeMode.name} locale=${s.locale}');
  }
}
