# Vector Map Long Press + Swipe — Problem & Solution

## The Problem

On the MapLibre vector map (Android PlatformView), the "long press → immediate swipe to grow radius" gesture didn't work. Three separate issues:

### 1. Map scrolls instead of radius growing

When the user long-pressed and swiped without releasing:
- `MapEventLongClick` (native event) fired after 500ms
- Flutter's `_onLongPress` handler called `setState` to show the overlay
- But the **native PlatformView already owned the pointer** from the initial touch
- The overlay `Listener` appeared mid-touch but **never received `onPointerDown`** for the ongoing touch
- The native MapLibre continued panning the map underneath
- The overlay circle appeared stuck at a fixed screen position while the map scrolled

### 2. Circle appeared at screen center

The screen position was calculated from the camera center + offset formula:
```
dx = dLng * cos(camLat) * (111320 / metersPerPx)
dy = -dLat * (110540 / metersPerPx)
screenCenter = Offset(screenWidth/2 + dx, screenHeight/2 + dy)
```

This produced incorrect values because `_controller?.camera` returned stale data at event time. A persistent `Listener(behavior: translucent)` was added to capture the pointer position, but PlatformViews may consume events at the native level before Flutter's hit testing.

### 3. No dual function (inside circle = radius, outside = map scroll)

The overlay used `HitTestBehavior.opaque` to block all map gestures. With a PlatformView, it's not possible to selectively pass events through — the native view processes touches at the platform level, bypassing Flutter's hit test system.

---

## Root Cause

**PlatformView gesture ownership**: MapLibre renders as a native Android view (`AndroidView`). Touch events go directly to the native layer before Flutter can intercept them. Once the native view starts tracking a pointer (e.g., for panning), Flutter cannot "steal" that pointer mid-touch.

The `MapEventLongClick` event fires FROM the native layer TO Flutter — it's a notification, not a gesture handoff. The native layer keeps the pointer for its own gesture handling.

---

## The Solution ✅

### GestureDetector wraps MapLibreMap

Replace `MapEventLongClick` with Flutter's `GestureDetector` wrapping the `MapLibreMap` widget:

```dart
GestureDetector(
  onLongPressStart: (details) {
    _assignScreenCenter = details.localPosition;
    _isDraggingRadius = true;
    final geo = _screenToGeo(details.localPosition);
    _startAssign(geo.lat, geo.lng);
  },
  onLongPressMoveUpdate: (details) {
    // Update radius from swipe distance
    final dist = (details.localPosition - _assignScreenCenter!).distance;
    _assignRadius = (dist * metersPerPx).clamp(100, 5000);
    _radiusNotifier.value = _currentRadiusPx;
  },
  onLongPressEnd: (details) {
    _isDraggingRadius = false;
  },
  child: MapLibreMap(...),
)
```

### Why this works

1. **Flutter wins the gesture arena**: `GestureDetector` with `onLongPressStart` competes in Flutter's gesture arena. When it recognizes a long press (after ~500ms of holding without movement), Flutter claims the pointer. The PlatformView does NOT start panning because Flutter won the arena first.

2. **Screen position from Flutter**: `details.localPosition` gives the exact screen position from the Flutter gesture system — no camera calculation needed, no stale data.

3. **Continuous updates**: `onLongPressMoveUpdate` fires for every pointer movement AFTER the long press is recognized, providing the same pointer data for radius calculation.

4. **Geo position from camera**: `_screenToGeo()` converts the screen position to geographic coordinates using the camera center + zoom level. This is the reverse of the screen-from-camera calculation:
```dart
dLng = dx * metersPerPx / (111320 * cos(camLat))
dLat = -dy * metersPerPx / 110540
geo = (camLat + dLat, camLng + dLng)
```

### Single tap flow (unchanged)

Single tap still uses `MapEventClick` from the native layer, which provides accurate geographic coordinates. The tap → assign flow works because:
1. User taps and releases → no gesture conflict
2. `MapEventClick` fires with correct lat/lng
3. Overlay appears for the NEXT touch (separate pointer)

### Architecture

```
GestureDetector (long press)
  └── MapLibreMap (PlatformView)
        ├── MapEventClick → _onTap (single tap)
        └── MapEventMoveCamera → zoom tracking

Stack overlay (when _isAssigning):
  ├── Listener (opaque) + CustomPaint (radius circle)
  └── AlarmCard
```

### Limitations

- **No map pan during assign**: The overlay is `HitTestBehavior.opaque`, blocking all map interaction. This is unavoidable with PlatformViews — selective event passthrough is not possible.
- **Circle swipe only inside circle**: `onPointerDown` checks distance from center; touches outside the circle are absorbed but ignored.
- **Pin position uses `_screenToGeo`**: Requires accurate camera center — if the camera state is stale, the pin may be offset from the circle. The circle position (screen-based) is always correct.

---

## Approaches That Failed

| Approach | Why it failed |
|----------|---------------|
| `MapEventLongClick` + `setState` overlay | PlatformView already owns the pointer |
| `Listener(translucent)` on top of map | PlatformView consumes events at native level |
| `_isDraggingRadius = true` in `_onLongPress` | Map already panning, can't stop mid-touch |
| Camera-based screen position calculation | `_controller?.camera` returns stale data |
| `AbsorbPointer` wrapping MapLibreMap | Requires setState → map widget rebuild |

---

## Key Insight

> The standard Flutter pattern for custom gestures on PlatformViews: don't try to intercept events AFTER the native view processes them. Instead, use Flutter's gesture arena (`GestureDetector`, `RawGestureDetector`) to claim the gesture BEFORE the native view can start processing it.
