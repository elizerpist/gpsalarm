import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapLibre 3D compass follow', () {
    test('does not animate high-frequency compass updates', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_minCompassCameraInterval'));
      expect(view, contains('_compassSmoothingGain'));
      expect(view, contains('COMPASS_CAMERA'));
      expect(view, contains('COMPASS_SKIP'));
      expect(view, contains('COMPASS_START'));
      expect(view, contains('COMPASS_STOP'));

      final start = view.indexOf(
        'void _handleCompassEvent(CompassEvent event)',
      );
      final end = view.indexOf('void _set3DMode', start);
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final compassFlow = view.substring(start, end);

      expect(
        compassFlow,
        contains('_safeMoveCamera('),
        reason:
            'Compass follow should use immediate moveCamera updates somewhere in the high-frequency flow; native animations add visible lag and can queue behind sensor data.',
      );
      expect(
        compassFlow,
        isNot(contains('_safeAnimateCamera(')),
        reason: 'High-frequency compass updates must not use animateCamera.',
      );
      expect(
        compassFlow,
        isNot(contains('Duration(milliseconds: 120)')),
        reason:
            'A per-sample native animation duration keeps the map behind the device heading.',
      );
    });

    test('uses low-lag adaptive compass tracking diagnostics', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('Duration(milliseconds: 32)'));
      expect(view, contains('_compassFastTurnGain'));
      expect(view, contains('_compassFastTurnDelta'));
      expect(view, contains('DateTime.now().subtract'));
      expect(view, contains('_minCompassCameraInterval'));
      expect(view, contains('COMPASS_STATS'));

      final start = view.indexOf(
        'void _handleCompassEvent(CompassEvent event)',
      );
      final end = view.indexOf('void _set3DMode', start);
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final method = view.substring(start, end);

      expect(method, contains('turnRate='));
      expect(method, contains('rawLag='));
      expect(method, contains('cameraLag='));
      expect(method, contains('gain='));
    });

    test('reports compass pipeline fps and jitter diagnostics', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassFpsReportInterval'));
      expect(view, contains('_recordCompassFpsRenderTick'));
      expect(view, contains('_recordCompassFpsCamera'));
      expect(view, contains('_logCompassFpsIfNeeded'));
      expect(view, contains('COMPASS_FPS'));
      expect(view, contains('eventHz='));
      expect(view, contains('renderHz='));
      expect(view, contains('cameraHz='));
      expect(view, contains('renderJank='));
      expect(view, contains('renderStall='));
      expect(view, contains('cameraDuty='));
      expect(view, contains('targetLagAvg='));
      expect(view, contains('targetLagMax='));

      final handlerStart = view.indexOf(
        'void _handleCompassEvent(CompassEvent event)',
      );
      final pumpStart = view.indexOf('void _pumpCompassCamera', handlerStart);
      final modeStart = view.indexOf('void _set3DMode', pumpStart);
      expect(handlerStart, isNonNegative);
      expect(pumpStart, greaterThan(handlerStart));
      expect(modeStart, greaterThan(pumpStart));

      final handler = view.substring(handlerStart, pumpStart);
      final pump = view.substring(pumpStart, modeStart);

      expect(handler, contains('_compassFpsWindowEvents++'));
      expect(pump, contains('_recordCompassFpsRenderTick('));
      expect(pump, contains('_recordCompassFpsCamera('));
      expect(pump, contains('_logCompassFpsIfNeeded(now'));
    });

    test('targets a 60Hz compass render cadence', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final lines = view.split('\n');
      final renderIntervalLine = lines.firstWhere(
        (line) => line.contains('_compassRenderInterval'),
      );
      final renderJankLine = lines.firstWhere(
        (line) => line.contains('_compassRenderJankMs'),
      );
      final renderStallLine = lines.firstWhere(
        (line) => line.contains('_compassRenderStallMs'),
      );

      expect(
        renderIntervalLine,
        contains('Duration(milliseconds: 16)'),
        reason:
            'A 24ms compass render pump caps camera updates around 41Hz, so it cannot deliver a 60fps compass-follow path.',
      );
      expect(renderJankLine, contains('= 25;'));
      expect(renderStallLine, contains('= 50;'));
      expect(
        view,
        contains('desiredRenderMs=\${_compassRenderInterval.inMilliseconds}'),
      );
    });

    test('keeps slow compass turns below the visible deadzone', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final minDeltaMatch = RegExp(
        r'_compassMinCameraDelta\s*=\s*([0-9.]+);',
      ).firstMatch(view);
      expect(minDeltaMatch, isNotNull);
      final minDelta = double.parse(minDeltaMatch!.group(1)!);

      expect(
        minDelta,
        lessThanOrEqualTo(0.18),
        reason:
            'Slow compass turns should not wait for nearly half a degree before moving the camera; that makes low-speed rotation step visibly.',
      );
      expect(view, contains('minDelta=\$_compassMinCameraDelta'));
    });

    test('coalesces compass samples through a frame-paced render pump', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassRenderInterval'));
      expect(view, contains('_compassRenderTicker'));
      expect(view, contains('createTicker'));
      expect(view, contains('_startCompassRenderPump'));
      expect(view, contains('_pumpCompassCamera'));
      expect(view, contains('_compassRenderSlowGain'));
      expect(view, contains('_compassRenderFastGain'));
      expect(view, contains('path=ticker-pump'));
      expect(
        view,
        isNot(contains('Timer.periodic(_compassRenderInterval')),
        reason:
            'Timer.periodic can drift and catch up after slow frames; the compass pump should be driven by Flutter vsync.',
      );

      final handlerStart = view.indexOf(
        'void _handleCompassEvent(CompassEvent event)',
      );
      final pumpStart = view.indexOf('void _pumpCompassCamera', handlerStart);
      final modeStart = view.indexOf('void _set3DMode', pumpStart);
      expect(handlerStart, isNonNegative);
      expect(pumpStart, greaterThan(handlerStart));
      expect(modeStart, greaterThan(pumpStart));

      final handler = view.substring(handlerStart, pumpStart);
      final pump = view.substring(pumpStart, modeStart);

      expect(
        handler,
        isNot(contains('_safeMoveCamera(')),
        reason:
            'Sensor events should only update the target bearing; native camera moves should be frame-paced for smoother visual cadence.',
      );
      expect(pump, contains('_safeMoveCamera('));
      expect(pump, isNot(contains('_safeAnimateCamera(')));
    });

    test('guards compass heading spikes caused by device tilt', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassSpikeClampDelta'));
      expect(view, contains('_compassSpikeClampRateDegPerSec'));
      expect(view, contains('_compassSpikeClampStep'));
      expect(view, contains('_stabilizeCompassHeading'));
      expect(view, contains('COMPASS_SPIKE_CLAMP'));

      final handlerStart = view.indexOf(
        'void _handleCompassEvent(CompassEvent event)',
      );
      final pumpStart = view.indexOf('void _pumpCompassCamera', handlerStart);
      expect(handlerStart, isNonNegative);
      expect(pumpStart, greaterThan(handlerStart));
      final handler = view.substring(handlerStart, pumpStart);

      expect(handler, contains('_stabilizeCompassHeading('));
      expect(handler, contains('usedDelta='));
      expect(
        handler,
        contains('_compassGainFor(usedDelta, turnRateDegPerSec)'),
        reason:
            'Tilt-induced sensor spikes should be clamped before the target bearing is advanced.',
      );
    });

    test('logs tilt spike decisions with clamp reasons', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassTiltTraceDelta'));
      expect(view, contains('_compassTiltTraceRateDegPerSec'));
      expect(view, contains('_shouldLogCompassTiltTrace'));
      expect(view, contains('_compassTiltTraceReason'));
      expect(view, contains('COMPASS_TILT_TRACE'));
      expect(view, contains('tiltTraceDelta='));
      expect(view, contains('tiltTraceRate='));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      for (final field in [
        'action=',
        'reason=',
        'targetBefore=',
        'camera=',
        'fromSettled=',
        'deltaOk=',
        'rateOk=',
        'rawLagBefore=',
        'cameraLagBefore=',
      ]) {
        expect(stabilizer, contains(field));
      }
    });

    test('clamps medium tilt spikes instead of passing them through', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double constant(String name) {
        final match = RegExp(
          'static const double $name'
          r'\s*=\s*([0-9.]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return double.parse(match!.group(1)!);
      }

      expect(
        constant('_compassSpikeClampDelta'),
        lessThanOrEqualTo(12.0),
        reason:
            'The latest tilt logs show 12-17 degree sensor jumps passing through as below-threshold and visibly snapping the map.',
      );
      expect(
        constant('_compassSpikeClampRateDegPerSec'),
        lessThanOrEqualTo(250.0),
        reason:
            'Tilt jumps around 280-410 deg/s must be treated as spikes, not normal compass movement.',
      );
      expect(
        constant('_compassSpikeClampStep'),
        lessThanOrEqualTo(6.0),
        reason:
            'Even clamped tilt bursts should not move the camera by 10 degrees per sensor sample.',
      );
      expect(view, contains('_compassSpikeClampLagDelta'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(stabilizer, contains('lagOk='));
      expect(stabilizer, contains('deltaOk &&'));
      expect(stabilizer, contains('(rateOk || lagOk)'));
      expect(
        stabilizer,
        isNot(contains('fromSettledMotion &&')),
        reason:
            'The prev-delta-chain path was letting 20+ degree tilt spikes pass through after a previous medium spike.',
      );
      expect(
        view,
        isNot(contains("return 'prev-delta-chain';")),
        reason:
            'Previous-delta state should remain diagnostic only; it must not be a pass-through reason for tilt spikes.',
      );
    });

    test('holds severe tilt bursts instead of integrating clamp steps', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassTiltHoldDelta'));
      expect(view, contains('_compassTiltHoldReleaseDelta'));
      expect(view, contains('_compassTiltHoldDuration'));
      expect(view, contains('_compassTiltHoldUntil'));
      expect(view, contains('_isCompassTiltHoldActive'));
      expect(view, contains('_shouldHoldCompassTilt'));
      expect(view, contains('COMPASS_TILT_HOLD'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);
      final holdStart = stabilizer.indexOf('COMPASS_TILT_HOLD');
      final clampStart = stabilizer.indexOf('final clampedDelta');

      expect(holdStart, isNonNegative);
      expect(clampStart, greaterThan(holdStart));
      expect(stabilizer, contains('_compassTiltHoldUntil ='));
      expect(stabilizer, contains('now.add(_compassTiltHoldDuration)'));
      expect(stabilizer, contains('return _lastBearing;'));
      expect(stabilizer, contains('holdActive='));
      expect(stabilizer, contains('holdReleaseOk='));
      expect(stabilizer, contains('reason=hold-window'));
    });

    test('keeps tilt hold short and rate-only jitter damped', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double durationMillis(String name) {
        final match = RegExp(
          'static const Duration $name'
          r'\s*=\s*Duration\(milliseconds:\s*([0-9]+)\);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return double.parse(match!.group(1)!);
      }

      double constant(String name) {
        final match = RegExp(
          'static const double $name'
          r'\s*=\s*([0-9.]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return double.parse(match!.group(1)!);
      }

      expect(
        durationMillis('_compassTiltHoldDuration'),
        lessThanOrEqualTo(180),
        reason:
            'A 650ms hold repeatedly restarted during tilt and blocked intentional rotation for several seconds.',
      );
      expect(
        constant('_compassRateOnlyJitterDelta'),
        greaterThanOrEqualTo(8.0),
        reason:
            'The logs show 9-11 degree delta-below-clamp samples passing through at high rate and causing side tremble.',
      );
      expect(view, contains('_compassRateOnlyJitterGain'));
      expect(view, contains('_dampenCompassTiltJitter'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(
        stabilizer,
        contains('!holdActive'),
        reason:
            'Severe tilt samples must not keep extending the hold window while the user is intentionally rotating.',
      );
      expect(stabilizer, contains('_dampenCompassTiltJitter('));
      expect(view, contains("return 'rate-only-jitter';"));
    });

    test('dampens tilt stall pass-through instead of snapping target', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double constant(String name) {
        final match = RegExp(
          'static const double $name'
          r'\s*=\s*([0-9.]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return double.parse(match!.group(1)!);
      }

      int intConstant(String name) {
        final match = RegExp(
          'static const int $name'
          r'\s*=\s*([0-9]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return int.parse(match!.group(1)!);
      }

      expect(
        constant('_compassSpikeClampStep'),
        lessThanOrEqualTo(4.0),
        reason:
            'Tilt+rotation bursts were still advancing the camera by repeated 6 degree clamp steps.',
      );
      expect(
        intConstant('_compassTiltJitterStallEventMs'),
        lessThanOrEqualTo(100),
        reason:
            'The logs show 97-154ms stalled samples passing through as 10-12 degree target jumps.',
      );
      expect(view, contains('_compassTiltJitterMaxStep'));
      expect(view, contains('_isCompassTiltStallJitter'));
      expect(view, contains('_dampenCompassTiltJitter'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(view, contains("return 'tilt-stall-jitter';"));
      expect(stabilizer, contains('eventDt >= _compassTiltJitterStallEventMs'));
      expect(
        stabilizer,
        contains('if (tiltJitter) return dampedHeading;'),
        reason:
            'Stalled tilt jitter must be damped even when the old clamp predicate is true.',
      );
    });

    test('treats visible below-clamp tilt deltas as damped jitter', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassVisibleTiltJitterDelta'));
      expect(view, contains('_isCompassVisibleTiltJitter'));
      expect(view, contains("return 'visible-tilt-jitter';"));
      expect(view, contains('reason=\$tiltJitterReason'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(
        stabilizer,
        contains('_isCompassVisibleTiltJitter('),
        reason:
            'The logs show 8-12 degree tilt deltas passing through because they sit below the old 12 degree clamp threshold.',
      );
      expect(
        stabilizer,
        contains('if (tiltJitter) return dampedHeading;'),
        reason:
            'Visible tilt jitter should be damped before the pass-through path can return the raw heading.',
      );
    });

    test('uses recovery damping after severe tilt hold', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassTiltRecoveryDuration'));
      expect(view, contains('_compassTiltRecoveryUntil'));
      expect(view, contains('_compassTiltRecoveryGain'));
      expect(view, contains('_compassTiltRecoveryMaxStep'));
      expect(view, contains("return 'tilt-recovery';"));
      expect(view, contains('reason=\$tiltJitterReason'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(stabilizer, contains('_compassTiltRecoveryUntil ='));
      expect(stabilizer, contains('_isCompassTiltRecoveryActive(now)'));
      expect(
        stabilizer,
        contains('tiltRecoveryActive'),
        reason:
            'After the short hold expires, severe tilt should recover through low-confidence damping instead of immediately resuming clamp steps.',
      );
    });

    test('keeps tilt recovery ahead of rotation confidence', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassRotationIntentDelta'));
      expect(view, contains('_compassRotationIntentRateDegPerSec'));
      expect(view, contains('_compassRotationIntentSamples'));
      expect(view, contains('_compassFastRotationSamples'));
      expect(view, contains('_isCompassRotationIntent'));
      expect(view, contains('rotationIntentConfirmed'));
      expect(view, contains('rotationIntent='));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(
        stabilizer,
        contains('(tiltRecoveryActive && !lagFollowCandidate) ||'),
        reason:
            'Recovery remains a low-confidence compass state unless a large persistent lag proves rotation catch-up.',
      );
      expect(
        stabilizer,
        contains('(!tiltRecoveryActive || lagFollowCandidate)'),
        reason:
            'Rotation candidates should only accumulate during recovery when persistent lag is present.',
      );
      expect(
        stabilizer,
        isNot(contains('if (rotationIntentConfirmed && tiltRecoveryActive)')),
        reason:
            'Confirmed rotation must not automatically escape tilt recovery; recovery has priority.',
      );
      expect(
        stabilizer,
        contains('_compassFastRotationSamples = 0;'),
        reason:
            'The fast-rotation confidence state must reset when motion settles or compass follow restarts.',
      );
    });

    test('uses sensor fallback when the compass render pump stalls', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassRenderFallbackStallMs'));
      expect(view, contains('_compassRenderFallbackDelta'));
      expect(view, contains('_shouldUseCompassSensorFallback'));
      expect(view, contains("path: 'sensor-fallback'"));
      expect(view, contains('sensorFallback='));

      final handlerStart = view.indexOf(
        'void _handleCompassEvent(CompassEvent event)',
      );
      final pumpStart = view.indexOf('void _pumpCompassCamera', handlerStart);
      final modeStart = view.indexOf('void _set3DMode', pumpStart);
      expect(handlerStart, isNonNegative);
      expect(pumpStart, greaterThan(handlerStart));
      expect(modeStart, greaterThan(pumpStart));

      final handler = view.substring(handlerStart, pumpStart);
      final pump = view.substring(pumpStart, modeStart);

      expect(handler, contains('_shouldUseCompassSensorFallback('));
      expect(handler, contains("_pumpCompassCamera(path: 'sensor-fallback')"));
      expect(
        pump,
        contains('_clampCompassRenderStep('),
        reason:
            'A stalled render pump must catch up through bounded camera steps, not one large delayed jump.',
      );
    });

    test(
      'tracks confirmed rotation through smooth follow instead of spike clamp',
      () {
        final view = File(
          'lib/widgets/maplibre_new_view.dart',
        ).readAsStringSync();

        expect(view, contains('_compassRotationFollowGain'));
        expect(view, contains('_compassRotationFollowMaxRateDegPerSec'));
        expect(view, contains('_followCompassRotationIntent'));
        expect(view, contains('COMPASS_ROTATION_FOLLOW'));

        final stabilizerStart = view.indexOf(
          'double _stabilizeCompassHeading({',
        );
        final recordStart = view.indexOf(
          'void _recordCompassEventDt',
          stabilizerStart,
        );
        expect(stabilizerStart, isNonNegative);
        expect(recordStart, greaterThan(stabilizerStart));
        final stabilizer = view.substring(stabilizerStart, recordStart);

        final rotationFollowStart = stabilizer.indexOf(
          '_followCompassRotationIntent(',
        );
        final jitterStart = stabilizer.indexOf('_dampenCompassTiltJitter(');
        final clampStart = stabilizer.indexOf('final clampedDelta');
        expect(rotationFollowStart, isNonNegative);
        expect(jitterStart, greaterThan(rotationFollowStart));
        expect(clampStart, greaterThan(rotationFollowStart));
        expect(
          stabilizer,
          contains('!tiltBurstBlocksRotation'),
          reason:
              'Rotation follow should start only while the candidate window is still tilt-free.',
        );
      },
    );

    test('keeps unconfirmed tilt jitter subtle', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double constant(String name) {
        final match = RegExp(
          'static const double $name'
          r'\s*=\s*([0-9.]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return double.parse(match!.group(1)!);
      }

      expect(
        constant('_compassVisibleTiltJitterGain'),
        lessThanOrEqualTo(0.16),
        reason:
            'Unconfirmed tilt+rotation bursts still moved 2 degrees per sensor sample and looked too sensitive.',
      );
      expect(
        constant('_compassVisibleTiltJitterMaxStep'),
        lessThanOrEqualTo(1.4),
        reason:
            'Tilt jitter should drift subtly until sustained same-direction yaw is confirmed.',
      );
    });

    test('keeps tilt bursts from confirming rotation too early', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double doubleConstant(String name) {
        final match = RegExp(
          'static const double $name'
          r'\s*=\s*([0-9.]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return double.parse(match!.group(1)!);
      }

      int intConstant(String name) {
        final match = RegExp(
          'static const int $name'
          r'\s*=\s*([0-9]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return int.parse(match!.group(1)!);
      }

      expect(
        intConstant('_compassRotationIntentSamples'),
        greaterThanOrEqualTo(3),
        reason:
            'Two high-rate samples let tilt bursts enter rotation follow before the tilt dampener can absorb them.',
      );
      expect(
        doubleConstant('_compassRenderMaxStep'),
        lessThanOrEqualTo(4.0),
        reason:
            'Unconfirmed tilt and plain jitter should stay on the subtle base render clamp.',
      );
    });

    test('gives tilt burst priority over rotation confirmation', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(
        stabilizer,
        contains('tiltBurstBlocksRotation'),
        reason:
            'Once a sequence is already classified as tilt-burst, the same sequence must not be promoted into rotation follow.',
      );
      expect(
        stabilizer,
        contains('!tiltBurstBlocksRotation'),
        reason:
            'Rotation confirmation must require a tilt-free candidate window.',
      );
      expect(
        stabilizer,
        contains(
          '_compassRotationIntentUntil = DateTime.fromMillisecondsSinceEpoch(0);',
        ),
        reason:
            'Tilt-burst/recovery should clear any active rotation grace window instead of letting stale confirmation drive 6 degree camera jumps.',
      );
    });

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
        lessThanOrEqualTo(3),
        reason:
            'The logs show rotation now feels fluent but starts late because tilt-burst waits 5-6 samples before escape.',
      );
      expect(
        doubleConstant('_compassRotationFollowMaxStep'),
        inInclusiveRange(8.0, 12.0),
        reason:
            'Confirmed yaw should catch up with bounded follow steps instead of being slowed by accumulated camera lag.',
      );

      final stateStart = view.indexOf('DateTime _compassRotationIntentUntil');
      final fpsStart = view.indexOf(
        'DateTime _compassFpsWindowStart',
        stateStart,
      );
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
      expect(
        stabilizer,
        contains('sustainedRotationEscape=\$sustainedRotationEscape'),
      );
      expect(
        stabilizer,
        contains('blockedRotationSamples=\$_compassBlockedRotationSamples'),
      );

      final followStart = view.indexOf('double _followCompassRotationIntent({');
      final followEnd = view.indexOf(
        'double _stabilizeCompassHeading({',
        followStart,
      );
      expect(followStart, isNonNegative);
      expect(followEnd, greaterThan(followStart));
      final follow = view.substring(followStart, followEnd);

      expect(follow, contains('required bool rotationIntent'));
      expect(follow, contains('_compassRotationFollowMaxStep'));
      expect(follow, contains('_compassRotationGraceMaxStep'));
      expect(
        follow,
        isNot(contains('_compassRotationFollowGain * tiltPenalty')),
      );
      expect(
        follow,
        isNot(contains('_compassRotationFollowMaxRateDegPerSec * tiltPenalty')),
      );
    });

    test('dampens all visible below-clamp tilt instead of raw pass-through', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final visibleStart = view.indexOf('bool _isCompassVisibleTiltJitter({');
      final visibleEnd = view.indexOf('bool _isCompassTiltStallJitter({');
      expect(visibleStart, isNonNegative);
      expect(visibleEnd, greaterThan(visibleStart));
      final visibleTilt = view.substring(visibleStart, visibleEnd);

      expect(
        visibleTilt,
        contains('return !deltaOk &&'),
        reason:
            'Below-clamp visible tilt should enter the damped path before raw heading pass-through.',
      );
      expect(
        visibleTilt,
        isNot(contains('rawDelta.abs() >= _compassFastTurnDelta')),
        reason:
            'The 6-12 degree visible tilt range must not depend on the old fast-turn threshold to be damped.',
      );
      expect(
        visibleTilt,
        isNot(contains('rateOk || lagOk')),
        reason:
            'Visible tilt should not pass through raw just because rate and camera lag sit under their larger clamp thresholds.',
      );
    });

    test('uses a separate render clamp for confirmed rotation', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

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
        doubleConstant('_compassRenderMaxStep'),
        lessThanOrEqualTo(4.0),
        reason: 'Tilt protection should keep the base render clamp subtle.',
      );
      expect(
        doubleConstant('_compassRotationRenderMaxStep'),
        inInclusiveRange(4.0, 5.5),
        reason:
            'Confirmed rotation needs a slightly larger render cap to catch up after dropped camera ticks without snapping the target.',
      );
      expect(
        doubleConstant('_compassRotationFollowMaxRateDegPerSec'),
        greaterThanOrEqualTo(240.0),
        reason:
            'Confirmed rotation still needs enough velocity to avoid feeling detached.',
      );
      expect(
        doubleConstant('_compassRotationFollowMaxRateDegPerSec'),
        lessThanOrEqualTo(360.0),
        reason:
            'Rotation follow should stay velocity-limited so dropped sensor frames do not create unbounded target jumps.',
      );
      expect(
        view,
        contains('rotationResponsive: _isCompassRotationIntentActive(now)'),
        reason:
            'Only confirmed rotation should use the larger render step; tilt/unconfirmed jitter must keep the base clamp.',
      );
    });

    test('logs compass decision inputs separately from action outputs', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(stabilizer, contains('COMPASS_DECISION'));
      for (final field in [
        'mode=',
        'rotationGraceActive=',
        'rotationGraceMs=',
        'tiltPenaltySource=',
        'tiltPenaltyBand=',
        'tiltCandidate=',
        'tiltJitter=',
        'visibleTiltJitter=',
        'shouldHold=',
        'shouldKeepHolding=',
        'blockedRotationCandidate=',
        'blockedRotationDirection=',
        'rawLagBefore=',
        'cameraLagBefore=',
        'followGain=',
        'followMaxStep=',
      ]) {
        expect(stabilizer, contains(field));
      }
    });

    test('logs compass camera render decision details', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final pumpStart = view.indexOf('void _pumpCompassCamera');
      final modeStart = view.indexOf('void _set3DMode', pumpStart);
      expect(pumpStart, isNonNegative);
      expect(modeStart, greaterThan(pumpStart));
      final pump = view.substring(pumpStart, modeStart);

      for (final field in [
        'rotationResponsive=',
        'renderMaxStep=',
        'cameraIntervalMs=',
        'renderIntervalMs=',
        'renderStallMs=',
        'firstCameraUpdate=',
      ]) {
        expect(pump, contains(field));
      }
    });

    test('uses sensor-to-sensor delta for rotation rate', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final handleStart = view.indexOf('void _handleCompassEvent');
      final pumpStart = view.indexOf('void _pumpCompassCamera', handleStart);
      expect(handleStart, isNonNegative);
      expect(pumpStart, greaterThan(handleStart));
      final handle = view.substring(handleStart, pumpStart);

      expect(handle, contains('previousRawCompassHeading'));
      expect(handle, contains('sensorDelta'));
      expect(
        handle,
        contains('sensorDelta / (eventDt / 1000.0)'),
        reason:
            'A frozen target plus hand tilt created large rawDelta on every event; rotation rate must come from raw compass sample-to-sample motion instead.',
      );
      expect(
        handle,
        isNot(contains('rawDelta / (eventDt / 1000.0)')),
        reason:
            'Using target lag as turn rate misclassifies held tilt offsets as fast yaw.',
      );
    });

    test('does not treat rotation lag as tilt confidence', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(
        view,
        isNot(contains('tiltPenaltySource=cameraLag')),
        reason:
            'The field logs proved camera lag is mostly rotation backlog; it must not be reused as tilt confidence.',
      );
      expect(view, contains('tiltPenaltySource=rotationMode'));

      final followStart = view.indexOf('double _followCompassRotationIntent({');
      final followEnd = view.indexOf(
        'void _resetCompassBlockedRotationEvidence',
        followStart,
      );
      expect(followStart, isNonNegative);
      expect(followEnd, greaterThan(followStart));
      final follow = view.substring(followStart, followEnd);

      expect(follow, contains('required bool rotationIntent'));
      expect(
        follow,
        isNot(contains('_compassRotationFollowGain * tiltPenalty')),
      );
      expect(
        follow,
        isNot(contains('_compassRotationFollowMaxRateDegPerSec * tiltPenalty')),
      );
    });

    test('caps confirmed rotation and grace coast follow steps', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double constant(String name) {
        final match = RegExp(
          'static const double $name'
          r'\s*=\s*([0-9.]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return double.parse(match!.group(1)!);
      }

      expect(
        constant('_compassRotationFollowMaxStep'),
        inInclusiveRange(8.0, 12.0),
        reason:
            'Large real rotation should catch up, but not produce huge target jumps after stalled sensor frames.',
      );
      expect(
        constant('_compassRotationGraceMaxStep'),
        lessThanOrEqualTo(4.5),
        reason:
            'When rotation intent has dropped but grace is still active, follow should coast without large snaps.',
      );

      final followStart = view.indexOf('double _followCompassRotationIntent({');
      final followEnd = view.indexOf(
        'void _resetCompassBlockedRotationEvidence',
        followStart,
      );
      expect(followStart, isNonNegative);
      expect(followEnd, greaterThan(followStart));
      final follow = view.substring(followStart, followEnd);

      expect(follow, contains('_compassRotationFollowMaxStep'));
      expect(follow, contains('_compassRotationGraceMaxStep'));
      expect(follow, contains('rotationIntent'));
    });

    test('releases rotation grace before visible tilt jitter is integrated', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_shouldReleaseCompassRotationGrace'));
      expect(view, contains('_compassRotationGraceReleaseDelta'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(stabilizer, contains('releaseRotationGrace'));
      expect(stabilizer, contains('visibleTiltJitter'));
      expect(
        stabilizer,
        contains(
          '_compassRotationIntentUntil = DateTime.fromMillisecondsSinceEpoch(0);',
        ),
      );
    });

    test('keeps rotation intent out of severe tilt hold', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(
        stabilizer,
        contains('!rotationEvidence &&'),
        reason:
            'A same-direction rotation or catch-up candidate should be damped or followed, not frozen by a tilt hold window.',
      );
      expect(stabilizer, contains('holdBlockedByRotation='));
    });

    test('absorbs tilt burst, stall, and recovery without target drift', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double constant(String name) {
        final match = RegExp(
          'static const double $name'
          r'\s*=\s*([0-9.]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return double.parse(match!.group(1)!);
      }

      expect(constant('_compassRateOnlyJitterGain'), equals(0.0));
      expect(constant('_compassTiltJitterMaxStep'), equals(0.0));
      expect(constant('_compassTiltRecoveryGain'), equals(0.0));
      expect(constant('_compassTiltRecoveryMaxStep'), equals(0.0));

      final dampenStart = view.indexOf('double _dampenCompassTiltJitter({');
      final followStart = view.indexOf(
        'double _followCompassRotationIntent({',
        dampenStart,
      );
      expect(dampenStart, isNonNegative);
      expect(followStart, greaterThan(dampenStart));
      final dampen = view.substring(dampenStart, followStart);

      expect(dampen, contains('tiltAbsorbed='));
      expect(
        dampen,
        contains('_lastBearing + dampedDelta'),
        reason:
            'The tilt path should continue returning a target derived from the previous target, not raw sensor heading.',
      );
    });

    test('does not open severe tilt hold on stalled tilt frames', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(
        stabilizer,
        contains('!stalledEvent &&'),
        reason:
            'The latest log shows a 213ms stalled tilt frame opened a severe hold, which then caused recovery jumps; stalled tilt should stay in absorbed damping.',
      );
    });

    test('uses persistent compass lag as rotation catch-up evidence', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_isCompassLagFollowCandidate'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(stabilizer, contains('lagFollowCandidate'));
      expect(stabilizer, contains('rotationIntent || lagFollowCandidate'));
      expect(
        stabilizer,
        contains('blockedRotationCandidate = lagFollowCandidate'),
        reason:
            'The latest rotation log froze with sensorDelta near zero but 30-70 degrees of target/camera lag; persistent lag must enter rotation-follow instead of waiting for sensor rate.',
      );
    });

    test('does not let tilt burst or severe hold lock rotation catch-up lag', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(
        stabilizer,
        contains('!lagFollowCandidate &&'),
        reason:
            'Large persistent lag is rotation catch-up evidence; tilt-burst absorb and severe hold must not lock that path.',
      );
      expect(
        stabilizer,
        contains('!tiltRecoveryActive || lagFollowCandidate'),
        reason:
            'Recovery damping should not keep absorbing real rotation once large lag is present again.',
      );
    });

    test('keeps visible tilt integration below a visible one-degree drift', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double constant(String name) {
        final match = RegExp(
          'static const double $name'
          r'\s*=\s*([0-9.]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return double.parse(match!.group(1)!);
      }

      expect(
        constant('_compassVisibleTiltJitterGain'),
        equals(0.0),
        reason:
            'Hand tremor while tilting still integrated 0.4 degrees per sample at 25Hz, so visible tilt must be absorbed instead of followed.',
      );
      expect(
        constant('_compassVisibleTiltJitterMaxStep'),
        equals(0.0),
        reason:
            'Repeated visible tilt samples should not move the compass target at all.',
      );
    });

    test('absorbs residual tilt settle tremor before raw pass-through', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double constant(String name) {
        final match = RegExp(
          'static const double $name'
          r'\s*=\s*([0-9.]+);',
          multiLine: true,
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be declared');
        return double.parse(match!.group(1)!);
      }

      expect(view, contains('_compassTiltSettleUntil'));
      expect(view, contains('_compassTiltSettleDuration'));
      expect(view, contains('_isCompassTiltSettleJitter'));
      expect(
        constant('_compassTiltSettleDelta'),
        lessThan(constant('_compassVisibleTiltJitterDelta')),
        reason:
            'Residual tilt tremor below the visible-jitter threshold should still be absorbed briefly instead of passing raw heading through.',
      );

      final jitterStart = view.indexOf('bool _isCompassTiltJitter({');
      final jitterEnd = view.indexOf('String _compassTiltJitterReason({');
      expect(jitterStart, isNonNegative);
      expect(jitterEnd, greaterThan(jitterStart));
      final jitter = view.substring(jitterStart, jitterEnd);

      expect(jitter, contains('_isCompassTiltSettleJitter'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(stabilizer, contains('tiltSettleActive'));
      expect(
        stabilizer,
        contains(
          '_compassTiltSettleUntil = now.add(_compassTiltSettleDuration)',
        ),
        reason:
            'Visible tilt samples should arm a short settle window so the release-side wobble cannot move the target.',
      );
    });

    test('tilt settle deadband does not block rotation evidence', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(stabilizer, contains('final tiltSettleActive'));
      expect(
        stabilizer,
        contains('!rotationEvidence &&'),
        reason:
            'The residual tilt deadband is only for non-rotation tremor; real rotation evidence must bypass it.',
      );
      expect(
        stabilizer,
        contains('tiltSettleActive: tiltSettleActive'),
        reason:
            'The stabilizer should pass the rotation-gated settle state into the jitter classifier.',
      );
    });

    test(
      'uses adaptive rotation catch-up instead of fixed six degree target steps',
      () {
        final view = File(
          'lib/widgets/maplibre_new_view.dart',
        ).readAsStringSync();

        double constant(String name) {
          final match = RegExp(
            'static const double $name'
            r'\s*=\s*([0-9.]+);',
            multiLine: true,
          ).firstMatch(view);
          expect(match, isNotNull, reason: '$name should be declared');
          return double.parse(match!.group(1)!);
        }

        expect(
          constant('_compassRotationFollowMaxStep'),
          greaterThan(6.0),
          reason:
              'The latest rotation log shows repeated usedDelta=6.0 while rawLag grows beyond 50 degrees; the target follow cap must be high enough to catch up.',
        );
        expect(view, contains('_compassRotationFollowLagBoostDelta'));
        expect(view, contains('_compassRotationFollowLagBoostStep'));

        final followStart = view.indexOf(
          'double _followCompassRotationIntent({',
        );
        final followEnd = view.indexOf(
          'void _resetCompassBlockedRotationEvidence',
          followStart,
        );
        expect(followStart, isNonNegative);
        expect(followEnd, greaterThan(followStart));
        final follow = view.substring(followStart, followEnd);

        expect(follow, contains('lagBoostStep'));
        expect(
          follow,
          contains('rawDelta.abs() >= _compassRotationFollowLagBoostDelta'),
        );
        expect(follow, contains('modeMaxStep + lagBoostStep'));
      },
    );

    test(
      'keeps recent tilt bursts quarantined from spike clamp and lag follow',
      () {
        final view = File(
          'lib/widgets/maplibre_new_view.dart',
        ).readAsStringSync();

        expect(view, contains('_compassTiltQuarantineUntil'));
        expect(view, contains('_compassTiltQuarantineDuration'));
        expect(view, contains('_isCompassTiltQuarantineActive'));
        expect(view, contains('_compassTiltQuarantineDelta'));
        expect(view, contains("return 'tilt-quarantine-jitter';"));

        final lagCandidateStart = view.indexOf(
          'bool _isCompassLagFollowCandidate({',
        );
        final lagCandidateEnd = view.indexOf(
          'bool _shouldHoldCompassTilt',
          lagCandidateStart,
        );
        expect(lagCandidateStart, isNonNegative);
        expect(lagCandidateEnd, greaterThan(lagCandidateStart));
        final lagCandidate = view.substring(lagCandidateStart, lagCandidateEnd);
        expect(lagCandidate, contains('tiltQuarantineActive'));
        expect(lagCandidate, contains('!tiltQuarantineActive'));

        final stabilizerStart = view.indexOf(
          'double _stabilizeCompassHeading({',
        );
        final recordStart = view.indexOf(
          'void _recordCompassEventDt',
          stabilizerStart,
        );
        expect(stabilizerStart, isNonNegative);
        expect(recordStart, greaterThan(stabilizerStart));
        final stabilizer = view.substring(stabilizerStart, recordStart);

        expect(stabilizer, contains('tiltQuarantineActive'));
        expect(
          stabilizer,
          contains('tiltQuarantineActive: tiltQuarantineActive'),
        );
        expect(
          stabilizer,
          contains(
            '_compassTiltQuarantineUntil = now.add(_compassTiltQuarantineDuration)',
          ),
          reason:
              'Visible tilt and tilt bursts should arm a longer quarantine so 13-22 degree tilt tremor cannot enter spike-clamp or lag-follow.',
        );
      },
    );

    test('routes sensor rotation before the isolated tilt stabilizer', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassRotationSensorMinDelta'));
      expect(view, contains('_compassRotationSensorMaxStep'));

      final wrapperStart = view.indexOf('double _stabilizeCompassHeading({');
      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(wrapperStart, isNonNegative);
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(wrapperStart));

      final wrapper = view.substring(wrapperStart, rotationStart);
      expect(wrapper, contains('required double sensorDelta'));
      expect(wrapper, contains('_followCompassSensorRotation('));
      expect(wrapper, contains('_stabilizeCompassTilt('));
      expect(
        wrapper.indexOf('_followCompassSensorRotation('),
        lessThan(wrapper.indexOf('_stabilizeCompassTilt(')),
        reason:
            'Rotation must get the raw sensor-to-sensor delta before the tilt state machine can absorb the sample.',
      );
      expect(wrapper, contains('sensorDelta: sensorDelta'));

      final rotation = view.substring(rotationStart, tiltStart);
      expect(rotation, contains('sensorDelta'));
      expect(rotation, contains('_lastBearing + followedDelta'));
      expect(
        rotation,
        isNot(contains('_isCompassLagFollowCandidate')),
        reason:
            'Direct rotation follow should not wait for lag-follow evidence.',
      );
      expect(rotation, isNot(contains('_dampenCompassTiltJitter')));
      expect(rotation, isNot(contains('_isCompassTiltJitter')));

      final handleStart = view.indexOf('void _handleCompassEvent(');
      final handleEnd = view.indexOf('void _pumpCompassCamera', handleStart);
      expect(handleStart, isNonNegative);
      expect(handleEnd, greaterThan(handleStart));
      final handle = view.substring(handleStart, handleEnd);
      expect(handle, contains('sensorDelta: sensorDelta'));
    });
  });
}
