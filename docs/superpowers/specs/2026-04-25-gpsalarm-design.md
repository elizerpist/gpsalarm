# GPS Alarm - Design Specification

## Overview

GPS-based proximity alarm app. The user places pins on a map and gets alerted when approaching (distance-based) or when estimated arrival time is reached (time-based, calculated from GPS speed). Built with Flutter, targeting Android, iOS, and Web (Chrome for development).

## Platforms

- **Android** — primary native target, tested on physical device
- **iOS** — native build support
- **Web (Chrome)** — development/testing via `flutter run -d web-server`

## Architecture

Flat, simple structure with Provider state management:

```
lib/
  main.dart
  models/            — AlarmPoint, AppSettings
  providers/         — MapProvider, AlarmProvider, SettingsProvider
  screens/           — MapScreen, SettingsScreen, AlarmListScreen
  widgets/           — MapControls, SearchPill, RadiusPopup, PinMarker
  services/          — LocationService, AlarmService, AudioService
  l10n/              — hu.json, en.json
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_map` | OpenStreetMap tile rendering |
| `latlong2` | Coordinate math, distance calculations |
| `http` | Nominatim/Photon geocoding API calls |
| `geolocator` | GPS position tracking (native) |
| `hive` / `hive_flutter` | Local storage for alarm points and settings |
| `provider` | State management |
| `audioplayers` | Alarm sound playback |
| `flutter_local_notifications` | Push notifications when app is in background |
| `vibration` | Vibration control |
| `file_picker` | Custom alarm sound file selection |
| `flutter_localization` | i18n (Hungarian + English) |

## Data Models

### AlarmPoint

```dart
class AlarmPoint {
  String id;
  String? name;
  double latitude;
  double longitude;
  double radiusMeters;         // distance trigger radius
  Duration? timeTrigger;       // time-based trigger (e.g. 30 min)
  TriggerType triggerType;     // distance | time
  AssignMode assignMode;       // tap (detailed) | fastAssign (long tap+swipe)
  bool isActive;
  String? customAlarmSound;    // null = use global default
  AlarmType? customAlarmType;  // null = use global default
  DateTime createdAt;
}

enum TriggerType { distance, time }
enum AssignMode { tap, fastAssign }
enum AlarmType { soundAndVibration, notificationOnly, fullScreenAlarm }
```

### AppSettings

```dart
class AppSettings {
  // Alarm defaults
  AlarmType defaultAlarmType;      // soundAndVibration | notificationOnly | fullScreenAlarm
  String defaultAlarmSound;        // hardcoded ring name or custom file path
  bool vibrationEnabled;
  double volume;                   // 0.0 - 1.0

  // GPS
  GpsPollingMode gpsPollingMode;   // continuous | custom
  Duration customPollingInterval;  // e.g. 10s, 30s, 1min, 5min

  // Map
  MapStartView mapStartView;      // currentGps | lastPosition | custom
  LatLng? customStartPosition;

  // Appearance
  ThemeMode themeMode;             // light | dark | system

  // Language
  String locale;                   // 'hu' | 'en'
}
```

## Screens & UI

### 1. MapScreen (main screen)

Full-screen OpenStreetMap filling the entire viewport. UI elements float on top:

- **Top-left:** Hamburger menu button (44x44, white/glass background, rounded)
- **Right side, above FAB:** Zoom +/- buttons (44x44 each, stacked vertically)
- **Bottom-right:** FAB button (56x56, blue gradient, search icon)
- **On map:** Alarm point pins with radius circle visualization + user position (blue dot)

**Interactions:**

1. **Tap** on map → red pin (����) appears → popup slides up with:
   - Name field (optional)
   - Trigger type toggle: Distance | Time
   - Distance mode: radius input (number field + slider, 100m–5km)
   - Time mode: minutes input (number field + slider, 5–120 min)
   - Cancel / Save buttons

2. **Long tap + swipe (fast assign)** → orange pin (📌) appears at touch point → circle grows as finger swipes outward → radius = swipe distance → release = alarm saved with default distance trigger. A bottom toast confirms: "Fast alarm - 350m". Tap the pin later to edit details.

**Pin visualization:**
- Tap pins: red (📍) with green circle border
- Fast assign pins: orange (📌) with orange circle border
- Radius circle: semi-transparent fill + colored border
- Distance label below pin (e.g. "500m", "1km")
- Inactive pins: grayed out, dashed circle

### 2. Search flow

FAB tap → search text pill slides up from bottom-right (left of FAB):
- Text input with search icon and X clear button
- Dropdown results appear below as user types
- Geocoding via Nominatim/Photon API (free, OpenStreetMap-based)
- 300ms debounce on keystroke
- Result tap → map animates to location, search pill closes
- FAB changes to red X (close) while search is active

### 3. Hamburger menu (drawer)

Left-side drawer, dark themed:

- **App header:** "GPS Alarm" + version
- **Mentett helyek / Saved locations** → AlarmListScreen
- **Alarm beallitasok / Alarm settings** → alarm type, sound, vibration, volume
- **GPS beallitasok / GPS settings** → polling mode, custom interval
- **Terkep beallitasok / Map settings** → start view preference
- **Megjelenes / Appearance** → light / dark / system theme
- **Nyelv / Language** → Hungarian / English

### 4. Alarm settings (sub-screen)

- **Alarm type:** radio selection — Sound+Vibration | Notification only | Full screen alarm
- **Alarm sound:** list of hardcoded ringtones (Classic Bell, Radar Ping, Gentle Wake) + "Custom file" option (file_picker). Each has a play preview button.
- **Vibration:** toggle switch
- **Volume:** slider with speaker icons

### 5. AlarmListScreen (saved locations)

List of all alarm points:
- Each card: pin icon, name (or "No name"), radius/time info, trigger type, coordinates, active/inactive toggle
- Swipe left to delete
- Tap to edit (opens the same popup as tap-create, pre-filled)
- Header shows count of active alarms

### 6. Alarm trigger screens

When an alarm triggers:
- **Sound+Vibration:** audio plays + device vibrates, notification with dismiss button
- **Notification only:** standard push notification with alarm name and distance
- **Full screen alarm:** lock-screen overlay, large alarm name + distance, slide to dismiss

## GPS & Battery Management

- **Polling modes:** Continuous (real-time GPS stream) or custom interval (10s, 30s, 1min, 5min)
- User configures in GPS settings
- Background execution via platform-specific foreground service (Android) / background location (iOS)
- Web: uses browser Geolocation API with watchPosition

**Time-based trigger calculation:**
- Track GPS speed over last N readings (moving average)
- Calculate ETA: distance_to_point / average_speed
- Trigger when ETA <= configured time threshold
- Fall back to distance trigger if speed is 0 or unreliable

## Map Provider

- **Tiles:** OpenStreetMap via flutter_map
- **Geocoding (search):** Nominatim or Photon API (free, no API key)
- **Distance calculation:** Haversine formula via latlong2 package
- No API keys required, fully free

## Data Persistence

- **Hive** for all local storage:
  - `alarmPointsBox` — AlarmPoint objects
  - `settingsBox` — AppSettings singleton
- No backend, no cloud sync — fully offline-capable

## Localization

- Hungarian (default) + English
- JSON-based l10n files
- Switchable from hamburger menu, persisted in settings

## Theme

- Light mode: white backgrounds, Material 3 style, blue accent (#1976D2)
- Dark mode: dark backgrounds (#1a1a2e), lighter text, same blue accent
- System mode: follows device setting
- Map controls: semi-transparent white/glass background in light mode, dark in dark mode
