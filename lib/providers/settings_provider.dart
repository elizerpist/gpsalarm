import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/app_settings.dart';
import '../services/debug_console.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _boxName = 'settings';
  static const String _key = 'appSettings';

  AppSettings _settings = AppSettings();
  Box? _box;

  AppSettings get settings => _settings;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _loadFromBox();
    DebugConsole.log('Settings loaded: provider=${_settings.mapProvider.name} tile=${_settings.mapTileStyle.name} apiKey=${_settings.googleMapsApiKey != null ? "set" : "null"} mapTilerKey=${_settings.mapTilerApiKey != null ? "set" : "null"}');
  }

  void _loadFromBox() {
    if (_box == null) return;
    final raw = _box!.get(_key);
    if (raw != null) {
      try {
        _settings = AppSettings.fromMap(Map<String, dynamic>.from(raw as Map));
      } catch (e) {
        DebugConsole.log('Settings load ERROR: $e — using defaults');
        _settings = AppSettings();
        _saveToBox();
      }
      notifyListeners();
    }
  }

  void _saveToBox() {
    _box?.put(_key, _settings.toMap());
    DebugConsole.log('Settings SAVED: provider=${_settings.mapProvider.name} apiKey=${_settings.googleMapsApiKey != null ? "set(${_settings.googleMapsApiKey!.length}ch)" : "null"}');
  }

  void updateSettings(AppSettings updated) {
    _settings = updated;
    _saveToBox();
    notifyListeners();
  }
}
