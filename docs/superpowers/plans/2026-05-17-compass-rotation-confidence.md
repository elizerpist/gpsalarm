# Compass Rotation Confidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make real compass yaw rotation responsive again while keeping tilt-induced heading artifacts damped and capped.

**Architecture:** Keep the existing MapLibre compass stabilizer, but replace the current all-or-nothing tilt-burst block with a sustained-rotation escape path. Tilt still wins for the first suspicious samples; sustained same-direction yaw can then confirm rotation with a tilt penalty that lowers gain and velocity caps when the signal remains tilt-heavy.

**Tech Stack:** Flutter/Dart, `flutter_test`, existing `DebugConsole` compass diagnostics, MapLibre camera bearing updates.

---

## File Structure

- Modify: `test/widgets/maplibre_compass_follow_test.dart`
  - Adds static regression coverage for the sustained-rotation escape and tilt penalty contract. This test file already validates compass behavior by inspecting `lib/widgets/maplibre_new_view.dart`; keep that pattern.
- Modify: `lib/widgets/maplibre_new_view.dart`
  - Adds blocked-rotation evidence state, reset helper, tilt-penalty constants, sustained escape logic, and extra diagnostics.
- No new production files.

---

### Task 1: Add Failing Regression Test For Sustained Rotation Escape

**Files:**
- Modify: `test/widgets/maplibre_compass_follow_test.dart`
- Test: `test/widgets/maplibre_compass_follow_test.dart`

- [ ] **Step 1: Insert the failing test**

Insert this test inside `group('MapLibre 3D compass follow', () { ... })`, after `gives tilt burst priority over rotation confirmation` and before `dampens all visible below-clamp tilt instead of raw pass-through`:

```dart
    test('lets sustained blocked rotation escape tilt burst damping', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      int intConstant(String name) {
        final match = RegExp(
          'static const int $name'
          r'\s*=\s*([0-9]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return int.parse(match!.group(1)!);
      }

      double doubleConstant(String name) {
        final match = RegExp(
          'static const double $name'
          r'\s*=\s*([0-9.]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return double.parse(match!.group(1)!);
      }

      expect(
        intConstant('_compassBlockedRotationEscapeSamples'),
        inInclusiveRange(5, 8),
        reason:
            'Real yaw should escape the tilt-burst trap after a short sustained evidence window, not after dozens of samples.',
      );
      expect(
        doubleConstant('_compassRotationHighTiltPenalty'),
        inInclusiveRange(0.35, 0.6),
        reason:
            'High tilt confidence should slow rotation follow without falling back to the 1 degree tilt clamp.',
      );

      final stateStart = view.indexOf('DateTime _compassRotationIntentUntil');
      final fpsStart = view.indexOf('DateTime _compassFpsWindowStart', stateStart);
      expect(stateStart, isNonNegative);
      expect(fpsStart, greaterThan(stateStart));
      final stateFields = view.substring(stateStart, fpsStart);

      expect(stateFields, contains('_compassBlockedRotationSamples = 0'));
      expect(stateFields, contains('_compassBlockedRotationDirection = 0'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(stabilizer, contains('blockedRotationCandidate'));
      expect(stabilizer, contains('_compassBlockedRotationSamples++'));
      expect(stabilizer, contains('sustainedRotationEscape'));
      expect(
        stabilizer,
        contains('!sustainedRotationEscape'),
        reason:
            'Tilt burst should block early samples, but sustained same-direction rotation must be able to escape.',
      );
      expect(
        stabilizer,
        contains('_compassFastRotationSamples = _compassRotationIntentSamples'),
        reason:
            'Once escape is proven, rotation follow should become responsive immediately instead of waiting for another full confirmation window.',
      );
      expect(
        stabilizer,
        contains('tiltRecoveryActive = false'),
        reason:
            'Sustained rotation must be able to leave tilt recovery; otherwise real rotation remains lagged for the whole recovery window.',
      );
      expect(stabilizer, contains('sustainedRotationEscape=$sustainedRotationEscape'));
      expect(stabilizer, contains('blockedRotationSamples=$_compassBlockedRotationSamples'));

      final followStart = view.indexOf('double _followCompassRotationIntent({');
      final followEnd = view.indexOf('double _stabilizeCompassHeading({', followStart);
      expect(followStart, isNonNegative);
      expect(followEnd, greaterThan(followStart));
      final follow = view.substring(followStart, followEnd);

      expect(follow, contains('tiltPenalty'));
      expect(follow, contains('_compassRotationFollowMaxRateDegPerSec * tiltPenalty'));
      expect(follow, contains('_compassRotationFollowGain * tiltPenalty'));
    });
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```bash
proot-distro login ubuntu --user flutteruser -- bash -lc 'cd /home/flutteruser/flutterapps/gpsalarm && /home/flutteruser/flutter/bin/flutter test test/widgets/maplibre_compass_follow_test.dart --plain-name "lets sustained blocked rotation escape tilt burst damping"'
```

Expected: FAIL because `_compassBlockedRotationEscapeSamples`, blocked-rotation state fields, `sustainedRotationEscape`, and `tiltPenalty` are not implemented yet.

- [ ] **Step 3: Commit the failing test only if the team accepts red commits**

For this repo, keep the failing test uncommitted until Task 2 makes it pass. Do not commit after this task.

---

### Task 2: Implement Sustained Rotation Escape And Tilt Penalty

**Files:**
- Modify: `lib/widgets/maplibre_new_view.dart`
- Test: `test/widgets/maplibre_compass_follow_test.dart`

- [ ] **Step 1: Add constants**

In `lib/widgets/maplibre_new_view.dart`, near the existing compass rotation constants, change this block:

```dart
  static const double _compassRotationIntentDelta = 18.0;
  static const double _compassRotationIntentRateDegPerSec = 650.0;
  static const int _compassRotationIntentSamples = 3;
  static const double _compassRotationFollowGain = 0.58;
  static const double _compassRotationFollowMaxRateDegPerSec = 180.0;
  static const double _compassRotationFollowSnapDelta = 4.0;
```

To:

```dart
  static const double _compassRotationIntentDelta = 18.0;
  static const double _compassRotationIntentRateDegPerSec = 650.0;
  static const int _compassRotationIntentSamples = 3;
  static const int _compassBlockedRotationEscapeSamples = 6;
  static const double _compassRotationMediumTiltLag = 24.0;
  static const double _compassRotationHighTiltLag = 42.0;
  static const double _compassRotationMediumTiltPenalty = 0.65;
  static const double _compassRotationHighTiltPenalty = 0.45;
  static const double _compassRotationFollowGain = 0.58;
  static const double _compassRotationFollowMaxRateDegPerSec = 180.0;
  static const double _compassRotationFollowSnapDelta = 4.0;
```

- [ ] **Step 2: Add blocked-rotation state fields**

Near the current compass state fields, change:

```dart
  bool _compassTiltHoldArmed = true;
  int _compassTiltBurstSamples = 0;
  int _compassFastRotationSamples = 0;
```

To:

```dart
  bool _compassTiltHoldArmed = true;
  int _compassTiltBurstSamples = 0;
  int _compassFastRotationSamples = 0;
  int _compassBlockedRotationSamples = 0;
  int _compassBlockedRotationDirection = 0;
```

- [ ] **Step 3: Add reset and penalty helpers**

Insert these helpers before `double _stabilizeCompassHeading({`:

```dart
  void _resetCompassBlockedRotationEvidence() {
    _compassBlockedRotationSamples = 0;
    _compassBlockedRotationDirection = 0;
  }

  double _compassRotationTiltPenalty(double cameraLagBefore) {
    final lag = cameraLagBefore.abs();
    if (lag >= _compassRotationHighTiltLag) {
      return _compassRotationHighTiltPenalty;
    }
    if (lag >= _compassRotationMediumTiltLag) {
      return _compassRotationMediumTiltPenalty;
    }
    return 1.0;
  }
```

- [ ] **Step 4: Reset evidence when compass follow starts and when lag has recovered**

In `_startCompassFollow()`, after `_compassFastRotationSamples = 0;`, add:

```dart
    _resetCompassBlockedRotationEvidence();
```

In `_stabilizeCompassHeading`, inside the existing `if (holdReleaseOk) { ... }` block, after `_compassFastRotationSamples = 0;`, add:

```dart
      _resetCompassBlockedRotationEvidence();
```

- [ ] **Step 5: Add blocked-rotation evidence and sustained escape logic**

In `_stabilizeCompassHeading`, replace the current `tiltBurstBlocksRotation` and rotation confirmation section:

```dart
    final tiltBurstBlocksRotation =
        !holdReleaseOk &&
        _compassTiltBurstSamples >= 2 &&
        rawDelta.abs() >= _compassVisibleTiltJitterDelta;
    var rotationIntentConfirmed = _isCompassRotationIntentActive(now);
    if (tiltBurstBlocksRotation || tiltRecoveryActive || holdActive) {
      _compassFastRotationSamples = 0;
      _compassRotationIntentUntil = DateTime.fromMillisecondsSinceEpoch(0);
      rotationIntentConfirmed = false;
    }
    if (rotationIntent &&
        !holdActive &&
        !tiltBurstBlocksRotation &&
        !tiltRecoveryActive) {
      _compassFastRotationSamples++;
      if (_compassFastRotationSamples >= _compassRotationIntentSamples) {
        _compassRotationIntentUntil = now.add(
          _compassRotationIntentGraceDuration,
        );
        rotationIntentConfirmed = true;
      }
    } else if (!holdActive && !rotationIntentConfirmed) {
      _compassFastRotationSamples = 0;
    }
```

With:

```dart
    final blockedRotationDirection = rawDelta == 0 ? 0 : rawDelta.sign.toInt();
    final blockedRotationCandidate =
        rotationIntent &&
        !holdActive &&
        !holdReleaseOk &&
        _compassTiltBurstSamples >= 2 &&
        rawDelta.abs() >= _compassRotationIntentDelta;
    if (blockedRotationCandidate && blockedRotationDirection != 0) {
      if (_compassBlockedRotationDirection == blockedRotationDirection) {
        _compassBlockedRotationSamples++;
      } else {
        _compassBlockedRotationDirection = blockedRotationDirection;
        _compassBlockedRotationSamples = 1;
      }
    } else if (!holdActive) {
      _resetCompassBlockedRotationEvidence();
    }

    final sustainedRotationEscape =
        _compassBlockedRotationSamples >= _compassBlockedRotationEscapeSamples;
    if (sustainedRotationEscape && tiltRecoveryActive) {
      _compassTiltRecoveryUntil = DateTime.fromMillisecondsSinceEpoch(0);
      tiltRecoveryActive = false;
    }

    final tiltBurstBlocksRotation =
        !sustainedRotationEscape &&
        !holdReleaseOk &&
        _compassTiltBurstSamples >= 2 &&
        rawDelta.abs() >= _compassVisibleTiltJitterDelta;
    var rotationIntentConfirmed = _isCompassRotationIntentActive(now);
    if (sustainedRotationEscape && rotationIntent && !holdActive) {
      _compassFastRotationSamples = _compassRotationIntentSamples;
      _compassRotationIntentUntil = now.add(
        _compassRotationIntentGraceDuration,
      );
      rotationIntentConfirmed = true;
      _compassTiltBurstSamples = 0;
    } else if (tiltBurstBlocksRotation || tiltRecoveryActive || holdActive) {
      _compassFastRotationSamples = 0;
      _compassRotationIntentUntil = DateTime.fromMillisecondsSinceEpoch(0);
      rotationIntentConfirmed = false;
    }
    if (rotationIntent &&
        !holdActive &&
        !tiltBurstBlocksRotation &&
        !tiltRecoveryActive) {
      _compassFastRotationSamples++;
      if (_compassFastRotationSamples >= _compassRotationIntentSamples) {
        _compassRotationIntentUntil = now.add(
          _compassRotationIntentGraceDuration,
        );
        rotationIntentConfirmed = true;
      }
    } else if (!holdActive && !rotationIntentConfirmed) {
      _compassFastRotationSamples = 0;
    }
```

- [ ] **Step 6: Reset blocked evidence while holding**

Inside the `if (shouldHold || shouldKeepHolding) { ... }` branch, immediately before `return _lastBearing;`, add:

```dart
      _resetCompassBlockedRotationEvidence();
```

This prevents hold-window samples from carrying stale rotation evidence into the next release.

- [ ] **Step 7: Pass tilt penalty into rotation follow**

In `_stabilizeCompassHeading`, replace:

```dart
    if (rotationIntentConfirmed) {
      return _followCompassRotationIntent(
        heading: heading,
        rawDelta: rawDelta,
        turnRateDegPerSec: turnRateDegPerSec,
        eventDt: eventDt,
        seq: seq,
      );
    }
```

With:

```dart
    if (rotationIntentConfirmed) {
      return _followCompassRotationIntent(
        heading: heading,
        rawDelta: rawDelta,
        turnRateDegPerSec: turnRateDegPerSec,
        eventDt: eventDt,
        seq: seq,
        tiltPenalty: _compassRotationTiltPenalty(cameraLagBefore),
      );
    }
```

- [ ] **Step 8: Apply tilt penalty inside rotation follow**

Change `_followCompassRotationIntent` from:

```dart
  double _followCompassRotationIntent({
    required double heading,
    required double rawDelta,
    required double turnRateDegPerSec,
    required int? eventDt,
    required int seq,
  }) {
    if (rawDelta.abs() <= _compassRotationFollowSnapDelta) {
      return heading;
    }
    final dtSeconds = eventDt != null && eventDt > 0
        ? eventDt / 1000.0
        : _minCompassCameraInterval.inMilliseconds / 1000.0;
    final maxStep = math.max(
      _compassSpikeClampStep,
      _compassRotationFollowMaxRateDegPerSec * dtSeconds,
    );
    final followedDelta = (rawDelta * _compassRotationFollowGain)
        .clamp(-maxStep, maxStep)
        .toDouble();
    final followedHeading = _normalizeBearing(_lastBearing + followedDelta);
    DebugConsole.log(
      'COMPASS_ROTATION_FOLLOW: seq=$seq eventDt=${eventDt ?? -1}ms '
      'raw=${heading.toStringAsFixed(1)} '
      'rawDelta=${rawDelta.toStringAsFixed(1)} '
      'turnRate=${turnRateDegPerSec.toStringAsFixed(1)} '
      'usedDelta=${followedDelta.toStringAsFixed(1)} '
      'heading=${followedHeading.toStringAsFixed(1)} '
      'maxStep=${maxStep.toStringAsFixed(1)}',
    );
    return followedHeading;
  }
```

To:

```dart
  double _followCompassRotationIntent({
    required double heading,
    required double rawDelta,
    required double turnRateDegPerSec,
    required int? eventDt,
    required int seq,
    required double tiltPenalty,
  }) {
    if (rawDelta.abs() <= _compassRotationFollowSnapDelta) {
      return heading;
    }
    final dtSeconds = eventDt != null && eventDt > 0
        ? eventDt / 1000.0
        : _minCompassCameraInterval.inMilliseconds / 1000.0;
    final effectiveGain = _compassRotationFollowGain * tiltPenalty;
    final maxStep = math.max(
      _compassSpikeClampStep,
      _compassRotationFollowMaxRateDegPerSec * tiltPenalty * dtSeconds,
    );
    final followedDelta = (rawDelta * effectiveGain)
        .clamp(-maxStep, maxStep)
        .toDouble();
    final followedHeading = _normalizeBearing(_lastBearing + followedDelta);
    DebugConsole.log(
      'COMPASS_ROTATION_FOLLOW: seq=$seq eventDt=${eventDt ?? -1}ms '
      'raw=${heading.toStringAsFixed(1)} '
      'rawDelta=${rawDelta.toStringAsFixed(1)} '
      'turnRate=${turnRateDegPerSec.toStringAsFixed(1)} '
      'usedDelta=${followedDelta.toStringAsFixed(1)} '
      'heading=${followedHeading.toStringAsFixed(1)} '
      'maxStep=${maxStep.toStringAsFixed(1)} '
      'tiltPenalty=${tiltPenalty.toStringAsFixed(2)}',
    );
    return followedHeading;
  }
```

- [ ] **Step 9: Add diagnostics to tilt trace and start log**

In the `COMPASS_TILT_TRACE` log, after `tiltBurstBlocksRotation=$tiltBurstBlocksRotation`, add:

```dart
        'sustainedRotationEscape=$sustainedRotationEscape '
        'blockedRotationSamples=$_compassBlockedRotationSamples '
```

In the `COMPASS_START` log, after `rotationIntentSamples=$_compassRotationIntentSamples`, add:

```dart
      'blockedRotationEscapeSamples=$_compassBlockedRotationEscapeSamples '
      'rotationTiltLag=$_compassRotationMediumTiltLag/$_compassRotationHighTiltLag '
      'rotationTiltPenalty=$_compassRotationMediumTiltPenalty/$_compassRotationHighTiltPenalty '
```

- [ ] **Step 10: Run the focused test**

Run:

```bash
proot-distro login ubuntu --user flutteruser -- bash -lc 'cd /home/flutteruser/flutterapps/gpsalarm && /home/flutteruser/flutter/bin/flutter test test/widgets/maplibre_compass_follow_test.dart --plain-name "lets sustained blocked rotation escape tilt burst damping"'
```

Expected: PASS.

- [ ] **Step 11: Run all compass-follow tests**

Run:

```bash
proot-distro login ubuntu --user flutteruser -- bash -lc 'cd /home/flutteruser/flutterapps/gpsalarm && /home/flutteruser/flutter/bin/flutter test test/widgets/maplibre_compass_follow_test.dart'
```

Expected: PASS for all tests in `test/widgets/maplibre_compass_follow_test.dart`.

- [ ] **Step 12: Commit the passing test and implementation**

Run:

```bash
git add lib/widgets/maplibre_new_view.dart test/widgets/maplibre_compass_follow_test.dart
git commit -m "Allow sustained compass rotation escape"
```

Expected: one commit containing the regression test and production code.

---

### Task 3: Full Verification And Push

**Files:**
- Verify: repository test suite and git diff

- [ ] **Step 1: Run full Flutter tests**

Run:

```bash
proot-distro login ubuntu --user flutteruser -- bash -lc 'cd /home/flutteruser/flutterapps/gpsalarm && /home/flutteruser/flutter/bin/flutter test'
```

Expected: PASS for the full Flutter test suite.

- [ ] **Step 2: Check whitespace and patch hygiene**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 3: Run analyzer as non-gating evidence**

Run:

```bash
proot-distro login ubuntu --user flutteruser -- bash -lc 'cd /home/flutteruser/flutterapps/gpsalarm && /home/flutteruser/flutter/bin/flutter analyze'
```

Expected: the repo currently has pre-existing analyzer issues. Record whether the count remains in the known pre-existing range and mention analyzer status in the final report. Do not hide analyzer failures.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git diff --stat HEAD~1..HEAD
git status --short
```

Expected: the last implementation commit only changes `lib/widgets/maplibre_new_view.dart` and `test/widgets/maplibre_compass_follow_test.dart`; working tree is clean except for intentional follow-up files.

- [ ] **Step 5: Push commits**

Run:

```bash
git push
```

Expected: push succeeds to the current branch.

---

## Self-Review Notes

Spec coverage:

- Sustained same-direction rotation escape: Task 1 and Task 2 Steps 5-7.
- Small/medium/high tilt confidence behavior: Task 2 Steps 1, 3, 7, and 8.
- No raw heading pass-through for visible tilt: existing test remains in place, Task 2 does not weaken `_isCompassVisibleTiltJitter`.
- No 14-17 degree target jumps or 6 degree render jumps: existing cap tests remain in place, Task 2 keeps `_compassRotationFollowMaxRateDegPerSec` at 180 and `_compassRotationRenderMaxStep` at 3.0.
- Field diagnostics: Task 2 Step 9.

Plan consistency:

- The new helper names match the new tests: `_resetCompassBlockedRotationEvidence`, `_compassRotationTiltPenalty`, `_compassBlockedRotationSamples`, `_compassBlockedRotationDirection`, and `sustainedRotationEscape`.
- The implementation stays inside the existing MapLibre view and static compass-follow test file.
