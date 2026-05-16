# 2026-05-16 MapLibre Exit Veil Handoff Known Good State

## Confirmed Working State

This is the first user-confirmed state where Android MapLibre exit-trigger editing is visually acceptable:

```text
bbb7ddc Smooth save veil handoff
fbe50cd Keep draft marker through new alarm save
748ae18 Defer exit veil handoff after save
```

User confirmation after `bbb7ddc`: the flow works, the pin no longer flashes, and only a minimal veil flicker remained before the final smoothing change. Keep this sequence as the baseline for future changes.

## What The Working Flow Does

### 1. Keep one visible radius border owner

The visible edit/save border is the native `radius-circle-*` layer for both enter and exit alarms. The exit veil owns only the outside mask. `veil-live-outline` remains hidden and must not become the normal edit border again.

Healthy live exit drag logs should keep showing native radius paint updates instead of skipping the native circle:

```text
ASSIGN_SYNC_SKIP: ... path=live-exit-immediate radiusOnly=true marker=false
EXIT_NATIVE_TRACE: ... nativeSkipped=false veil=true
EXIT_NATIVE_VEIL_PAINT: ... reason=assign-radius:immediate:...
```

### 2. Promote new alarm draft visuals in place

New alarm creation preallocates the final native visual id, such as `alarm-0`, while the user is still assigning the alarm. On save, the draft circle is promoted in place instead of clearing it and waiting for a full rebuild.

The important save behavior is:

```text
SAVE_ASSIGN: existing=null ...
Alarm added: <id>
EXIT_NATIVE_VEIL_CLEAR: stage=start reason=save-rebuild-pre-native ...
VEIL_SOURCE_UPDATE: id=veil-src ... reason=save-rebuild-pre-native
EXIT_NATIVE_CIRCLE_SUPPRESS: active=false reason=save-promote-restore ...
NATIVE_RENDER_ACK: reason=save-native-flush ...
EXIT_NATIVE_VEIL_HANDOFF_DEFER: reason=save-veil-handoff delayMs=220 ...
```

Do not let a provider-triggered full `_rebuildRadiusLayers` immediately replace the same new alarm visual after save unless the style has actually reloaded.

### 3. Keep the draft pin overlay after new alarm save

The new alarm pin/chip does not exist as a stable native `radius-label-*` layer until promotion. If the Flutter draft marker overlay is cleared immediately, there can be a one-frame pin flash.

The fix in `fbe50cd` keeps the Flutter marker overlay alive briefly only for promoted new alarms:

```dart
final keepPromotedMarker = promotedCircle != null;
_beginClosingAssignVisual(
  keepCircle: false,
  keepPreview: false,
  keepMarker: keepPromotedMarker,
);
_scheduleAssignVisualClear(
  keepPromotedMarker ? const Duration(milliseconds: 260) : Duration.zero,
);
```

Existing alarm saves do not need this overlay because their native pin layer is already present and only updated in place.

### 4. Prepare static veil while the live annulus still covers the map

For exit alarms, the live edit veil is the native `veil-live-annulus` circle stroke. The saved/static veil is the polygon mask in `veil-src` rendered by `veil-fill`.

The stable save path first updates `veil-src` for the final saved state while the live annulus is still visible. It does not hide the annulus or clear its source in the same render pass:

```text
EXIT_NATIVE_VEIL_CLEAR: stage=start reason=save-...-pre-native needsFlush=true liveHole=true nativeActive=true
VEIL_SOURCE_UPDATE: id=veil-src ... reason=save-...-pre-native
EXIT_NATIVE_VEIL_CLEAR: stage=static-ready ... nativeActive=true
```

Only after the native save flush/render ACK does the code schedule the final handoff:

```text
NATIVE_RENDER_ACK: reason=save-native-flush ...
EXIT_NATIVE_VEIL_HANDOFF_DEFER: reason=save-veil-handoff delayMs=220 ...
```

### 5. Smooth only the delayed save handoff

The remaining visible veil flicker came from a single abrupt opacity swap:

```text
veil-fill opacity: 0.0 -> 0.15
veil-live-annulus stroke opacity: 0.15 -> 0.0
```

Even with correct log order, MapLibre Android can present these paint changes across different rendered frames. The working fix in `bbb7ddc` uses two explicit blend steps only in the delayed save-close handoff:

```text
fill 0.05 / annulus 0.10
wait for native render ACK
fill 0.10 / annulus 0.05
wait for native render ACK
fill 0.15 / annulus 0.00
wait for native render ACK
clear hidden live annulus radius/stroke/source
```

This is intentionally not a MapLibre style transition. It is controlled Dart-side sequencing with existing `setLayerPaintProperty` calls and render waits.

The direct zone toggle path remains immediate so card interaction does not feel sluggish. Only `_scheduleLiveExitVeilStaticHandoffAfterClose(...)` calls `_handoffLiveExitVeilToStatic(..., smooth: true)`.

## What Does Not Work

Do not reintroduce these approaches:

- **MapLibre `*-transition` paint maps.** Android rejected nested transition maps with `Unsupported property type: _Map<String, int>` and layer initialization failed.
- **Immediate live-annulus-to-static opacity swap on save.** `veil-fill` up and `veil-live-annulus` down in one handoff can still flicker even when debug logs are ordered correctly.
- **Clearing `veil-live-annulus-src`, `circle-radius`, or `circle-stroke-width` in the same render pass as the opacity handoff.** That can create an empty or mismatched frame. Clear hidden geometry only after the hidden handoff has rendered.
- **Removing the draft marker overlay immediately for new alarm saves.** The native `radius-label-*` pin may not be visually ready yet, causing a pin flash.
- **Full rebuild as the default new-alarm save path.** It can duplicate or briefly remove the same visual. Prefer draft promotion in place.
- **Making `veil-live-outline` the visible edit border again.** It competes with `radius-circle-*` and can create doubled/thicker borders.
- **Flutter fallback borders for the radius circle.** They create a second visual owner and drift from the native circle path.
- **Source-driven `circle-radius` updates from GeoJSON properties for live drag on Android.** The source updates landed, but MapLibre did not reliably re-evaluate `circle-radius`; the result was a stuck native border while the veil moved.
- **GeoJSON polygon radius circles for the actual alarm radius.** Polygon simplification causes faceted circles. The veil mask may use polygons; the visible radius circle must not.
- **Trusting timeout ACK as proof that a specific style/source mutation is visible.** `NATIVE_RENDER_ACK source=timeout:96ms` is only a timing fallback. It reduces risk but does not provide an atomic commit guarantee.

## Files To Check Before Changing This Again

Core implementation:

- `lib/widgets/maplibre_new_view/maplibre_assign_lifecycle.dart`
- `lib/widgets/maplibre_new_view/maplibre_veil_layer.dart`
- `lib/widgets/maplibre_new_view/maplibre_radius_layer_rebuild.dart`
- `lib/widgets/maplibre_new_view/maplibre_radius_layer_init.dart`

Regression tests:

- `test/widgets/maplibre_exit_veil_sync_test.dart`
- `test/widgets/maplibre_exit_outline_test.dart`

Related background docs:

- `docs/2026-05-14-exit-trigger-live-drag-dataflow.md`
- `docs/vector-radius-flicker-and-drag-performance.md`

## Verification Checklist

Before calling a future change in this area good, manually test on Android native MapLibre mode:

1. Create a new `onLeave` distance alarm and save it.
2. Confirm the pin/chip does not disappear at save.
3. Confirm the veil does not flash hard at `EXIT_NATIVE_VEIL_HANDOFF`.
4. Re-open the saved alarm and save without changing radius.
5. Edit radius from card and save.
6. Toggle `onEntry -> onLeave -> onEntry -> onLeave` while editing.
7. Cancel an existing `onLeave` edit.

Expected automated verification:

```sh
/root/flutter/bin/flutter test
```

The suite should include the regression tests for delayed save handoff, draft marker overlap, native annulus paint, and hidden source clear ordering.
