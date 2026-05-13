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

  final bool enablePersistence;
  AppSettings _settings = AppSettings();
  Box? _hiveBox;

  SettingsProvider({this.enablePersistence = true});

  AppSettings get settings => _settings;

  Future<void> init() async {
    if (!enablePersistence) {
      notifyListeners();
      return;
    }

    _hiveBox = await Hive.openBox(_hiveBoxName);

    var loadedFromDb = false;
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

    if (!loadedFromDb) {
      try {
        final raw = _hiveBox!.get(_hiveKey);
        if (raw != null) {
          _settings = AppSettings.fromMap(Map<String, dynamic>.from(raw as Map));
          DebugConsole.log('Settings loaded from Hive (fallback)');
          await _saveToDb();
        } else {
          DebugConsole.log('Settings: using defaults (first run)');
        }
      } catch (e) {
        DebugConsole.log('Hive load failed: $e - using defaults');
        _settings = AppSettings();
      }
    }

    _logCurrentSettings();
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings updated) async {
    _settings = updated;
    await _saveToHive();
    await _saveToDb();
    notifyListeners();
  }

  Future<void> _saveToHive() async {
    if (!enablePersistence) return;
    await _hiveBox?.put(_hiveKey, _settings.toMap());
  }

  Future<void> _saveToDb() async {
    if (!enablePersistence) return;
    try {
      final jsonStr = json.encode(_settings.toMap());
      await DatabaseService.saveSetting(_dbKey, jsonStr);
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
