# Vector Map: Long-Press Geo Conversion & Post-Save Layer Rendering

## Problem 1: Screen → Geographic coordinate conversion

### Symptom
When long-pressing the MapLibre vector map to place an alarm, the saved alarm's pin+circle appeared at a **different position** than where the user touched. The pin would jump toward the top-left of the screen after saving.

### Root cause
Flutter's `GestureDetector.onLongPressStart` gives `details.localPosition` in **logical pixels** (dp), but MapLibre Android's native `Projection.fromScreenLocation(PointF)` (accessed via `MapController.toLngLatSync()`) expects **physical pixels**.

On a DPR=2.63 device, passing un-multiplied logical pixels made the native projection interpret the coordinates as a point closer to the origin (top-left), causing a consistent offset.

### Why it wasn't visible during assign
During assign mode, the pin and circle are drawn as a **Flutter overlay** at the touch's **screen coordinates** — these always matched the touch point. The geo coordinates from `toLngLatSync` were only used to **save** the alarm. After saving, the `MarkerLayer` rendered the pin at the (wrong) geo coordinates, causing the visible jump.

### Solution
Multiply `localPosition` by `devicePixelRatio` before passing to `toLngLatSync`:

```dart
final dpr = MediaQuery.devicePixelRatioOf(context);
final geo = _controller?.toLngLatSync(details.localPosition * dpr);
```

### Commits
- `1ea76e8` — initial `toLngLatSync` implementation (wrong, no DPR)
- `c838ca9` — DPR multiplication fix

---

## Problem 2: GestureDetector vs MapEventLongClick mutual exclusion

### Symptom
`GestureDetector` wrapping `MapLibreMap` and `MapEventLongClick` cannot both fire for the same gesture. When GestureDetector wins the arena at ~500ms, the native PlatformView never receives the long-press, so `MapEventLongClick` never fires.

### Failed approaches
1. **MapEventLongClick only** — gives exact geo but no immediate swipe for radius drag
2. **GestureDetector only + manual formula** — `metersPerPx = 156543 * cos(lat) / 2^zoom` is always 30-200px off due to MapLibre's internal transforms (camera offsets, tile scale, bearing, PlatformView composition offset)
3. **Both together with `_pendingLongClickGeo` race** — MapEventLongClick at ~400ms, GestureDetector at ~500ms. In practice, MapEventLongClick does NOT fire when GestureDetector claims the gesture.

### Solution
Use `MapController.toLngLatSync(Offset)` which calls native `Projection.fromScreenLocation` via JNI — pixel-perfect, no manual formula needed. This API already existed in maplibre 0.2.2 but was overlooked.

```dart
onLongPressStart: (details) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final geo = _controller?.toLngLatSync(details.localPosition * dpr);
  _startAssign(geo.lat.toDouble(), geo.lng.toDouble());
},
```

### Commits
- `1ea76e8` — discovered and used `toLngLatSync`
- `c838ca9` — DPR fix

---

## Problem 3: CircleStyleLayer + SymbolStyleLayer not rendering after save

### Symptom
After saving an alarm on the vector map, the radius circle and distance chip label did not appear. No errors in logs. The same `CircleStyleLayer` pattern worked perfectly for the "fast-assign" circle during drag.

### Root cause (confirmed via PPX + debug logging)
**`addSource()` called from a Timer callback silently fails** when the MapLibre style is transiently unavailable. The native Kotlin code uses `mapLibreMap.style?.addLayer()` with null-safe operator — if `style` is null at that instant, the call is silently skipped and `callback(Result.success(Unit))` is still returned.

The "fast-assign" circle worked because its source (`fast-src`) was created during `onStyleLoaded` (style guaranteed loaded). The per-alarm sources were created dynamically in `_rebuildRadiusLayers()` called from a debounced Timer — style could be transiently null during rapid Flutter rebuilds.

### Additional factors
1. **Race condition in version tracking**: `_syncRadiusSource` runs on every `build()`, incrementing `_radiusLayerVersion`. If `build()` fires during the async `_rebuildRadiusLayers`, the version check aborted the rebuild mid-execution — layers were removed but not re-added.
2. **Missing `text-font`**: `SymbolStyleLayer` requires explicit `text-font` in layout on Android native. Without it, text silently doesn't render even if glyphs are available from the style.

### Solution
Mirror the working "fast-circle" pattern:

1. **Pre-create sources at init** (during `onStyleLoaded`, style guaranteed):
```dart
Future<void> _initRadiusLayer(StyleController style) async {
  // ... existing veil + fast-src sources ...
  for (int i = 0; i < 20; i++) {
    await style.addSource(GeoJsonSource(id: 'radius-pt-alarm-$i', data: _emptyGeoJson));
  }
}
```

2. **Use `updateGeoJsonSource`** instead of `addSource`/`removeSource`:
```dart
// Source always exists — just update data
style.updateGeoJsonSource(id: 'radius-pt-${c.id}', data: _pointGeoJson(c.lng, c.lat));
// Then remove/add LAYERS only (not sources)
await style.addLayer(CircleStyleLayer(...));
```

3. **Add explicit `text-font`** to SymbolStyleLayer:
```dart
layout: {
  'text-field': '500m',
  'text-font': ['Noto Sans Regular'],
  // ...
},
```

4. **Increase debounce** from 50ms to 200ms to reduce race window.

5. **Remove inner-loop version check** — once rebuild starts, it must complete.

### Key insight
In maplibre 0.2.2 on Android, **sources must be created during `onStyleLoaded`** for reliable layer rendering. Dynamic `addSource` from Timer/async callbacks is unreliable due to transient style unavailability. Use `updateGeoJsonSource` on pre-created sources instead.

### Commits
- `81059a7` — removed inner-loop version check
- `c5824a8` — pre-create sources at init, `updateGeoJsonSource`, `text-font`
- `98647f0` — debug logging + 200ms debounce (confirmed working)

---

## Problem 4: Assign overlay vs saved alarm visual inconsistency

### Issues
- Assign pin was custom-drawn teardrop (28px), saved pin was Material `Icons.location_on` (64px via MarkerLayer)
- No distance chip on saved alarms (only during assign)
- Extra overlay circle appeared when tapping to edit existing alarm

### Solutions
- **Assign pin**: Changed to `Icons.location_on` drawn via `TextPainter` in `_RadiusOverlayPainter` (32px, matching raster map)
- **Distance chip on saved**: `SymbolStyleLayer` with `text-field` + `text-halo-color/width` on each alarm's point source
- **Edit overlay**: Added `_assignExisting == null` condition — overlay only shows for new alarms, not when editing existing ones

### Commits
- `54219d3` — pin style, overlay chip, edit overlay fix
- `3dae68b` — pin sizes, SymbolStyleLayer for saved alarms

---

## Problem 5: CircleStyleLayer circle smaller than Flutter overlay / veil

### Symptom
Same alarm, same radius (146m), same zoom — but the enter trigger's native `CircleStyleLayer` circle is visibly smaller than:
- The Flutter overlay circle (during assign)
- The veil hole (exit trigger, geo-polygon)

### Root cause
MapLibre's `circle-radius` is in **physical pixels** on Android. The `basePx` formula produces **logical pixels**. At DPR=2.63, the native circle was 2.63x smaller than expected.

The veil (exit trigger) uses a geo-polygon in geographic coordinates, so it's not affected by the pixel ratio. The Flutter overlay operates in logical pixels. Only the CircleStyleLayer's pixel-based radius was wrong.

### Solution
Multiply `basePx` by `devicePixelRatio`:

```dart
final basePx = c.radiusMeters / (156543.03392 * cos(c.lat * π / 180)) * dpr;
```

### Commits
- `216468d` — DPR multiplication for CircleStyleLayer basePx

---

## Architecture summary

```
During assign (long-press + drag):
  ├── Pin + circle + chip: Flutter overlay (_RadiusOverlayPainter)
  │   └── onLeave: pin+chip only (veil provides circle visual)
  ├── Geo coords: toLngLatSync(screenPos * dpr)
  └── Radius: pixel drag distance × metersPerPx

After save:
  ├── Pin: MarkerLayer (iconImage: 'pin-red', iconSize: 0.4)
  ├── Circle: CircleStyleLayer on pre-created source
  │   └── circle-radius: interpolate(exponential 2, zoom, basePx*dpr..basePx*dpr*2^22)
  └── Label: SymbolStyleLayer on same source
      └── text-field: '500m', text-font: ['Noto Sans Bold']

DPR corrections needed:
  ├── toLngLatSync(screenPos * dpr)     — screen→geo conversion
  └── basePx * dpr                       — CircleStyleLayer radius

Source lifecycle:
  onStyleLoaded → addSource('radius-pt-alarm-0'..'radius-pt-alarm-19')
  on rebuild    → updateGeoJsonSource (data only, source persists)
                → removeLayer + addLayer (layers are ephemeral)
  on save       → _lastRadiusDataHash = '' (force rebuild)
```
