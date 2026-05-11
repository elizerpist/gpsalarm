# Vector Map Implementation Progress — Full Summary

> GPS Alarm app, maplibre ^0.2.2 (josxha/flutter-maplibre), Android native
> Samsung Galaxy, DPR=2.63, 1080×2400
> 2026-04-28 — 2026-05-11

---

## Table of Contents

1. [The Goal](#the-goal)
2. [Timeline & Phases](#timeline--phases)
3. [Problem 1: Screen → Geo Conversion](#problem-1-screen--geo-conversion)
4. [Problem 2: GestureDetector vs MapEventLongClick](#problem-2-gesturedetector-vs-mapeventlongclick)
5. [Problem 3: Native Layers Not Rendering After Save](#problem-3-native-layers-not-rendering-after-save)
6. [Problem 4: Visual Inconsistency (Assign vs Saved)](#problem-4-visual-inconsistency-assign-vs-saved)
7. [Problem 5: Circle Size Discrepancy (DPR)](#problem-5-circle-size-discrepancy-dpr)
8. [Problem 6: Flash on Save](#problem-6-flash-on-save)
9. [Problem 7: Exit Trigger Missing Pin/Border](#problem-7-exit-trigger-missing-pinborder)
10. [What Didn't Work](#what-didnt-work)
11. [What Works Now](#what-works-now)
12. [Remaining Issues](#remaining-issues)
13. [Architecture](#architecture)
14. [Key Lessons Learned](#key-lessons-learned)

---

## The Goal

Long-press on the vector map (MapLibre) → place alarm pin at exact touch position → swipe (without lifting finger) to set radius → save → show circle + pin + distance chip on the map. Both enter and exit triggers. Must match the raster map (flutter_map) experience.

---

## Timeline & Phases

### Phase 1: Manual `_screenToGeo` formula (failed)
**Commits:** `fe0d9f1` → `3c58768` (6+ commits)

Tried to convert screen coordinates to geographic using:
```
metersPerPx = 156543 × cos(lat) / 2^zoom
dx = (touchX - mapCenterX) / dpr
geo.lng = camera.center.lng + dx × metersPerPx / (111320 × cos(lat))
```

**Result:** Always 30-200px off. Tried: DPR division, status bar padding, nav bar padding, camera center offset. None worked consistently. MapLibre's internal transforms are more complex than this linear approximation.

### Phase 2: `MapEventLongClick` (partially worked)
**Commits:** `46f6bcb` → `d02f628`

Used MapLibre's native long-click event for geo coordinates. Geo was perfect, but:
- No immediate swipe (can't intercept mid-touch for radius drag)
- GestureDetector wrapping the map steals the gesture from the PlatformView

Tried `_pendingLongClickGeo` race approach (MapEventLongClick at ~400ms, GestureDetector at ~500ms). In practice, MapEventLongClick does NOT fire when GestureDetector wraps the PlatformView.

### Phase 3: `toLngLatSync` discovery (breakthrough)
**Commits:** `1ea76e8`, `c838ca9`

Discovered `MapController.toLngLatSync(Offset)` — calls native `Projection.fromScreenLocation` via JNI. Pixel-perfect, no manual formula. This API existed in maplibre 0.2.2 all along but wasn't documented prominently.

**Critical DPR fix:** Flutter gives logical pixels, native expects physical → multiply by `devicePixelRatio`.

### Phase 4: Native layer rendering (hardest phase)
**Commits:** `81059a7` → `c5824a8` → `98647f0`

After save, `CircleStyleLayer` + `SymbolStyleLayer` didn't render. Root cause: dynamic `addSource()` from Timer callbacks silently fails on Android. Fix: pre-create sources at `onStyleLoaded`, use `updateGeoJsonSource` only.

### Phase 5: Visual polish & edge cases
**Commits:** `54219d3` → `bea3567`

Pin consistency, distance chips, edit overlay, exit trigger border, flash elimination.

---

## Problem 1: Screen → Geo Conversion

### Symptom
Pin jumps toward top-left of screen after saving.

### Root cause
`toLngLatSync(Offset)` calls native `Projection.fromScreenLocation(PointF)` which expects **physical pixels**. Flutter's `GestureDetector.localPosition` gives **logical pixels**. At DPR=2.63, coordinates were ~2.6× too small → point shifted toward origin.

### Why it wasn't visible during assign
Overlay draws at screen coordinates (touch position) — always correct. Only geo coordinates (for save) were wrong.

### Solution
```dart
final dpr = MediaQuery.devicePixelRatioOf(context);
final geo = _controller?.toLngLatSync(details.localPosition * dpr);
```

### What didn't work
- Manual `_screenToGeo` formula with various DPR/padding adjustments (6 commits, all failed)
- `MapEventLongClick` → mutually exclusive with GestureDetector

---

## Problem 2: GestureDetector vs MapEventLongClick

### Symptom
Need BOTH: immediate swipe-to-resize (GestureDetector) AND exact geo coordinates (MapEventLongClick). Can't have both — Flutter's gesture arena gives the gesture to one recognizer only.

### What didn't work
1. **MapEventLongClick only** → exact geo, no swipe
2. **GestureDetector only + manual formula** → swipe works, geo always offset
3. **Both with `_pendingLongClickGeo` timing race** → MapEventLongClick doesn't fire when GestureDetector wraps PlatformView
4. **`HitTestBehavior.translucent`** → affects hit testing, not gesture arena
5. **`RawGestureDetector`** → same arena rules apply

### Solution
GestureDetector for the UX + `toLngLatSync()` for exact geo. Clean, no race conditions.

---

## Problem 3: Native Layers Not Rendering After Save

### Symptom
`CircleStyleLayer` + `SymbolStyleLayer` added successfully (no errors), but nothing appears on the map.

### What didn't work
1. **Dynamic `addSource` + `addLayer` in Timer callback** → silently fails when `mapLibreMap.style` is transiently null (Kotlin `?.` operator skips without error, callback returns success)
2. **Race condition in version tracking** → `_syncRadiusSource` runs on every `build()`, incrementing version. If `build()` fires during async `_rebuildRadiusLayers`, version check aborts mid-rebuild: layers removed but not re-added
3. **Missing `text-font`** in SymbolStyleLayer layout → text silently doesn't render on Android native

### What worked
1. **Pre-create sources at `onStyleLoaded`** (20 placeholder GeoJsonSources)
2. **`updateGeoJsonSource`** instead of `addSource`/`removeSource`
3. **Explicit `text-font: ['Noto Sans Bold']`** in SymbolStyleLayer
4. **Increased debounce** from 50ms to 200ms
5. **Removed inner-loop version check** — once rebuild starts, it must complete
6. **Data hash cache** (`_lastRadiusDataHash`) — skip rebuild when alarm data unchanged

### Key insight
In maplibre 0.2.2 on Android, **sources must be created during `onStyleLoaded`** for reliable rendering. The native Kotlin code uses `mapLibreMap.style?.addLayer()` which silently no-ops if style is null, but `callback(Result.success(Unit))` is still called, making Dart think it succeeded.

### How it was diagnosed
- Added comprehensive debug logging (`SYNC_RADIUS`, `REBUILD_TIMER`, `REBUILD_LAYERS`)
- Confirmed layers were being "added" but not rendering
- PPX consultation confirmed the timing/lifecycle hypothesis
- Confirmed fix by mirroring the working "fast-circle" pattern (source created at init)

---

## Problem 4: Visual Inconsistency (Assign vs Saved)

### Symptom
- Assign pin: custom teardrop (28px) — saved pin: Material icon (64px)
- No distance chip on saved alarms
- Chip style different: Flutter Container (rounded badge) vs SymbolStyleLayer (text halo)
- Extra overlay circle when tapping to edit existing alarm

### Solutions
- **Assign pin** → `Icons.location_on` via `TextPainter` in `_RadiusOverlayPainter` (32px)
- **Saved pin** → `MarkerLayer` with `iconSize: 0.4` (160px image × 0.4 = ~64px)
- **Distance chip on saved** → `SymbolStyleLayer` with `text-halo-width: 8` (badge-like)
- **Edit overlay** → overlay shown for all trigger types during assign; edited alarm's native layers hidden to avoid duplication

### What didn't work
- `iconSize: 0.2` for MarkerLayer (too small — MapLibre's icon scaling works differently than Flutter widget pixels)
- `TextDirection.ltr` without `ui.` prefix (build error — `dart:ui as ui` import conflict)

### Remaining limitation
SymbolStyleLayer `text-halo` can't perfectly replicate a Flutter `Container` with `BorderRadius`. The halo is round, not a rectangle. This is a MapLibre native limitation.

---

## Problem 5: Circle Size Discrepancy (DPR)

### Symptom
Enter trigger circle (CircleStyleLayer) was visually smaller than exit trigger circle (veil geo-polygon) at the same radius.

### Investigation
Added debug logging comparing both:
```
RADIUS_PX: 322m → 203.6px  (overlay metersPerPx formula)
VEIL_GEO:  322m → 203.8px  (geo-polygon converted to pixels)
```
Both formulas produce **identical values** (203.6 vs 203.8px).

### What didn't work
- `basePx × DPR` for CircleStyleLayer → circle became 2.63× TOO LARGE (reverted)

### Conclusion
`circle-radius` is in **logical pixels** (not physical). The DPR multiplication was wrong. The perceived size difference between enter (filled circle) and exit (veil hole) is an optical illusion — the brain perceives filled areas smaller than equivalent holes.

---

## Problem 6: Flash on Save

### Symptom
Circle briefly disappears when saving — overlay vanishes instantly, native layers take 200ms+ to appear.

### Root cause
`_cancelAssign()` hides overlay immediately, but `_rebuildRadiusLayers` runs on a 200ms debounce timer. Gap = visible flash.

### What didn't work
- `_lastRadiusDataHash` cache alone — prevents redundant rebuilds but doesn't eliminate the initial gap
- Hash was also incorrectly implemented (duplicate assignment overwriting the edit hash)

### Solution
In `_saveAssign()`, run `_rebuildRadiusLayers` **synchronously** (no debounce) BEFORE calling `_cancelAssign()`. Native layers are built while overlay is still visible.

```dart
void _saveAssign(AlarmPoint alarm) {
  alarmProv.addAlarmPoint(alarm);
  _rebuildRadiusLayers(style, circles, version); // ← BEFORE overlay hide
  _cancelAssign(); // ← overlay disappears AFTER layers exist
}
```

---

## Problem 7: Exit Trigger Missing Pin/Border

### Symptom
Exit trigger (onLeave) showed the veil (pink overlay outside circle) but no pin, no chip, and no circle border.

### Root cause
- Overlay painter had `_assignZoneTrigger != ZoneTrigger.onLeave` condition → painter was null for exit triggers
- `_rebuildRadiusLayers` had `if (c.isLeave) continue;` → skipped all layers for exit alarms

### Solution
1. Overlay painter now has `isLeave` parameter: draws pin + chip always, circle fill only for enter trigger
2. `_rebuildRadiusLayers` no longer skips onLeave — adds `CircleStyleLayer` with transparent fill + colored stroke (border only)

---

## What Didn't Work (Complete List)

| Approach | Why It Failed |
|----------|--------------|
| Manual `_screenToGeo` formula | MapLibre's internal transforms too complex for linear approximation |
| DPR division in formula | Wrong direction — made offset worse |
| Status bar / nav bar padding adjustments | Inconsistent across devices |
| `MapEventLongClick` + GestureDetector together | Gesture arena prevents both from firing |
| `_pendingLongClickGeo` race (400ms vs 500ms) | MapEventLongClick doesn't fire when GestureDetector wraps PlatformView |
| `HitTestBehavior.translucent` | Affects hit testing, not gesture arena sharing |
| Dynamic `addSource` from Timer callbacks | Silently fails when style transiently null |
| `text-font` omitted in SymbolStyleLayer | Text silently doesn't render on Android |
| `iconSize: 0.2` for MarkerLayer | Too small on high-DPR devices |
| `basePx × DPR` for CircleStyleLayer | Circle 2.63× too large (circle-radius is in logical pixels) |
| Debounce alone for flash fix | 200ms gap still visible |

---

## What Works Now

| Feature | Implementation | Status |
|---------|---------------|--------|
| Long press to place alarm | GestureDetector + `toLngLatSync(pos × dpr)` | ✅ Working |
| Swipe to adjust radius | Overlay Listener + `metersPerPx` formula | ✅ Working |
| Pin at exact touch position | `toLngLatSync` with DPR correction | ✅ Working |
| Radius circle during assign | Flutter overlay (`_RadiusOverlayPainter`) | ✅ Working |
| Distance chip during assign | Canvas-drawn rounded badge in overlay | ✅ Working |
| Radius circle after save | Native `CircleStyleLayer` (pre-created sources) | ✅ Working |
| Distance chip after save | Native `SymbolStyleLayer` (text-halo) | ✅ Working |
| Pin after save | Native `MarkerLayer` | ✅ Working |
| Enter trigger (onEntry) | Fill + stroke CircleStyleLayer | ✅ Working |
| Exit trigger (onLeave) | Veil (FillStyleLayer hole) + stroke-only CircleStyleLayer | ✅ Working |
| Edit existing alarm | Tap → overlay shows, native layers hidden | ✅ Working |
| No flash on save | Sync rebuild before overlay hide | ✅ Working |

---

## Remaining Issues

1. **Chip design mismatch**: Overlay chip = Flutter `Container` (rounded rectangle badge). Saved chip = `SymbolStyleLayer` `text-halo` (round glow). MapLibre can't draw rounded rectangles natively. Options: (a) accept difference, (b) render chip as PNG icon per alarm, (c) use Flutter overlay for saved chips too (requires camera tracking).

2. **Perceived circle size difference**: Enter (filled) and exit (veil hole) look different sizes to the human eye despite being mathematically identical (confirmed by debug logging: 203.6 vs 203.8px). This is an optical illusion — filled areas appear smaller than equivalent negative space.

3. **Excessive rebuilds**: `_syncRadiusSource` runs on every `build()`. Data hash cache helps, but version counter still increments rapidly (observed: 170+ in one session). Could be optimized by debouncing the version increment itself.

4. **MarkerLayer vs overlay pin size**: MapLibre's `iconSize` doesn't directly correspond to Flutter's `Icon(size:)`. The 160px PNG at `iconSize: 0.4` ≈ 64px in MapLibre's rendering, which may look different from the overlay's 32px Canvas drawing at different zoom levels.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    ASSIGN MODE (editing)                 │
│                                                         │
│  GestureDetector.onLongPressStart                       │
│    └── _controller.toLngLatSync(localPos × dpr)         │
│         → _assignLat, _assignLng (geo coordinates)      │
│    └── _assignScreenCenter = localPos (screen coords)   │
│                                                         │
│  Flutter Overlay (_RadiusOverlayPainter)                │
│    ├── Circle: Canvas.drawCircle(center, radiusPx)      │
│    │   └── isLeave: skip circle (veil handles it)       │
│    ├── Pin: TextPainter(Icons.location_on, 32px)        │
│    └── Chip: Canvas RRect + TextPainter ("300m")        │
│                                                         │
│  Veil (for onLeave only)                                │
│    └── FillStyleLayer with geo-polygon hole             │
│        └── _geoCircle(lng, lat, radius) → haversine     │
│                                                         │
│  Radius calculation:                                    │
│    metersPerPx = 156543 × cos(lat) / 2^zoom             │
│    _assignRadius = dragDistance × metersPerPx            │
│    _radiusNotifier.value = _assignRadius / metersPerPx   │
└─────────────────────────────────────────────────────────┘
                          │
                     _saveAssign()
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    SAVED MODE (display)                  │
│                                                         │
│  1. _rebuildRadiusLayers (sync, before overlay hide)    │
│     ├── updateGeoJsonSource('radius-pt-alarm-N', data)  │
│     ├── addLayer(CircleStyleLayer)                      │
│     │   ├── circle-radius: interpolate(exp 2, zoom,     │
│     │   │     basePx, basePx×2^22)                      │
│     │   ├── onEntry: fill + stroke                      │
│     │   └── onLeave: transparent fill + stroke only     │
│     └── addLayer(SymbolStyleLayer)                      │
│         ├── text-field: '300m'                          │
│         ├── text-font: ['Noto Sans Bold']               │
│         └── text-halo-width: 8                          │
│                                                         │
│  2. _cancelAssign() (overlay disappears)                │
│                                                         │
│  3. MarkerLayer in layers: [...]                        │
│     ├── 'pin-red' (active alarms)                       │
│     └── 'pin-grey' (inactive alarms)                    │
│                                                         │
│  4. Veil (FillStyleLayer) for onLeave alarms            │
│                                                         │
│  Source lifecycle:                                       │
│    onStyleLoaded → addSource × 20 (placeholder)         │
│    on change → updateGeoJsonSource (data only)           │
│    on change → removeLayer + addLayer (layers ephemeral) │
│    on save → sync rebuild (no debounce)                  │
│    on pan/zoom → data hash skip (no unnecessary rebuild) │
└─────────────────────────────────────────────────────────┘
```

---

## Key Lessons Learned

### maplibre 0.2.2 on Android

1. **Sources MUST be created in `onStyleLoaded`**. Dynamic `addSource` from async/Timer contexts silently fails. Use `updateGeoJsonSource` on pre-created sources instead.

2. **Native Kotlin callback always returns success**. `mapLibreMap.style?.addLayer()` with null-safe operator silently skips, but `callback(Result.success(Unit))` is still called. You cannot trust the callback.

3. **`toLngLatSync` needs physical pixels** on Android. Multiply Flutter's logical pixel coordinates by `devicePixelRatio` before calling.

4. **`CircleStyleLayer` circle-radius is in logical pixels** (NOT physical). Do NOT multiply `basePx` by DPR — tested: 2.63× too large.

5. **`SymbolStyleLayer` requires explicit `text-font`** on Android. Without it, text silently doesn't render.

6. **Math expressions (`['*']`, `['/']`, `['+']`) are silently broken** in paint/layout properties. Pre-compute all values in Dart and embed as literals.

7. **GestureDetector and PlatformView gesture events are mutually exclusive**. The gesture arena gives the gesture to one recognizer only. `HitTestBehavior.translucent` and `gestureRecognizers` don't help.

### Flutter PlatformView on Android

8. **Overlay vs native layer rendering are fundamentally different systems**. The overlay is screen-fixed (doesn't pan/zoom with map). Native layers are geo-referenced. Switching between them on save causes visual discontinuity.

9. **The sync rebuild pattern** (`_rebuildRadiusLayers` before `_cancelAssign`) eliminates the flash gap between overlay disappearing and native layers appearing.

10. **Data hash caching** prevents unnecessary remove+add cycles during rapid `build()` calls (pan/zoom triggers rebuild → version counter races → layers flash).

### DPR on Android with MapLibre

11. **Three different pixel systems**:
    - Flutter logical pixels (GestureDetector, Canvas, widget sizes)
    - Physical pixels (native `Projection.fromScreenLocation`)
    - MapLibre style pixels (`circle-radius`, `icon-size` — these are logical, NOT physical)

12. **DPR correction map**:
    | API | Needs DPR? | Direction |
    |-----|-----------|-----------|
    | `toLngLatSync(Offset)` | Yes, × DPR | screen → geo |
    | `CircleStyleLayer` circle-radius | No | already logical |
    | `SymbolStyleLayer` text-size | No | already logical |
    | `MarkerLayer` iconSize | No | factor on image pixels |
    | `GestureDetector.localPosition` | — | already logical |
    | `Canvas.drawCircle` (overlay) | — | already logical |
