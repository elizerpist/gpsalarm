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
| `vibration` | Vibration control (mobile only, no-op on web) |
| `file_picker` | Custom alarm sound file selection |
| `easy_localization` | i18n (Hungarian + English, JSON-based) |

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
  bool isActive;
  String? customAlarmSound;    // null = use global default
  AlarmType? customAlarmType;  // null = use global default
  DateTime createdAt;
}

enum TriggerType { distance, time }
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

2. **Long tap + swipe (fast assign)** → orange pin (📌) appears at touch point → circle grows as finger swipes outward → radius is calculated from swipe pixel distance converted to meters using the current map zoom level (pixels × meters-per-pixel at zoom) → release = alarm saved with default distance trigger. A bottom toast confirms: "Fast alarm - 350m". Tap the pin later to edit details.

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
- **Full screen alarm:** lock-screen overlay, large alarm name + distance, slide to dismiss (Android: requires `USE_FULL_SCREEN_INTENT` permission; iOS: uses notification with critical alert)

**After dismissal:** the alarm point automatically deactivates (isActive = false). User must manually re-enable it from the list or map pin. No snooze — this is a location alarm, not a recurring alarm.

**Maximum alarm points:** 50 active alarms. Beyond that, user must deactivate existing ones. This prevents excessive battery drain from monitoring too many geofences.

## GPS & Battery Management

- **Polling modes:** Continuous (real-time GPS stream) or custom interval (10s, 30s, 1min, 5min)
- User configures in GPS settings
- **Android background:** foreground service with persistent notification ("GPS Alarm is monitoring X locations")
- **iOS background:** `allowBackgroundLocationUpdates` with significant location changes for battery efficiency
- **Web:** browser Geolocation API with watchPosition (foreground only, no background support — shows warning)

**Time-based trigger calculation:**
- Track GPS speed over last 5 readings (moving average window = 5)
- Calculate ETA: distance_to_point / average_speed
- Trigger when ETA <= configured time threshold
- Fall back to distance trigger if speed is 0 or unreliable (< 1 km/h for > 30 seconds)

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

## Permissions

App requests permissions progressively (not all at once on first launch):

- **Location (foreground):** requested on first app open, required for map "my location" and alarm monitoring
- **Location (background):** requested when user creates first alarm point — explained with rationale dialog ("GPS Alarm needs background location to alert you when you're near your saved locations")
- **Notifications:** requested when user creates first alarm — needed for alarm delivery
- **File access:** requested only when user taps "Custom file" in alarm sound settings

**Permission denied handling:** show inline banner explaining why the permission is needed, with "Open Settings" button. App remains usable without background location (alarms only work in foreground) and without notifications (only in-app alarm).

## Platform-Specific Limitations (Web)

Web (Chrome) is for development/testing. Known limitations:
- No background GPS monitoring — alarms only work while tab is active
- No vibration API on desktop browsers
- No file picker for custom alarm sounds (use hardcoded only)
- No full-screen alarm overlay
- No push notifications without service worker setup
- These features gracefully degrade: unavailable options are hidden or shown as disabled with tooltip

## Error Handling

- **Geocoding failure:** show "No results found" or "Connection error, try again" in search dropdown
- **GPS unavailable:** show banner on map "GPS not available" with retry button
- **Duplicate pin prevention:** if user taps within 50m of existing pin, show existing pin's popup instead of creating new one
