# 2026-05-14 Exit Trigger Live Drag Data Flow

## Current Best State

The best known exit-trigger live-drag state is:

```text
9075288 Use native circle for exit edit border
```

This commit was pushed after:

```text
40f78db Fix exit radius edit ghost layers
```

The earlier useful baseline was:

```text
3d9d0aa Keep exit outline native during fast drags
```

`3d9d0aa` was important because it moved the exit outline away from the Flutter fallback border and back onto the native/live MapLibre path. It still had fade-out. `40f78db` removed the fade-out and cleaned up save/restore. `aea0748` kept that behavior and addressed the remaining fast-drag ghost. `2b0fdfe` kept the same flow but made the live edit border full opacity. `ec41947` keeps the fast drag flow, but matches the live edit outline back to the saved native stroke strength after screenshots showed the edit border was too strong and visually thicker. `36f0f04` keeps the existing native circle layer present and suppresses only the native exit stroke, not the full circle opacity, so exit-to-enter switches do not fade the enter fill back in. `7041cd2` removes the attempted MapLibre transition paint properties because the Android plugin rejects nested transition maps during style initialization. `7cd7492` refreshes the native circle source once when entering live exit mode so a draft/edited enter circle cannot leave its native fill under the exit veil hole. `ab3c87b` applies the same source-first rule before restoring enter visuals, so exit-to-enter does not expose the native circle before `isLeave=false` has reached the circle source. `9075288` makes exit edit use the same native `radius-circle-*` border as enter edit; the veil remains responsible only for the exit mask.

## User-Visible Target

For existing alarm edits with:

- trigger type: distance
- zone trigger: onLeave
- visual owner: nativeLive

fast radius drag should show exactly one red border. The border should remain visible during drag and should not fade out on save or restore.

The expected debug shape during drag is:

```text
EXIT_INPUT_TRACE ... owner=nativeLive nativeHidden=false overlay=false nativeExisting=true trigger=distance zone=onLeave
ASSIGN_SYNC_SKIP ... path=live-exit-immediate radiusOnly=true marker=false
EXIT_NATIVE_TRACE ... updated=true nativeSkipped=false veil=true
VEIL_MASK_SYNC ... reason=assign-radius:immediate:overlay#...
VEIL_OUTLINE_SYNC ... reason=assign-radius:immediate:overlay#...
```

`nativeSkipped=false` is intentional in the current path. The native radius circle border is the shared enter/exit edit circle; the veil still updates only the exit mask.

## Live Drag Data Flow

Fast exit radius drag follows this path:

```text
overlay pointer move
  -> _applyAssignRadiusPaint(debugReason: overlay#N)
  -> liveExitVeil == true
  -> _setCircleLayerRadiusPaint(...) on radius-circle-*
  -> _syncLiveExitNativeCircleSuppression(...) keeps native circle visible
  -> _syncAssignVeilWithRadiusPaint(...)
  -> _updateVeil(...)
  -> update veil-src mask
  -> leave veil-live-outline hidden
  -> keep scheduled radius-only source sync skipped
```

The visible drag border is owned by the native circle path:

- `radius-circle-*` is the single red circle border for enter and exit edit.
- `veil-src` carries the red translucent mask with the live hole.
- `veil-live-outline-src` may still be updated by the veil machinery, but `veil-live-outline` stays at opacity 0 and is not the visible border.

## Why The Ghost Happened

The remaining ghost after `40f78db` was not the old fade-out problem.

Two visual artifacts could still overlap during fast drag:

1. A native `radius-circle-alarm-N` layer could be re-created while `_assignExitNativeCircleSuppressed` was already true. Because suppression skipped repeated paint writes for performance, a re-created layer could briefly be visible at an older radius.
2. The fill layer could draw an anti-aliased edge around the live veil hole, visually doubling the explicit `veil-live-outline` border.

The logs showed `nativeSkipped=true` during drag while `EXIT_NATIVE_CIRCLE_SUPPRESS` later found `radius-circle-alarm-0` at overlay-up. That means the native layer could exist even though the live drag path did not update it every frame.

## Current Fix

`aea0748` fixed the remaining ghost without changing the hot pointer data flow. `2b0fdfe` tried a full-opacity live edit outline, but screenshots showed that was stronger than the saved circle. `ec41947` is the border visual match point. `36f0f04` is the switch visual match point because it removes the enter fill fade. `7041cd2` is the initialization-safe state because it removes unsupported `*-transition` paint maps. `9075288` is the current zone-switch visual state because it uses the native `radius-circle-*` as the only visible edit border for both enter and exit, while keeping the veil mask path unchanged.

In `maplibre_radius_layer_rebuild.dart`, existing live exit edits no longer hide the native circle at layer creation. Exit circles already have transparent native fill through the shared circle color expression, so their native stroke can stay visible without changing the veil mask.

In `maplibre_assign_lifecycle.dart`, `_applyAssignRadiusPaint` now calls `_setCircleLayerRadiusPaint(...)` before the exit-specific veil mask sync. This is the same native radius paint path used by enter edit, so exit edit no longer has a separate live border owner. Existing exit edit startup also keeps the native circle visible instead of hiding the stroke.

In `maplibre_veil_layer.dart`, `_syncAssignExitVeilOutlineMode` keeps `veil-live-outline` at opacity 0 and keeps `radius-circle-*` stroke opacity at 1.0. This does not change the veil mask; it only stops the old live-outline border from competing with the native circle border.

In `maplibre_radius_layer_init.dart`, the veil fill no longer draws an anti-aliased hole edge:

```dart
'fill-antialias': false,
```

Do not add MapLibre `*-transition` paint maps here: the Android plugin rejected `{duration: 0, delay: 0}` with `Unsupported property type: _Map<String, int>` and prevented radius/veil layer initialization.

This keeps the red border always visible through `radius-circle-*`, prevents live-outline/native border duplication, and makes exit edit visually consistent with enter edit and saved native radius circles.

## Constraints For Future Changes

Do not reintroduce these into the live exit drag path:

- Flutter fallback borders for the radius circle.
- Opacity fade transitions on radius circle restore.
- Per-frame forced native circle suppression writes.
- Scheduled full native source sync during live exit drag.
- Visible `veil-live-outline` as the normal edit border.
- Polygon radius rendering for the actual saved or edited radius circle.

If this area needs another change, preserve the single-circle rule: enter and exit edit borders use `radius-circle-*`; exit-specific behavior belongs to the veil mask only.
