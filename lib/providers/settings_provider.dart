import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/app_settings.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _boxName = 'settings';
  static const String _key = 'appSettings';

  AppSettings _settings = AppSettings();
  Box? _box;

  AppSettings get settings => _settings;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _loadFromBox();
  }

  void _loadFromBox() {
    if (_box == null) return;
    final raw = _box!.get(_key);
    if (raw != null) {
      _settings = AppSettings.fromMap(Map<String, dynamic>.from(raw as Map));
      notifyListeners();
    }
  }

  void _saveToBox() {
    _box?.put(_key, _settings.toMap());
  }

  void updateSettings(AppSettings updated) {
    _settings = updated;
    _saveToBox();
    notifyListeners();
  }
}
