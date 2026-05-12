# Vector Radius Flicker And Drag Performance

## Context

The vector map uses MapLibre Native through the Flutter `maplibre` wrapper. Alarm radii must look like true circles, follow map pitch in 3D, scale correctly in meters during zoom, and avoid any visible transition between assign/edit mode and the saved alarm state.

This is difficult because the wrapper only supports a limited subset of MapLibre expressions reliably. In particular, arithmetic expressions such as `['*', ...]` are not usable for per-feature meter-to-pixel scaling. A GeoJSON polygon is also not acceptable for radius rendering, because MapLibre simplifies polygon geometry at some zoom levels and the circle becomes visibly faceted.

## User-visible failure

The vector radius previously flickered or duplicated for a few milliseconds in these flows:

- Creating a new alarm, then saving it.
- Editing an existing alarm, changing the radius, then saving it.
- Cancelling edit after the native circle and the temporary assign circle had both been visible.

The visible symptoms were:

- Red circle/veil briefly doubled.
- Pin/chip sometimes faded in after save.
- Border thickness and veil opacity looked inconsistent between edit mode and saved mode.
- The saved map sometimes looked different from edit mode because two visual systems were active for one alarm.

## Root cause

The old flow had two different visual owners for the same alarm:

1. A temporary assign visual used while the user was placing or editing the alarm.
2. The permanent saved alarm visual rebuilt by `_rebuildRadiusLayers`.

On save, the app added or updated the alarm in `AlarmProvider`. That provider change scheduled radius sync. The sync path later ran `_rebuildRadiusLayers`, which cleared old native layers and added permanent ones again. During that short window the temporary visual and the permanent visual could overlap, or the temporary visual could be removed before the permanent one was fully ready.

This was especially visible for new alarms because the draft assign circle did not already share the final permanent layer id. The save path therefore had to swap visual systems.

## Constraints

The radius must not be drawn as a polygon.

Acceptable radius rendering:

- `CircleStyleLayer`
- point source + native circle paint
- literal `interpolate` zoom stops for saved, meter-accurate radius

Rejected radius rendering:

- GeoJSON polygon fill/line circles
- polygon approximations with more vertices
- hybrid polygon fill plus circle border

The veil mask may still use a polygon with holes, because that polygon is only the screen-darkening mask. It is not the visible radius circle.

## Stable saved-radius solution

Saved alarm radii use one point source and one `CircleStyleLayer` per alarm.

The layer uses precomputed literal zoom stops:

```dart
'circle-radius': [
  'interpolate',
  ['exponential', 2.0],
  ['zoom'],
  0.0,
  basePx,
  22.0,
  basePx * 4194304.0,
]
```

`basePx` is computed in Dart:

```text
basePx = 2 * radiusMeters / (156543.03392 * cos(latitude))
```

This works because the expensive math is done before the expression is sent to MapLibre. MapLibre only receives literal stop values, so native zoom interpolation remains smooth.

## Flicker fix

The save flow now avoids switching visual ownership.

For a new alarm, assign mode preallocates the same layer id that the saved alarm will use:

```text
alarm-${alarmProvider.alarmPoints.length}
```

The draft radius circle is created directly on that final id, for example:

```text
radius-pt-alarm-0
radius-circle-alarm-0
```

On save, the draft visual is promoted in place:

- update the final source
- add or refresh the final pin/chip label
- mark the visual id as active
- update `_lastRadiusDataHash`
- do not trigger a delayed full `_rebuildRadiusLayers`

For existing alarms, edit mode keeps the existing native visual alive and updates it in place. On save or cancel, the source is updated back to the final alarm state without hiding the pin/chip first.

The important rule is:

```text
Do not let save remove the edit visual before the saved visual is ready.
Do not let provider sync rebuild the same visual a second time immediately after save.
```

## Current performance issue

Long-press + swipe radius editing in vector mode can still feel below 60 FPS.

The problematic drag path is different from the save flicker path. During pointer movement, the app currently has to update live radius visuals many times per second. If every move causes:

- a Flutter `setState`
- an assign marker bitmap refresh
- a MapLibre GeoJSON source update
- and possibly a `CircleStyleLayer` remove/add because the radius expression changed

then the UI can miss frames.

The saved-radius expression is ideal for persisted alarms, but it is expensive for live dragging if the layer has to be recreated whenever the radius changes.

## Performance direction

Use two CircleStyleLayer modes, both still non-polygon:

1. Saved mode:
   - meter-accurate literal zoom interpolation
   - stable while zooming and panning
   - used for persisted alarms

2. Live drag mode:
   - source property contains the current screen pixel radius
   - circle layer reads `['get', 'radiusPx']`
   - pointer movement updates only the GeoJSON source
   - no layer remove/add during drag

This is valid because map gestures are blocked during assign/edit. The camera zoom is effectively fixed while the user drags the radius, so a screen-pixel radius is stable for the duration of the gesture. On save or cancel, the layer is converted back to saved mode.

The drag loop should also avoid rebuilding the full widget tree for every pointer event. The circle visual should update immediately, while lower-priority UI such as the slider text and marker chip can be coalesced to a frame callback or throttled update.

## Expected healthy logs

Healthy save flow:

```text
SAVE_ASSIGN: existing=null ...
Alarm added: ...
```

There should not be an immediate:

```text
REBUILD_LAYERS: START ...
```

after every new-alarm save unless the style has reloaded or a full rebuild is genuinely required.

Healthy edit flow:

```text
ASSIGN_START: ... existing=<id>
ASSIGN_START: keeping native alarm visual during edit
SAVE_ASSIGN: existing=<id> ...
Alarm updated: <id>
```

No `ZONE ERROR`, `Use after release`, or repeated `Null check operator` logs should appear.
