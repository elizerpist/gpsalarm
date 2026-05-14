# 2026-05-14 Exit Trigger Live Drag Data Flow

## Current Best State

The best known exit-trigger live-drag state is:

```text
aea0748 Hide native exit circle during live drag
```

This commit was pushed after:

```text
40f78db Fix exit radius edit ghost layers
```

The earlier useful baseline was:

```text
3d9d0aa Keep exit outline native during fast drags
```

`3d9d0aa` was important because it moved the exit outline away from the Flutter fallback border and back onto the native/live MapLibre path. It still had fade-out. `40f78db` removed the fade-out and cleaned up save/restore. `aea0748` kept that behavior and addressed the remaining fast-drag ghost.

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
EXIT_NATIVE_TRACE ... updated=false nativeSkipped=true veil=true
VEIL_MASK_SYNC ... reason=assign-radius:immediate:overlay#...
VEIL_OUTLINE_SYNC ... reason=assign-radius:immediate:overlay#...
```

`nativeSkipped=true` is intentional. The native radius circle must not be driven on every pointer frame in this path.

## Live Drag Data Flow

Fast exit radius drag follows this path:

```text
overlay pointer move
  -> _applyAssignRadiusPaint(debugReason: overlay#N)
  -> liveExitVeil == true
  -> _syncLiveExitNativeCircleSuppression(...)
  -> _syncAssignVeilWithRadiusPaint(...)
  -> _updateVeil(...)
  -> update veil-src mask
  -> update veil-live-outline-src outline
  -> keep scheduled radius-only native sync skipped
```

The visible drag circle is owned by the veil path:

- `veil-src` carries the red translucent mask with the live hole.
- `veil-live-outline-src` carries the live red outline ring.
- `veil-live-outline` is the only intended visible red border during fast drag.

The persisted alarm circle layer may exist in the style graph, but it must not be visible while the live exit veil owns the drag visual.

## Why The Ghost Happened

The remaining ghost after `40f78db` was not the old fade-out problem.

Two visual artifacts could still overlap during fast drag:

1. A native `radius-circle-alarm-N` layer could be re-created while `_assignExitNativeCircleSuppressed` was already true. Because suppression skipped repeated paint writes for performance, a re-created layer could briefly be visible at an older radius.
2. The fill layer could draw an anti-aliased edge around the live veil hole, visually doubling the explicit `veil-live-outline` border.

The logs showed `nativeSkipped=true` during drag while `EXIT_NATIVE_CIRCLE_SUPPRESS` later found `radius-circle-alarm-0` at overlay-up. That means the native layer could exist even though the live drag path did not update it every frame.

## Current Fix

`aea0748` fixes the remaining ghost without changing the hot pointer data flow.

In `maplibre_radius_layer_rebuild.dart`, existing live exit edits hide the native circle at layer creation:

```dart
final hideLiveExitNativeCircle =
    _assignExisting != null &&
    this._usesLiveAssignVeilHole() &&
    circle.id == _assignNativeAlarmLayerId;

if (hideLiveExitNativeCircle) 'circle-opacity': 0.0,
if (hideLiveExitNativeCircle) 'circle-stroke-opacity': 0.0,
```

In `maplibre_radius_layer_init.dart`, the veil fill no longer draws an anti-aliased hole edge:
