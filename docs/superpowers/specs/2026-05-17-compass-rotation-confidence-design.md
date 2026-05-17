# Compass Rotation Confidence Design

## Context

The latest compass change correctly prevents large tilt-induced target jumps, but it also made real rotation feel worse. The log shows long runs where `rotationIntent=true`, `rotationIntentConfirmed=false`, `tiltBurstBlocksRotation=true`, `fastRotationSamples=0`, and `tiltBurstSamples` grows past 25-40 while `rawLag` remains around 30-60 degrees. The target is capped to 1.0-1.5 degrees per sensor sample, so a real yaw rotation cannot catch up and cannot satisfy the current release condition.

## Problem

The state machine treats tilt and rotation as a binary priority decision. Once tilt burst wins, rotation confirmation is reset on every sample. That protects against false heading jumps, but it also creates a feedback trap for sustained real rotation with small or moderate tilt noise.

## Desired Behavior

Compass follow should be responsive when there is sustained yaw rotation, even if the Android rotation-vector heading contains small tilt artifacts. Tilt should reduce confidence and cap velocity, not always block rotation outright.

The contract:

- First 2-4 suspicious samples are tilt protected.
- Sustained same-direction rotation can escape tilt-burst blocking after a short evidence window.
- Small tilt plus strong yaw uses responsive rotation follow with safe caps.
- Medium tilt uses a lower gain and lower per-sample cap.
- Severe tilt or unstable direction stays in hold/dampen mode.
- No tilt path may reintroduce 14-17 degree target jumps or 6 degree camera-frame jumps.

## Proposed State Model

Add a blocked-rotation evidence counter:

- Count consecutive samples where rotation intent is present while tilt-burst/recovery is blocking it.
- Require the same raw-delta direction across the evidence window.
- Reset the counter on direction change, raw lag returning near target/camera, hold activation, or loss of rotation intent.
- Once the counter reaches the threshold, enter `sustainedRotationEscape`.

`sustainedRotationEscape` does not mean raw heading pass-through. It allows rotation follow using velocity limits and a tilt penalty.

## Confidence And Caps

Use a rotation confidence band based on tilt severity:

- High confidence: sustained yaw, low tilt lag. Target cap roughly 4-7 degrees per sample at normal event cadence.
- Medium confidence: sustained yaw with visible tilt. Target cap roughly 2-4 degrees per sample.
- Low confidence: severe tilt or unstable signal. Target cap remains 0-1.5 degrees per sample or hold.

Camera rendering remains velocity-limited; the render max step should stay below the earlier jumpy behavior.

## Testing

Add regression coverage that checks:

- Sustained blocked rotation cannot remain permanently trapped under `tiltBurstBlocksRotation`.
- Tilt recovery can be escaped by sustained same-direction rotation.
- Visible tilt without sustained rotation still dampens and never passes raw heading directly.
- Confirmed/escaped rotation remains capped and does not produce 14-17 degree target jumps.
- Compass logs expose `sustainedRotationEscape` and blocked-rotation sample count for field diagnosis.

## Implementation Scope

The implementation should stay in the existing MapLibre compass stabilizer and its current tests. It should avoid broad refactors and keep the behavior observable through the existing debug logs.
