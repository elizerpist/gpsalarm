# Vector Map Radius Circles — Implementation Notes

## The Problem

Drawing meter-based radius circles on a MapLibre vector map in Flutter (`maplibre ^0.2.2`) that are:
- Perfect geometric circles at every zoom level
- Smooth-scaling during zoom gestures (no jumps, no lag)
- Correctly sized in real-world meters (100m–5000m)
- Moving in sync with the map during pan/scroll
- Supporting per-feature styling (active=red, inactive=grey)

This turned out to be far harder than expected due to limitations in the `maplibre ^0.2.2` Flutter wrapper and the MapLibre Native tile pipeline.

---

## Approaches That Failed

### 1. Annotation `CircleLayer` (from `MapLibreMap.layers`)

```dart
CircleLayer(points: [...], radius: 38, color: ..., strokeColor: ..., strokeWidth: ...)
```

- `radius` is `int` (pixels) — causes discrete size jumps during zoom
- Must be recalculated from meters on every zoom change via Dart `setState`
- The Dart↔native bridge is async — 1–2 frame lag during pinch-to-zoom
- **Result:** circles jump and lag behind the smoothly zooming map tiles

### 2. `CircleStyleLayer` with `['*']` math expression

```dart
'circle-radius': ['*', ['get', 'basePx'],
  ['interpolate', ['exponential', 2.0], ['zoom'], 0.0, 1.0, 22.0, 4194304.0]]
```

- Simple expressions like `['get', 'prop']` and `['case', ...]` work
- **Math operators `['*', ...]` are completely ignored** in maplibre 0.2.2
- Circle stays at default ~5px regardless of the expression
- **Result:** broken — expressions with arithmetic don't work

### 3. `circle-pitch-scale: 'map'` on CircleStyleLayer

```dart
paint: {'circle-pitch-scale': 'map', 'circle-radius': ['get', 'basePx']}
```

- `circle-pitch-scale` controls 3D pitch behavior, NOT 2D zoom scaling
- `basePx` at zoom 0 is ~0.005 (sub-pixel) → circles are invisible
- **Result:** no circles rendered at all

### 4. GeoJSON Polygon circles (`FillStyleLayer` + `LineStyleLayer`)

256-point polygon approximating a circle in geographic coordinates (Haversine formula).

- **Pan:** perfect — native GL, no lag ✓
- **Zoom scaling:** perfect — geo-referenced coordinates ✓
- **Shape:** MapLibre's tile pipeline applies **Douglas-Peucker simplification** at certain zoom levels, reducing the polygon to a visible pentagon/hexagon
- More segments (512, 1024) don't help — simplification is based on circle size in tile-pixel units, not vertex count
- **Result:** looks like a polygon at mid-zoom levels

### 5. Disabling tile simplification via `tolerance: 0`

- `GeoJsonSource` in maplibre 0.2.2 doesn't expose `tolerance` parameter
- CI patch to native `MapLibreMapController.java` adding `.withTolerance(0.0f)` — didn't help
- Simplification likely happens at the tile *rendering* level, not source level
- **Result:** polygon edges still visible

### 6. Hybrid: polygon fill + CircleLayer stroke

- Polygon `FillStyleLayer` for smooth-scaling fill area
- Annotation `CircleLayer` for perfect geometric circle border
- **Problem:** CircleLayer stroke jumps/lags during zoom (async Dart bridge)
- Fill and stroke sizes don't match consistently
- `devicePixelRatio` correction attempted — still inconsistent
- **Result:** mismatched and jumpy stroke

### 7. `['interpolate']` with `['get']` stop values

```dart
['interpolate', ['exponential', 2], ['zoom'], 0, ['get', 'r0'], 22, ['get', 'r22']]
```

- MapLibre spec requires stop output values to be **literal numbers**, not expressions
- Can't use per-feature values in interpolation stops this way
- **Result:** not applicable

---

## The Solution That Works ✅

### Per-alarm `CircleStyleLayer` with literal `interpolate` expression

Each alarm point gets its own `GeoJsonSource` (Point) + `CircleStyleLayer` with **pre-computed literal zoom stops**:

```dart
'circle-radius': [
  'interpolate', ['exponential', 2.0], ['zoom'],
  0.0, basePx,          // pixel radius at zoom 0
  22.0, basePx * 4194304.0,  // pixel radius at zoom 22 (= basePx * 2^22)
]
```

Where `basePx = radiusMeters / (156543.03392 * cos(lat * π / 180))` — the pixel radius at zoom level 0.

### Why this works

1. **No `['*']` operator** — the multiplication is pre-computed in Dart and baked into the stop values as literal numbers
2. **`['interpolate', ['exponential', 2], ['zoom'], ...]`** works natively — the GL renderer smoothly interpolates `basePx * 2^zoom` at every frame
3. **Perfect geometric circle** — native `circle-radius`, not a polygon
4. **Smooth zoom** — computed entirely on the GPU, no Dart bridge involvement
5. **Correct meter-based radius** — the exponential interpolation with base 2 exactly matches the Web Mercator projection's zoom-to-meters relationship

### Architecture

```
For each alarm point:
  1. Compute basePx from radiusMeters and latitude
  2. Create GeoJsonSource with a single Point feature
  3. Create CircleStyleLayer with literal interpolate expression
  4. On radius/position change: remove old source+layer, create new ones
```

### Trade-offs

- **One source + one layer per alarm** — acceptable for typical alarm counts (<20)
- **Layer recreation on radius change** (slider drag) — slightly more overhead than updating a property, but smooth enough in practice
- **No shared layer** — can't use a single layer for all alarms because each has different basePx values, and `['get']` can't be used inside interpolation stop values

### Key formulas

```
metersPerPixel(lat, zoom) = 156543.03392 * cos(lat * π/180) / 2^zoom
basePx(radiusMeters, lat) = radiusMeters / (156543.03392 * cos(lat * π/180))
pixelRadius(basePx, zoom)  = basePx * 2^zoom
```

The `['interpolate', ['exponential', 2], ['zoom'], 0, basePx, 22, basePx * 2^22]` expression computes `basePx * 2^zoom` natively for any zoom level between 0 and 22.

---

## MapLibre 0.2.2 Expression Support Summary

| Expression | Works? | Notes |
|-----------|--------|-------|
| `['get', 'prop']` | ✅ | Property access |
| `['case', cond, v1, v2]` | ✅ | Conditional |
| `['interpolate', ['exponential', N], ['zoom'], ...]` | ✅ | With literal stop values |
| `['*', a, b]` | ❌ | Multiplication — silently ignored |
| `['/', a, b]` | ❌ | Presumed broken (not tested) |
| `['+', a, b]` | ❌ | Presumed broken (not tested) |

The workaround for math: **pre-compute in Dart, embed as literal values** in the expression.
