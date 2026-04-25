# GPS Alarm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a GPS-based proximity alarm Flutter app where users place pins on an OpenStreetMap and get alerted by distance or estimated time.

**Architecture:** Flat structure with Provider state management. OpenStreetMap tiles via flutter_map, Nominatim/Photon geocoding, Hive local storage, geolocator for GPS. All free, no API keys.

**Tech Stack:** Flutter 3.x, Dart 3.x, flutter_map, latlong2, provider, hive, geolocator, audioplayers, easy_localization

**Spec:** `docs/superpowers/specs/2026-04-25-gpsalarm-design.md`

**Important context:** The developer edits files directly in Termux. Flutter commands (analyze, run, build, test) are run by the user in a separate terminal via:
```bash
bash ~/start-gpsalarm.sh
```
Project path: `/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/home/flutteruser/flutterapps/gpsalarm/`
(Abbreviated as `gpsalarm/` in this plan.)

---

## File Structure

```
gpsalarm/lib/
  main.dart                              — App entry, providers, theme, localization setup
  models/
    alarm_point.dart                     — AlarmPoint model + TriggerType/AlarmType enums
    app_settings.dart                    — AppSettings model + GpsPollingMode/MapStartView enums
  providers/
    alarm_provider.dart                  — AlarmPoint CRUD, Hive persistence, 50-alarm limit
    settings_provider.dart               — AppSettings read/write, Hive persistence
    map_provider.dart                    — Map state: center, zoom, search results, user position
  services/
    location_service.dart                — GPS position stream, speed tracking, permission requests
    geocoding_service.dart               — Nominatim/Photon search with debounce
    alarm_service.dart                   — Proximity check logic, trigger evaluation, ETA calculation
    audio_service.dart                   — Alarm sound playback, vibration, notification
    permission_service.dart              — Progressive permission requests with rationale dialogs
    platform_service.dart                — Platform capability detection (web vs mobile)
  screens/
    map_screen.dart                      — Main screen: full-screen map + floating UI
    settings_screen.dart                 — Hamburger drawer menu items
    alarm_settings_screen.dart           — Alarm type, sound, vibration, volume settings
    gps_settings_screen.dart             — Polling mode, interval settings
    map_settings_screen.dart             — Start view preference
    alarm_list_screen.dart               — Saved locations list with toggle/delete/edit
    alarm_trigger_screen.dart            — Full-screen alarm dismiss overlay
  widgets/
    map_controls.dart                    — Hamburger button, zoom +/-, FAB
    search_pill.dart                     — Search text input + dropdown results
    radius_popup.dart                    — Alarm creation/edit popup (name, trigger, radius/time)
    pin_marker.dart                      — Map pin widget (red tap / orange fast-assign / inactive)
    radius_circle.dart                   — Semi-transparent radius circle overlay on map
    alarm_list_tile.dart                 — Single alarm card in list view
    user_location_marker.dart            — Blue dot for user's current GPS position
    permission_banner.dart               — Inline banner when permission denied + "Open Settings"
  l10n/
    hu.json                              — Hungarian translations
    en.json                              — English translations

gpsalarm/test/
  models/
    alarm_point_test.dart
    app_settings_test.dart
  services/
    alarm_service_test.dart
    geocoding_service_test.dart
  providers/
    alarm_provider_test.dart
    settings_provider_test.dart

gpsalarm/assets/
  sounds/
    classic_bell.mp3                     — (placeholder, added later)
    radar_ping.mp3
    gentle_wake.mp3
```

---

## Task 1: Project Setup — pubspec.yaml + folder structure

**Files:**
- Modify: `gpsalarm/pubspec.yaml`
- Create: `gpsalarm/lib/models/` (directory)
- Create: `gpsalarm/lib/providers/` (directory)
- Create: `gpsalarm/lib/services/` (directory)
- Create: `gpsalarm/lib/screens/` (directory)
- Create: `gpsalarm/lib/widgets/` (directory)
- Create: `gpsalarm/lib/l10n/hu.json`
- Create: `gpsalarm/lib/l10n/en.json`
- Create: `gpsalarm/assets/sounds/` (directory with .gitkeep)

- [ ] **Step 1: Update pubspec.yaml**

Replace the entire pubspec.yaml with correct app name, dependencies, and asset declarations:

```yaml
name: gpsalarm
description: "GPS-based proximity alarm app"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.11.1

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_map: ^7.0.2
  latlong2: ^0.9.1
  http: ^1.2.2
  geolocator: ^13.0.2
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  provider: ^6.1.2
  audioplayers: ^6.1.0
  flutter_local_notifications: ^18.0.1
  vibration: ^2.0.1
  file_picker: ^8.1.6
  easy_localization: ^3.0.7
  uuid: ^4.5.1
  geolocator_android: ^4.6.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/sounds/
    - lib/l10n/
```

- [ ] **Step 2: Create directory structure**

Create all directories:
```
lib/models/
lib/providers/
lib/services/
lib/screens/
lib/widgets/
lib/l10n/
assets/sounds/
test/models/
test/services/
test/providers/
```

- [ ] **Step 3: Create l10n JSON files**

`lib/l10n/hu.json`:
```json
{
  "app_title": "GPS Alarm",
  "saved_locations": "Mentett helyek",
  "alarm_settings": "Alarm beállítások",
  "gps_settings": "GPS beállítások",
  "map_settings": "Térkép beállítások",
  "appearance": "Megjelenés",
  "language": "Nyelv",
  "save": "Mentés",
  "cancel": "Mégse",
  "delete": "Törlés",
  "new_alarm_point": "Új alarm pont",
  "name_optional": "Név (opcionális)",
  "trigger_type": "Trigger típus",
  "distance": "Távolság",
  "time": "Idő",
  "radius_meters": "Sugár (méter)",
  "minutes": "perc",
  "active": "AKTÍV",
  "inactive": "INAKTÍV",
  "no_name": "Nincs név",
  "search_city": "Város keresése...",
  "no_results": "Nincs találat",
  "connection_error": "Kapcsolódási hiba, próbáld újra",
  "gps_unavailable": "GPS nem elérhető",
  "alarm_type": "Alarm típus",
  "sound_and_vibration": "Hang + Vibráció",
  "notification_only": "Csak értesítés",
  "full_screen_alarm": "Teljes ébresztő képernyő",
  "alarm_sound": "Alarm hang",
  "custom_file": "Egyéni fájl választása...",
  "vibration": "Vibráció",
  "volume": "Hangerő",
  "polling_mode": "Polling mód",
  "continuous": "Folyamatos",
  "custom_interval": "Egyéni intervallum",
  "start_view": "Induló nézet",
  "current_gps": "Aktuális GPS pozíció",
  "last_position": "Utolsó mentett pozíció",
  "light": "Világos",
  "dark": "Sötét",
  "system": "Rendszer",
  "active_alarms": "{} aktív alarm",
  "fast_alarm": "Fast alarm - {}m",
  "max_alarms_reached": "Maximum 50 aktív alarm",
  "dismiss": "Elutasítás",
  "background_location_rationale": "A GPS Alarm háttér helymeghatározást igényel, hogy értesíteni tudjon a mentett helyek közelében.",
  "open_settings": "Beállítások megnyitása",
  "play": "Lejátszás"
}
```

`lib/l10n/en.json`:
```json
{
  "app_title": "GPS Alarm",
  "saved_locations": "Saved locations",
  "alarm_settings": "Alarm settings",
  "gps_settings": "GPS settings",
  "map_settings": "Map settings",
  "appearance": "Appearance",
  "language": "Language",
  "save": "Save",
  "cancel": "Cancel",
  "delete": "Delete",
  "new_alarm_point": "New alarm point",
  "name_optional": "Name (optional)",
  "trigger_type": "Trigger type",
  "distance": "Distance",
  "time": "Time",
  "radius_meters": "Radius (meters)",
  "minutes": "minutes",
  "active": "ACTIVE",
  "inactive": "INACTIVE",
  "no_name": "No name",
  "search_city": "Search city...",
  "no_results": "No results found",
  "connection_error": "Connection error, try again",
  "gps_unavailable": "GPS unavailable",
  "alarm_type": "Alarm type",
  "sound_and_vibration": "Sound + Vibration",
  "notification_only": "Notification only",
  "full_screen_alarm": "Full screen alarm",
  "alarm_sound": "Alarm sound",
  "custom_file": "Choose custom file...",
  "vibration": "Vibration",
  "volume": "Volume",
  "polling_mode": "Polling mode",
  "continuous": "Continuous",
  "custom_interval": "Custom interval",
  "start_view": "Start view",
  "current_gps": "Current GPS position",
  "last_position": "Last saved position",
  "light": "Light",
  "dark": "Dark",
  "system": "System",
  "active_alarms": "{} active alarms",
  "fast_alarm": "Fast alarm - {}m",
  "max_alarms_reached": "Maximum 50 active alarms",
  "dismiss": "Dismiss",
  "background_location_rationale": "GPS Alarm needs background location to alert you when you're near your saved locations.",
  "open_settings": "Open Settings",
  "play": "Play"
}
```

- [ ] **Step 4: Create assets/sounds/.gitkeep**

Empty file placeholder for sound assets directory.

- [ ] **Step 5: Ask user to run `flutter pub get`**

User runs in the other terminal:
```bash
proot-distro login ubuntu --user flutteruser -- bash -c "cd /home/flutteruser/flutterapps/gpsalarm && flutter pub get"
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: project setup - dependencies, l10n, folder structure"
```

---

## Task 2: Data Models

**Files:**
- Create: `gpsalarm/lib/models/alarm_point.dart`
- Create: `gpsalarm/lib/models/app_settings.dart`
- Create: `gpsalarm/test/models/alarm_point_test.dart`
- Create: `gpsalarm/test/models/app_settings_test.dart`

- [ ] **Step 1: Write AlarmPoint model tests**

`test/models/alarm_point_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gpsalarm/models/alarm_point.dart';

void main() {
  group('AlarmPoint', () {
    test('creates with required fields', () {
      final point = AlarmPoint(
        id: 'test-1',
        latitude: 47.4979,
        longitude: 19.0402,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      expect(point.id, 'test-1');
      expect(point.isActive, true);
      expect(point.name, isNull);
      expect(point.customAlarmSound, isNull);
      expect(point.customAlarmType, isNull);
    });

    test('creates time-based trigger', () {
      final point = AlarmPoint(
        id: 'test-2',
        latitude: 47.5,
        longitude: 19.08,
        radiusMeters: 0,
        triggerType: TriggerType.time,
        timeTrigger: const Duration(minutes: 30),
      );
      expect(point.triggerType, TriggerType.time);
      expect(point.timeTrigger?.inMinutes, 30);
    });

    test('toMap and fromMap roundtrip', () {
      final original = AlarmPoint(
        id: 'test-3',
        name: 'Work',
        latitude: 47.4979,
        longitude: 19.0402,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
        isActive: false,
      );
      final map = original.toMap();
      final restored = AlarmPoint.fromMap(map);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.latitude, original.latitude);
      expect(restored.isActive, false);
    });

    test('copyWith updates fields', () {
      final point = AlarmPoint(
        id: 'test-4',
        latitude: 47.0,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      final updated = point.copyWith(name: 'Home', radiusMeters: 200);
      expect(updated.name, 'Home');
      expect(updated.radiusMeters, 200);
      expect(updated.id, 'test-4');
    });
  });
}
```

- [ ] **Step 2: Write AlarmPoint model**

`lib/models/alarm_point.dart`:
```dart
enum TriggerType { distance, time }

enum AlarmType { soundAndVibration, notificationOnly, fullScreenAlarm }

class AlarmPoint {
  final String id;
  final String? name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final Duration? timeTrigger;
  final TriggerType triggerType;
  final bool isActive;
  final String? customAlarmSound;
  final AlarmType? customAlarmType;
  final DateTime createdAt;

  AlarmPoint({
    required this.id,
    this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.timeTrigger,
    required this.triggerType,
    this.isActive = true,
    this.customAlarmSound,
    this.customAlarmType,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'timeTriggerMinutes': timeTrigger?.inMinutes,
        'triggerType': triggerType.index,
        'isActive': isActive,
        'customAlarmSound': customAlarmSound,
        'customAlarmType': customAlarmType?.index,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AlarmPoint.fromMap(Map<String, dynamic> map) => AlarmPoint(
        id: map['id'] as String,
        name: map['name'] as String?,
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        radiusMeters: (map['radiusMeters'] as num).toDouble(),
        timeTrigger: map['timeTriggerMinutes'] != null
            ? Duration(minutes: map['timeTriggerMinutes'] as int)
            : null,
        triggerType: TriggerType.values[map['triggerType'] as int],
        isActive: map['isActive'] as bool,
        customAlarmSound: map['customAlarmSound'] as String?,
        customAlarmType: map['customAlarmType'] != null
            ? AlarmType.values[map['customAlarmType'] as int]
            : null,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  AlarmPoint copyWith({
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    Duration? timeTrigger,
    TriggerType? triggerType,
    bool? isActive,
    String? customAlarmSound,
    AlarmType? customAlarmType,
  }) =>
      AlarmPoint(
        id: id,
        name: name ?? this.name,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        radiusMeters: radiusMeters ?? this.radiusMeters,
        timeTrigger: timeTrigger ?? this.timeTrigger,
        triggerType: triggerType ?? this.triggerType,
        isActive: isActive ?? this.isActive,
        customAlarmSound: customAlarmSound ?? this.customAlarmSound,
        customAlarmType: customAlarmType ?? this.customAlarmType,
        createdAt: createdAt,
      );
}
```

- [ ] **Step 3: Write AppSettings model tests**

`test/models/app_settings_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gpsalarm/models/app_settings.dart';
import 'package:gpsalarm/models/alarm_point.dart';

void main() {
  group('AppSettings', () {
    test('creates with defaults', () {
      final settings = AppSettings();
      expect(settings.defaultAlarmType, AlarmType.soundAndVibration);
      expect(settings.defaultAlarmSound, 'classic_bell');
      expect(settings.vibrationEnabled, true);
      expect(settings.volume, 0.7);
      expect(settings.gpsPollingMode, GpsPollingMode.continuous);
      expect(settings.locale, 'hu');
    });

    test('toMap and fromMap roundtrip', () {
      final original = AppSettings(
        volume: 0.5,
        locale: 'en',
        gpsPollingMode: GpsPollingMode.custom,
        customPollingInterval: const Duration(seconds: 30),
      );
      final map = original.toMap();
      final restored = AppSettings.fromMap(map);
      expect(restored.volume, 0.5);
      expect(restored.locale, 'en');
      expect(restored.gpsPollingMode, GpsPollingMode.custom);
      expect(restored.customPollingInterval.inSeconds, 30);
    });
  });
}
```

- [ ] **Step 4: Write AppSettings model**

`lib/models/app_settings.dart`:
```dart
import 'package:flutter/material.dart';
import 'alarm_point.dart';

enum GpsPollingMode { continuous, custom }
enum MapStartView { currentGps, lastPosition, custom }

class AppSettings {
  final AlarmType defaultAlarmType;
  final String defaultAlarmSound;
  final bool vibrationEnabled;
  final double volume;
  final GpsPollingMode gpsPollingMode;
  final Duration customPollingInterval;
  final MapStartView mapStartView;
  final double? customStartLat;
  final double? customStartLng;
  final ThemeMode themeMode;
  final String locale;

  AppSettings({
    this.defaultAlarmType = AlarmType.soundAndVibration,
    this.defaultAlarmSound = 'classic_bell',
    this.vibrationEnabled = true,
    this.volume = 0.7,
    this.gpsPollingMode = GpsPollingMode.continuous,
    this.customPollingInterval = const Duration(seconds: 10),
    this.mapStartView = MapStartView.currentGps,
    this.customStartLat,
    this.customStartLng,
    this.themeMode = ThemeMode.system,
    this.locale = 'hu',
  });

  Map<String, dynamic> toMap() => {
        'defaultAlarmType': defaultAlarmType.index,
        'defaultAlarmSound': defaultAlarmSound,
        'vibrationEnabled': vibrationEnabled,
        'volume': volume,
        'gpsPollingMode': gpsPollingMode.index,
        'customPollingIntervalSeconds': customPollingInterval.inSeconds,
        'mapStartView': mapStartView.index,
        'customStartLat': customStartLat,
        'customStartLng': customStartLng,
        'themeMode': themeMode.index,
        'locale': locale,
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) => AppSettings(
        defaultAlarmType: AlarmType.values[map['defaultAlarmType'] as int],
        defaultAlarmSound: map['defaultAlarmSound'] as String,
        vibrationEnabled: map['vibrationEnabled'] as bool,
        volume: (map['volume'] as num).toDouble(),
        gpsPollingMode: GpsPollingMode.values[map['gpsPollingMode'] as int],
        customPollingInterval:
            Duration(seconds: map['customPollingIntervalSeconds'] as int),
        mapStartView: MapStartView.values[map['mapStartView'] as int],
        customStartLat: (map['customStartLat'] as num?)?.toDouble(),
        customStartLng: (map['customStartLng'] as num?)?.toDouble(),
        themeMode: ThemeMode.values[map['themeMode'] as int],
        locale: map['locale'] as String,
      );

  AppSettings copyWith({
    AlarmType? defaultAlarmType,
    String? defaultAlarmSound,
    bool? vibrationEnabled,
    double? volume,
    GpsPollingMode? gpsPollingMode,
    Duration? customPollingInterval,
    MapStartView? mapStartView,
    double? customStartLat,
    double? customStartLng,
    ThemeMode? themeMode,
    String? locale,
  }) =>
      AppSettings(
        defaultAlarmType: defaultAlarmType ?? this.defaultAlarmType,
        defaultAlarmSound: defaultAlarmSound ?? this.defaultAlarmSound,
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        volume: volume ?? this.volume,
        gpsPollingMode: gpsPollingMode ?? this.gpsPollingMode,
        customPollingInterval:
            customPollingInterval ?? this.customPollingInterval,
        mapStartView: mapStartView ?? this.mapStartView,
        customStartLat: customStartLat ?? this.customStartLat,
        customStartLng: customStartLng ?? this.customStartLng,
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
      );
}
```

- [ ] **Step 5: Ask user to run tests**

```bash
proot-distro login ubuntu --user flutteruser -- bash -c "cd /home/flutteruser/flutterapps/gpsalarm && flutter test test/models/"
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add AlarmPoint and AppSettings data models with tests"
```

---

## Task 3: Providers — AlarmProvider + SettingsProvider

**Files:**
- Create: `gpsalarm/lib/providers/alarm_provider.dart`
- Create: `gpsalarm/lib/providers/settings_provider.dart`
- Create: `gpsalarm/test/providers/alarm_provider_test.dart`
- Create: `gpsalarm/test/providers/settings_provider_test.dart`

- [ ] **Step 1: Write AlarmProvider tests**

`test/providers/alarm_provider_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gpsalarm/models/alarm_point.dart';
import 'package:gpsalarm/providers/alarm_provider.dart';

void main() {
  group('AlarmProvider', () {
    late AlarmProvider provider;

    setUp(() {
      provider = AlarmProvider();
    });

    test('starts with empty list', () {
      expect(provider.alarmPoints, isEmpty);
      expect(provider.activeCount, 0);
    });

    test('addAlarmPoint adds to list', () {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      provider.addAlarmPoint(point);
      expect(provider.alarmPoints.length, 1);
      expect(provider.activeCount, 1);
    });

    test('enforces 50 alarm limit', () {
      for (int i = 0; i < 50; i++) {
        provider.addAlarmPoint(AlarmPoint(
          id: 'p$i',
          latitude: 47.0 + i * 0.01,
          longitude: 19.0,
          radiusMeters: 100,
          triggerType: TriggerType.distance,
        ));
      }
      expect(provider.canAddAlarm, false);
    });

    test('toggleActive switches isActive', () {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      provider.addAlarmPoint(point);
      provider.toggleActive('1');
      expect(provider.alarmPoints.first.isActive, false);
      expect(provider.activeCount, 0);
    });

    test('removeAlarmPoint removes from list', () {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      provider.addAlarmPoint(point);
      provider.removeAlarmPoint('1');
      expect(provider.alarmPoints, isEmpty);
    });

    test('updateAlarmPoint replaces existing', () {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      provider.addAlarmPoint(point);
      provider.updateAlarmPoint(point.copyWith(name: 'Work'));
      expect(provider.alarmPoints.first.name, 'Work');
    });

    test('findNearby returns point within 50m', () {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      provider.addAlarmPoint(point);
      final found = provider.findNearby(47.5001, 19.0001);
      expect(found, isNotNull);
      expect(found?.id, '1');
    });
  });
}
```

- [ ] **Step 2: Write AlarmProvider**

`lib/providers/alarm_provider.dart`:
```dart
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
      final distance = _haversineMeters(lat, lng, point.latitude, point.longitude);
      if (distance < duplicateThresholdMeters) return point;
    }
    return null;
  }

  static double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRad(double deg) => deg * pi / 180;
}
```

- [ ] **Step 3: Write SettingsProvider**

`lib/providers/settings_provider.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
```

- [ ] **Step 4: Ask user to run tests**

```bash
proot-distro login ubuntu --user flutteruser -- bash -c "cd /home/flutteruser/flutterapps/gpsalarm && flutter test"
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AlarmProvider and SettingsProvider with Hive persistence"
```

---

## Task 4: Services — GeocodingService + AlarmService

**Files:**
- Create: `gpsalarm/lib/services/geocoding_service.dart`
- Create: `gpsalarm/lib/services/alarm_service.dart`
- Create: `gpsalarm/lib/services/location_service.dart`
- Create: `gpsalarm/lib/services/audio_service.dart`
- Create: `gpsalarm/test/services/alarm_service_test.dart`
- Create: `gpsalarm/test/services/geocoding_service_test.dart`

- [ ] **Step 1: Write AlarmService tests**

`test/services/alarm_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gpsalarm/services/alarm_service.dart';

void main() {
  group('AlarmService', () {
    test('isWithinRadius returns true when inside', () {
      final result = AlarmService.isWithinRadius(
        userLat: 47.4979,
        userLng: 19.0402,
        pointLat: 47.4980,
        pointLng: 19.0403,
        radiusMeters: 500,
      );
      expect(result, true);
    });

    test('isWithinRadius returns false when outside', () {
      final result = AlarmService.isWithinRadius(
        userLat: 47.4979,
        userLng: 19.0402,
        pointLat: 47.51,
        pointLng: 19.06,
        radiusMeters: 500,
      );
      expect(result, false);
    });

    test('calculateEtaMinutes returns correct estimate', () {
      final eta = AlarmService.calculateEtaMinutes(
        distanceMeters: 5000,
        speedKmh: 60,
      );
      expect(eta, 5.0);
    });

    test('calculateEtaMinutes returns null for zero speed', () {
      final eta = AlarmService.calculateEtaMinutes(
        distanceMeters: 5000,
        speedKmh: 0,
      );
      expect(eta, isNull);
    });

    test('calculateAverageSpeed computes moving average', () {
      final speeds = [50.0, 60.0, 55.0, 65.0, 70.0];
      final avg = AlarmService.calculateAverageSpeed(speeds);
      expect(avg, 60.0);
    });

    test('distanceMeters calculates Haversine correctly', () {
      final d = AlarmService.distanceMeters(47.4979, 19.0402, 47.498, 19.041);
      expect(d, greaterThan(0));
      expect(d, lessThan(100));
    });
  });
}
```

- [ ] **Step 2: Write AlarmService**

`lib/services/alarm_service.dart`:
```dart
import 'dart:math';

class AlarmService {
  static double distanceMeters(
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

  static bool isWithinRadius({
    required double userLat,
    required double userLng,
    required double pointLat,
    required double pointLng,
    required double radiusMeters,
  }) {
    return distanceMeters(userLat, userLng, pointLat, pointLng) <= radiusMeters;
  }

  static double? calculateEtaMinutes({
    required double distanceMeters,
    required double speedKmh,
  }) {
    if (speedKmh < 1.0) return null;
    final speedMps = speedKmh * 1000 / 3600;
    return (distanceMeters / speedMps) / 60;
  }

  static double calculateAverageSpeed(List<double> recentSpeeds) {
    if (recentSpeeds.isEmpty) return 0;
    return recentSpeeds.reduce((a, b) => a + b) / recentSpeeds.length;
  }

  static double _toRad(double deg) => deg * pi / 180;
}
```

- [ ] **Step 3: Write GeocodingService**

`lib/services/geocoding_service.dart`:
```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingResult {
  final String displayName;
  final String? city;
  final String? country;
  final double latitude;
  final double longitude;

  GeocodingResult({
    required this.displayName,
    this.city,
    this.country,
    required this.latitude,
    required this.longitude,
  });
}

class GeocodingService {
  static const String _baseUrl =
      'https://photon.komoot.io/api/';
  static const Duration _debounce = Duration(milliseconds: 300);

  Timer? _debounceTimer;

  void search(String query, void Function(List<GeocodingResult>) onResults,
      void Function(String) onError) {
    _debounceTimer?.cancel();
    if (query.trim().length < 2) {
      onResults([]);
      return;
    }
    _debounceTimer = Timer(_debounce, () async {
      try {
        final uri = Uri.parse('$_baseUrl?q=${Uri.encodeComponent(query)}&limit=5&lang=hu');
        final response = await http.get(uri, headers: {
          'User-Agent': 'GPSAlarmApp/1.0',
        });
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final features = data['features'] as List;
          final results = features.map((f) {
            final props = f['properties'];
            final coords = f['geometry']['coordinates'];
            return GeocodingResult(
              displayName: props['name'] ?? '',
              city: props['city'] as String?,
              country: props['country'] as String?,
              latitude: (coords[1] as num).toDouble(),
              longitude: (coords[0] as num).toDouble(),
            );
          }).toList();
          onResults(results);
        } else {
          onError('connection_error');
        }
      } catch (e) {
        onError('connection_error');
      }
    });
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}
```

- [ ] **Step 4: Write LocationService stub**

`lib/services/location_service.dart`:
```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  final List<double> _recentSpeeds = [];
  static const int speedWindowSize = 5;

  Position? lastPosition;

  Future<bool> requestPermission() async {
    if (kIsWeb) {
      final permission = await Geolocator.requestPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    }
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      lastPosition = position;
      return position;
    } catch (e) {
      return null;
    }
  }

  void startTracking({
    required void Function(Position) onPosition,
    Duration? interval,
  }) {
    _positionSubscription?.cancel();
    final settings = interval != null
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            intervalDuration: interval,
          )
        : const LocationSettings(accuracy: LocationAccuracy.high);

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings)
            .listen((position) {
      lastPosition = position;
      _recordSpeed(position.speed * 3.6); // m/s to km/h
      onPosition(position);
    });
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _recordSpeed(double speedKmh) {
    _recentSpeeds.add(speedKmh);
    if (_recentSpeeds.length > speedWindowSize) {
      _recentSpeeds.removeAt(0);
    }
  }

  double get averageSpeedKmh {
    if (_recentSpeeds.isEmpty) return 0;
    return _recentSpeeds.reduce((a, b) => a + b) / _recentSpeeds.length;
  }

  void dispose() {
    stopTracking();
  }
}
```

- [ ] **Step 5: Write AudioService stub**

`lib/services/audio_service.dart`:
```dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();

  static const Map<String, String> hardcodedSounds = {
    'classic_bell': 'sounds/classic_bell.mp3',
    'radar_ping': 'sounds/radar_ping.mp3',
    'gentle_wake': 'sounds/gentle_wake.mp3',
  };

  Future<void> playAlarm(String soundName, {double volume = 0.7}) async {
    await _player.setVolume(volume);
    if (hardcodedSounds.containsKey(soundName)) {
      await _player.play(AssetSource(hardcodedSounds[soundName]!));
    } else {
      // Custom file path
      if (!kIsWeb) {
        await _player.play(DeviceFileSource(soundName));
      }
    }
  }

  Future<void> stop() async {
    await _player.stop();
  }

  void dispose() {
    _player.dispose();
  }
}
```

- [ ] **Step 6: Ask user to run tests**

```bash
proot-distro login ubuntu --user flutteruser -- bash -c "cd /home/flutteruser/flutterapps/gpsalarm && flutter test"
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add services - AlarmService, GeocodingService, LocationService, AudioService"
```

---

## Task 5: MapProvider + main.dart with Provider setup

**Files:**
- Create: `gpsalarm/lib/providers/map_provider.dart`
- Modify: `gpsalarm/lib/main.dart`

- [ ] **Step 1: Write MapProvider**

`lib/providers/map_provider.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../services/geocoding_service.dart';

class MapProvider extends ChangeNotifier {
  LatLng _center = const LatLng(47.4979, 19.0402); // Budapest default
  double _zoom = 13.0;
  bool _searchActive = false;
  List<GeocodingResult> _searchResults = [];
  String? _searchError;

  final GeocodingService _geocodingService = GeocodingService();

  LatLng get center => _center;
  double get zoom => _zoom;
  bool get searchActive => _searchActive;
  List<GeocodingResult> get searchResults => _searchResults;
  String? get searchError => _searchError;

  void setCenter(LatLng center) {
    _center = center;
    notifyListeners();
  }

  void setZoom(double zoom) {
    _zoom = zoom.clamp(3.0, 18.0);
    notifyListeners();
  }

  void zoomIn() => setZoom(_zoom + 1);
  void zoomOut() => setZoom(_zoom - 1);

  void toggleSearch() {
    _searchActive = !_searchActive;
    if (!_searchActive) {
      _searchResults = [];
      _searchError = null;
    }
    notifyListeners();
  }

  void search(String query) {
    _searchError = null;
    _geocodingService.search(
      query,
      (results) {
        _searchResults = results;
        _searchError = null;
        notifyListeners();
      },
      (error) {
        _searchResults = [];
        _searchError = error;
        notifyListeners();
      },
    );
  }

  void goToSearchResult(GeocodingResult result) {
    _center = LatLng(result.latitude, result.longitude);
    _zoom = 14.0;
    _searchActive = false;
    _searchResults = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _geocodingService.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 2: Rewrite main.dart**

`lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'providers/alarm_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/map_provider.dart';
import 'screens/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Hive.initFlutter();

  final alarmProvider = AlarmProvider();
  await alarmProvider.init();

  final settingsProvider = SettingsProvider();
  await settingsProvider.init();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('hu'), Locale('en')],
      path: 'lib/l10n',
      fallbackLocale: const Locale('hu'),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: alarmProvider),
          ChangeNotifierProvider.value(value: settingsProvider),
          ChangeNotifierProvider(create: (_) => MapProvider()),
        ],
        child: const GpsAlarmApp(),
      ),
    ),
  );
}

class GpsAlarmApp extends StatelessWidget {
  const GpsAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    return MaterialApp(
      title: 'GPS Alarm',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      themeMode: settings.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1976D2),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1976D2),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1a1a2e),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
```

- [ ] **Step 3: Create placeholder MapScreen so app compiles**

`lib/screens/map_screen.dart`:
```dart
import 'package:flutter/material.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'GPS Alarm - Map loading...',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Ask user to run app in Chrome to verify it builds**

```bash
bash ~/start-gpsalarm.sh
```
Expected: app starts, shows "GPS Alarm - Map loading..." text centered.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add MapProvider, wire up main.dart with providers and theming"
```

---

## Task 6: MapScreen — basic map with controls + user position

**Files:**
- Modify: `gpsalarm/lib/screens/map_screen.dart` (replace placeholder)
- Create: `gpsalarm/lib/widgets/map_controls.dart`
- Create: `gpsalarm/lib/widgets/user_location_marker.dart`

- [ ] **Step 1: Write MapScreen**

`lib/screens/map_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/map_provider.dart';
import '../providers/alarm_provider.dart';
import '../widgets/map_controls.dart';
import '../widgets/search_pill.dart';
import '../widgets/pin_marker.dart';
import '../widgets/radius_circle.dart';
import '../widgets/radius_popup.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng? _pendingTapPoint;
  LatLng? _fastAssignCenter;
  double? _fastAssignRadius;
  bool _isFastAssigning = false;

  @override
  Widget build(BuildContext context) {
    final mapProv = context.watch<MapProvider>();
    final alarmProv = context.watch<AlarmProvider>();

    return Scaffold(
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapProv.center,
              initialZoom: mapProv.zoom,
              onTap: (tapPosition, point) => _handleTap(context, point),
              onLongPress: (tapPosition, point) =>
                  _handleLongPressStart(point),
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                  mapProv.setCenter(position.center);
                  mapProv.setZoom(position.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.gpsalarm.app',
              ),
              // Radius circles
              CircleLayer(
                circles: alarmProv.alarmPoints
                    .map((p) => buildRadiusCircle(p))
                    .toList(),
              ),
              // Fast assign preview circle
              if (_isFastAssigning && _fastAssignCenter != null && _fastAssignRadius != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _fastAssignCenter!,
                      radius: _fastAssignRadius!,
                      useRadiusInMeter: true,
                      color: Colors.orange.withOpacity(0.15),
                      borderColor: Colors.orange.withOpacity(0.7),
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              // Pin markers
              MarkerLayer(
                markers: alarmProv.alarmPoints
                    .map((p) => buildPinMarker(
                          point: p,
                          onTap: () => _showEditPopup(context, p),
                        ))
                    .toList(),
              ),
            ],
          ),
          // Controls overlay
          MapControls(
            onMenuTap: () => Scaffold.of(context).openDrawer(),
            onZoomIn: () {
              mapProv.zoomIn();
              _mapController.move(mapProv.center, mapProv.zoom);
            },
            onZoomOut: () {
              mapProv.zoomOut();
              _mapController.move(mapProv.center, mapProv.zoom);
            },
            onSearchTap: () => mapProv.toggleSearch(),
            searchActive: mapProv.searchActive,
          ),
          // Search pill
          if (mapProv.searchActive)
            SearchPill(
              onResultSelected: (result) {
                mapProv.goToSearchResult(result);
                _mapController.move(
                  LatLng(result.latitude, result.longitude),
                  14.0,
                );
              },
            ),
          // Fast assign radius display
          if (_isFastAssigning && _fastAssignRadius != null)
            Positioned(
              bottom: 100,
              left: 50,
              right: 50,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_fastAssignRadius!.round()}m',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      drawer: _buildDrawer(context),
    );
  }

  void _handleTap(BuildContext context, LatLng point) {
    final alarmProv = context.read<AlarmProvider>();
    final existing = alarmProv.findNearby(point.latitude, point.longitude);
    if (existing != null) {
      _showEditPopup(context, existing);
    } else {
      _showCreatePopup(context, point);
    }
  }

  void _handleLongPressStart(LatLng point) {
    setState(() {
      _isFastAssigning = true;
      _fastAssignCenter = point;
      _fastAssignRadius = 100; // initial
    });
  }

  void _showCreatePopup(BuildContext context, LatLng point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RadiusPopup(
        latitude: point.latitude,
        longitude: point.longitude,
      ),
    );
  }

  void _showEditPopup(BuildContext context, dynamic alarmPoint) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RadiusPopup(
        latitude: alarmPoint.latitude,
        longitude: alarmPoint.longitude,
        existingPoint: alarmPoint,
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return const Drawer(
      child: SafeArea(
        child: Center(
          child: Text('Settings - TODO'),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Write MapControls widget**

`lib/widgets/map_controls.dart`:
```dart
import 'package:flutter/material.dart';

class MapControls extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onSearchTap;
  final bool searchActive;

  const MapControls({
    super.key,
    required this.onMenuTap,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onSearchTap,
    required this.searchActive,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? Colors.grey[900]!.withOpacity(0.92)
        : Colors.white.withOpacity(0.92);
    final iconColor = isDark ? Colors.white : Colors.grey[800]!;

    return Stack(
      children: [
        // Hamburger - top left
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 12,
          child: _ControlButton(
            onTap: onMenuTap,
            bgColor: bgColor,
            child: Icon(Icons.menu, color: iconColor, size: 24),
          ),
        ),
        // Zoom buttons - right side above FAB
        Positioned(
          bottom: 140,
          right: 16,
          child: Column(
            children: [
              _ControlButton(
                onTap: onZoomIn,
                bgColor: bgColor,
                child: Icon(Icons.add, color: iconColor, size: 24),
              ),
              const SizedBox(height: 4),
              _ControlButton(
                onTap: onZoomOut,
                bgColor: bgColor,
                child: Icon(Icons.remove, color: iconColor, size: 24),
              ),
            ],
          ),
        ),
        // FAB - bottom right
        Positioned(
          bottom: 24,
          right: 16,
          child: GestureDetector(
            onTap: onSearchTap,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: searchActive
                      ? [Colors.red[400]!, Colors.red[800]!]
                      : [Colors.blue[400]!, Colors.blue[800]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (searchActive ? Colors.red : Colors.blue)
                        .withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                searchActive ? Icons.close : Icons.search,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color bgColor;
  final Widget child;

  const _ControlButton({
    required this.onTap,
    required this.bgColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}
```

- [ ] **Step 3: Write UserLocationMarker widget**

`lib/widgets/user_location_marker.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

Marker buildUserLocationMarker(LatLng position) {
  return Marker(
    point: position,
    width: 24,
    height: 24,
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2196F3).withOpacity(0.4),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 4: Create placeholder widgets**

Create minimal stubs for `SearchPill`, `PinMarker`, `RadiusCircle`, `RadiusPopup` so the app compiles:

`lib/widgets/search_pill.dart` — empty container
`lib/widgets/pin_marker.dart` — returns basic Marker
`lib/widgets/radius_circle.dart` — returns basic CircleMarker
`lib/widgets/radius_popup.dart` — empty bottom sheet

- [ ] **Step 5: Ask user to run app in Chrome**

```bash
bash ~/start-gpsalarm.sh
```
Expected: OpenStreetMap visible, hamburger button top-left, zoom buttons right, FAB bottom-right.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add MapScreen with OSM tiles, controls, and drawer skeleton"
```

---

## Task 7: SearchPill widget

**Files:**
- Modify: `gpsalarm/lib/widgets/search_pill.dart`

- [ ] **Step 1: Implement SearchPill**

`lib/widgets/search_pill.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/map_provider.dart';
import '../services/geocoding_service.dart';

class SearchPill extends StatefulWidget {
  final void Function(GeocodingResult) onResultSelected;

  const SearchPill({super.key, required this.onResultSelected});

  @override
  State<SearchPill> createState() => _SearchPillState();
}

class _SearchPillState extends State<SearchPill> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapProv = context.watch<MapProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      bottom: 90,
      left: 16,
      right: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Text input pill
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.search, color: Colors.grey[500], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: tr('search_city'),
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey[400]),
                    ),
                    onChanged: (query) => mapProv.search(query),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _controller.clear();
                      mapProv.search('');
                    },
                    child: Icon(Icons.close, color: Colors.grey[400], size: 20),
                  ),
                const SizedBox(width: 12),
              ],
            ),
          ),
          // Results dropdown
          if (mapProv.searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: mapProv.searchResults.map((result) {
                  return InkWell(
                    onTap: () => widget.onResultSelected(result),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 18, color: Colors.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(result.displayName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                if (result.country != null)
                                  Text(
                                    [result.city, result.country]
                                        .whereType<String>()
                                        .join(', '),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500]),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          // Error message
          if (mapProv.searchError != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                tr(mapProv.searchError!),
                style: TextStyle(color: Colors.red[400], fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Test in Chrome** — FAB tap opens pill, typing shows results, tap result moves map.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add SearchPill with Photon geocoding and debounced search"
```

---

## Task 8: PinMarker + RadiusCircle widgets

**Files:**
- Modify: `gpsalarm/lib/widgets/pin_marker.dart`
- Modify: `gpsalarm/lib/widgets/radius_circle.dart`

- [ ] **Step 1: Implement PinMarker**

`lib/widgets/pin_marker.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/alarm_point.dart';

Marker buildPinMarker({
  required AlarmPoint point,
  required VoidCallback onTap,
}) {
  final isActive = point.isActive;
  final color = isActive ? Colors.red : Colors.grey;
  final label = point.triggerType == TriggerType.distance
      ? _formatDistance(point.radiusMeters)
      : '${point.timeTrigger?.inMinutes ?? 0}min';

  return Marker(
    point: LatLng(point.latitude, point.longitude),
    width: 60,
    height: 60,
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on,
            color: isActive ? color : Colors.grey[400],
            size: 32,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: (isActive ? color : Colors.grey).withOpacity(0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _formatDistance(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }
  return '${meters.round()}m';
}
```

- [ ] **Step 2: Implement RadiusCircle**

`lib/widgets/radius_circle.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/alarm_point.dart';

CircleMarker buildRadiusCircle(AlarmPoint point) {
  final isActive = point.isActive;
  final color = isActive ? Colors.red : Colors.grey;

  return CircleMarker(
    point: LatLng(point.latitude, point.longitude),
    radius: point.radiusMeters,
    useRadiusInMeter: true,
    color: color.withOpacity(isActive ? 0.12 : 0.05),
    borderColor: color.withOpacity(isActive ? 0.6 : 0.3),
    borderStrokeWidth: isActive ? 2 : 1,
  );
}
```

- [ ] **Step 3: Test in Chrome** — verify pins and circles render on map.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add PinMarker and RadiusCircle map widgets"
```

---

## Task 9: RadiusPopup — alarm creation/edit

**Files:**
- Modify: `gpsalarm/lib/widgets/radius_popup.dart`

- [ ] **Step 1: Implement RadiusPopup**

`lib/widgets/radius_popup.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import '../models/alarm_point.dart';
import '../providers/alarm_provider.dart';

class RadiusPopup extends StatefulWidget {
  final double latitude;
  final double longitude;
  final AlarmPoint? existingPoint;

  const RadiusPopup({
    super.key,
    required this.latitude,
    required this.longitude,
    this.existingPoint,
  });

  @override
  State<RadiusPopup> createState() => _RadiusPopupState();
}

class _RadiusPopupState extends State<RadiusPopup> {
  late TextEditingController _nameController;
  late TriggerType _triggerType;
  late double _radiusMeters;
  late int _timeMinutes;

  @override
  void initState() {
    super.initState();
    final p = widget.existingPoint;
    _nameController = TextEditingController(text: p?.name ?? '');
    _triggerType = p?.triggerType ?? TriggerType.distance;
    _radiusMeters = p?.radiusMeters ?? 500;
    _timeMinutes = p?.timeTrigger?.inMinutes ?? 10;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1a1a2e) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('new_alarm_point'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.latitude.toStringAsFixed(4)}° N, ${widget.longitude.toStringAsFixed(4)}° E',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            // Name field
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: tr('name_optional'),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            // Trigger type toggle
            Text(tr('trigger_type'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Row(
              children: [
                _TriggerChip(
                  label: tr('distance'),
                  icon: Icons.straighten,
                  selected: _triggerType == TriggerType.distance,
                  onTap: () =>
                      setState(() => _triggerType = TriggerType.distance),
                ),
                const SizedBox(width: 8),
                _TriggerChip(
                  label: tr('time'),
                  icon: Icons.timer,
                  selected: _triggerType == TriggerType.time,
                  onTap: () => setState(() => _triggerType = TriggerType.time),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Distance or time slider
            if (_triggerType == TriggerType.distance) ...[
              Text(tr('radius_meters'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _radiusMeters,
                      min: 100,
                      max: 5000,
                      divisions: 49,
                      label: '${_radiusMeters.round()}m',
                      onChanged: (v) => setState(() => _radiusMeters = v),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text('${_radiusMeters.round()}m',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ] else ...[
              Text(tr('minutes'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _timeMinutes.toDouble(),
                      min: 5,
                      max: 120,
                      divisions: 23,
                      label: '$_timeMinutes min',
                      onChanged: (v) =>
                          setState(() => _timeMinutes = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text('$_timeMinutes min',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(tr('cancel')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _save(context),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(tr('save')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save(BuildContext context) {
    final alarmProv = context.read<AlarmProvider>();

    if (!alarmProv.canAddAlarm && widget.existingPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('max_alarms_reached'))),
      );
      return;
    }

    final point = AlarmPoint(
      id: widget.existingPoint?.id ?? const Uuid().v4(),
      name: _nameController.text.isEmpty ? null : _nameController.text,
      latitude: widget.latitude,
      longitude: widget.longitude,
      radiusMeters: _triggerType == TriggerType.distance ? _radiusMeters : 0,
      triggerType: _triggerType,
      timeTrigger: _triggerType == TriggerType.time
          ? Duration(minutes: _timeMinutes)
          : null,
    );

    if (widget.existingPoint != null) {
      alarmProv.updateAlarmPoint(point);
    } else {
      alarmProv.addAlarmPoint(point);
    }
    Navigator.pop(context);
  }
}

class _TriggerChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TriggerChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[300]!,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Test in Chrome** — tap map, popup appears, save creates pin with radius circle.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add RadiusPopup for alarm creation and editing"
```

---

## Task 10: Fast Assign (long tap + swipe)

**Files:**
- Modify: `gpsalarm/lib/screens/map_screen.dart`

- [ ] **Step 1: Implement GestureDetector for long press + pan** — track swipe distance, convert to meters using zoom level, show preview circle, save on release.

- [ ] **Step 2: Add toast confirmation** — SnackBar "Fast alarm - Xm".

- [ ] **Step 3: Test in Chrome** — long tap + drag creates circle, release saves.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add fast assign via long tap + swipe"
```

---

## Task 11: Hamburger Menu (Drawer) + Settings Screens

**Files:**
- Create: `gpsalarm/lib/screens/settings_screen.dart`
- Create: `gpsalarm/lib/screens/alarm_settings_screen.dart`
- Create: `gpsalarm/lib/screens/gps_settings_screen.dart`
- Create: `gpsalarm/lib/screens/map_settings_screen.dart`
- Modify: `gpsalarm/lib/screens/map_screen.dart` — replace drawer stub

- [ ] **Step 1: Write SettingsScreen** — drawer with all menu items from spec.

- [ ] **Step 2: Write AlarmSettingsScreen** — alarm type radio, sound list + preview, vibration toggle, volume slider.

- [ ] **Step 3: Write GpsSettingsScreen** — polling mode toggle, custom interval picker.

- [ ] **Step 4: Write MapSettingsScreen** — start view selection.

- [ ] **Step 5: Add theme toggle and language switcher** to drawer.

- [ ] **Step 6: Test in Chrome** — all settings screens navigate and persist changes.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add hamburger menu, all settings screens"
```

---

## Task 12: AlarmListScreen

**Files:**
- Create: `gpsalarm/lib/screens/alarm_list_screen.dart`
- Create: `gpsalarm/lib/widgets/alarm_list_tile.dart`

- [ ] **Step 1: Write AlarmListTile** — pin icon, name, radius/time, coordinates, active toggle.

- [ ] **Step 2: Write AlarmListScreen** — list of tiles, swipe to delete (Dismissible), tap to edit, header with active count.

- [ ] **Step 3: Test in Chrome** — create alarms, view in list, toggle, delete, edit.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add AlarmListScreen with toggle, swipe delete, and edit"
```

---

## Task 13: GPS Monitoring + Alarm Triggering

**Files:**
- Modify: `gpsalarm/lib/screens/map_screen.dart` — start GPS monitoring
- Modify: `gpsalarm/lib/services/location_service.dart` — integrate with alarm checking
- Modify: `gpsalarm/lib/services/audio_service.dart` — trigger alarm sounds

- [ ] **Step 1: Wire LocationService into MapScreen** — start tracking on app launch, check all active alarms on each position update.

- [ ] **Step 2: Implement proximity check loop** — for each active alarm, check distance or ETA trigger, fire alarm when met, auto-deactivate point.

- [ ] **Step 3: Implement alarm sound + vibration playback** on trigger.

- [ ] **Step 4: Test on Android** — user walks near a pin, alarm fires.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add GPS monitoring and alarm trigger logic"
```

---

## Task 14: Alarm Trigger UI — notifications + full-screen alarm

**Files:**
- Create: `gpsalarm/lib/screens/alarm_trigger_screen.dart`
- Modify: `gpsalarm/lib/services/audio_service.dart` — add notification delivery

- [ ] **Step 1: Implement AlarmTriggerScreen**

`lib/screens/alarm_trigger_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/alarm_point.dart';

class AlarmTriggerScreen extends StatelessWidget {
  final AlarmPoint alarmPoint;
  final double distanceMeters;
  final VoidCallback onDismiss;

  const AlarmTriggerScreen({
    super.key,
    required this.alarmPoint,
    required this.distanceMeters,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.alarm, color: Colors.red, size: 80),
                const SizedBox(height: 24),
                Text(
                  alarmPoint.name ?? tr('no_name'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${distanceMeters.round()}m',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 48),
                // Slide to dismiss
                GestureDetector(
                  onHorizontalDragEnd: (_) => onDismiss(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.withOpacity(0.5)),
                    ),
                    child: Center(
                      child: Text(
                        '← ${tr("dismiss")} →',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Add notification delivery to AudioService**

Update `lib/services/audio_service.dart` to use `flutter_local_notifications` for notification-only mode. Initialize notification channel on startup, show notification with alarm name and distance when triggered.

- [ ] **Step 3: Wire alarm trigger into MapScreen/alarm check loop**

In Task 13's proximity check, based on `AlarmType`:
- `soundAndVibration`: play sound + vibrate + show notification with dismiss
- `notificationOnly`: show notification only
- `fullScreenAlarm`: navigate to `AlarmTriggerScreen`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add alarm trigger UI - notifications and full-screen dismiss"
```

---

## Task 15: Progressive Permissions + Rationale Dialogs

**Files:**
- Create: `gpsalarm/lib/services/permission_service.dart`
- Create: `gpsalarm/lib/widgets/permission_banner.dart`
- Modify: `gpsalarm/lib/screens/map_screen.dart` — request foreground location on launch
- Modify: `gpsalarm/lib/widgets/radius_popup.dart` — request background location + notifications on first alarm

- [ ] **Step 1: Implement PermissionService**

`lib/services/permission_service.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class PermissionService {
  static Future<bool> requestForegroundLocation() async {
    if (kIsWeb) {
      final permission = await Geolocator.requestPermission();
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    }
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  static Future<bool> requestBackgroundLocation() async {
    if (kIsWeb) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always;
  }

  static Future<bool> checkForegroundLocation() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  static Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }
}
```

- [ ] **Step 2: Implement PermissionBanner widget**

`lib/widgets/permission_banner.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/permission_service.dart';

class PermissionBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const PermissionBanner({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.orange.withOpacity(0.9),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => PermissionService.openAppSettings(),
            child: Text(tr('open_settings'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Wire permissions into MapScreen**

- On MapScreen init: call `PermissionService.requestForegroundLocation()`
- If denied: show `PermissionBanner` at top of screen
- On first alarm creation (in RadiusPopup save): call `requestBackgroundLocation()` with rationale dialog

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add progressive permission flow with rationale dialogs"
```

---

## Task 16: Web Platform Graceful Degradation

**Files:**
- Create: `gpsalarm/lib/services/platform_service.dart`
- Modify: `gpsalarm/lib/screens/alarm_settings_screen.dart` — hide unavailable options on web
- Modify: `gpsalarm/lib/widgets/radius_popup.dart` — disable time trigger on web if no GPS

- [ ] **Step 1: Implement PlatformService**

`lib/services/platform_service.dart`:
```dart
import 'package:flutter/foundation.dart';

class PlatformService {
  static bool get isWeb => kIsWeb;
  static bool get isMobile => !kIsWeb;

  static bool get supportsBackgroundLocation => isMobile;
  static bool get supportsVibration => isMobile;
  static bool get supportsFilePicker => isMobile;
  static bool get supportsFullScreenAlarm => isMobile;
  static bool get supportsNotifications => isMobile;
}
```

- [ ] **Step 2: Update AlarmSettingsScreen**

- Hide "Full screen alarm" option on web
- Hide "Custom file" option on web
- Hide vibration toggle on web
- Show tooltip "Not available on web" for disabled options

- [ ] **Step 3: Update other screens**

- GpsSettingsScreen: show warning "Background monitoring not available on web"
- RadiusPopup: all features work on web, but show info about foreground-only

- [ ] **Step 4: Test in Chrome** — verify hidden/disabled elements.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add web platform graceful degradation"
```

---

## Task 17: Android Foreground Service for Background Monitoring

**Files:**
- Modify: `gpsalarm/lib/services/location_service.dart` — add foreground service notification
- Modify: `gpsalarm/android/app/src/main/AndroidManifest.xml` — add permissions

- [ ] **Step 1: Add Android manifest permissions**

Add to AndroidManifest.xml:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.VIBRATE"/>
```

- [ ] **Step 2: Setup foreground notification in LocationService**

Use `flutter_local_notifications` to show a persistent notification when GPS monitoring is active:
- Title: "GPS Alarm"
- Body: "Monitoring X locations" (updated when alarm count changes)
- Ongoing: true, not dismissable

- [ ] **Step 3: Test on Android device** — verify persistent notification appears and location tracking works in background.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add Android foreground service for background GPS monitoring"
```

---

## Task 18: Dark/Light Theme + Polish

**Files:**
- All widget files — ensure they respect theme
- `gpsalarm/lib/main.dart` — theme finalization

- [ ] **Step 1: Verify all screens respect dark/light mode** — test by toggling theme in settings.

- [ ] **Step 2: Polish map controls** — ensure glass effect on light mode, dark on dark mode.

- [ ] **Step 3: Test both themes in Chrome and Android.**

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: polish dark/light theme across all screens"
```

---

## Summary

| Task | Description | Key files |
|------|-------------|-----------|
| 1 | Project setup | pubspec.yaml, l10n, folders |
| 2 | Data models | alarm_point.dart, app_settings.dart |
| 3 | Providers | alarm_provider.dart, settings_provider.dart |
| 4 | Services | alarm_service.dart, geocoding_service.dart, location_service.dart |
| 5 | MapProvider + main.dart | map_provider.dart, main.dart |
| 6 | MapScreen + controls + user position | map_screen.dart, map_controls.dart, user_location_marker.dart |
| 7 | SearchPill | search_pill.dart |
| 8 | PinMarker + RadiusCircle | pin_marker.dart, radius_circle.dart |
| 9 | RadiusPopup | radius_popup.dart |
| 10 | Fast assign | map_screen.dart (gesture) |
| 11 | Settings screens | settings_screen.dart, alarm/gps/map settings |
| 12 | AlarmListScreen | alarm_list_screen.dart |
| 13 | GPS monitoring + trigger | location_service.dart, map_screen.dart |
| 14 | Alarm trigger UI | alarm_trigger_screen.dart, notifications |
| 15 | Progressive permissions | permission_service.dart, permission_banner.dart |
| 16 | Web graceful degradation | platform_service.dart |
| 17 | Android foreground service | AndroidManifest.xml, location_service.dart |
| 18 | Theme polish | all files |
