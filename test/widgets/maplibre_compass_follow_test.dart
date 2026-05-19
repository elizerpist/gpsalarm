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
        contains('_compassTargetPath = _CompassTargetPath.tilt;'),
        reason:
            'Stalled tilt jitter must stay on the tilt path even when the old clamp predicate is true.',
      );
      expect(
        stabilizer.indexOf('if (tiltJitter)'),
        lessThan(stabilizer.indexOf('if (!shouldClamp)')),
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
        contains('_compassTargetPath = _CompassTargetPath.tilt;'),
        reason:
            'Visible tilt jitter should remain on the tilt path before the pass-through path can return the raw heading.',
      );
      expect(
        stabilizer.indexOf('if (tiltJitter)'),
        lessThan(stabilizer.indexOf('if (!shouldClamp)')),
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
        inInclusiveRange(8.0, 12.0),
        reason:
            'Confirmed rotation has its own camera path, so it can use a wider bounded render cap without changing the tilt clamp.',
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
        contains('_compassTargetPath == _CompassTargetPath.rotation'),
        reason:
            'Only the isolated confirmed-rotation target path should use the larger render step; tilt/unconfirmed jitter must keep the base clamp.',
      );
    });

    test('uses an isolated fast camera render path for confirmed rotation', () {
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

      expect(view, contains('enum _CompassTargetPath'));
      expect(view, contains('_CompassTargetPath.rotation'));
      expect(view, contains('_CompassTargetPath.tilt'));
      expect(view, contains('_compassTargetPath'));

      expect(
        doubleConstant('_compassRotationRenderMinGain'),
        lessThanOrEqualTo(0.40),
        reason:
            'Confirmed yaw must be spread over render frames instead of snapping each 26Hz target update into one camera frame.',
      );
      expect(
        doubleConstant('_compassRotationRenderMaxGain'),
        lessThan(1.0),
        reason:
            'A gain of 1.0 makes renderStep equal dCamera, producing low cameraHz with many render-small-delta skips in the 11:37 trace.',
      );
      expect(
        doubleConstant('_compassRotationRenderMaxStep'),
        inInclusiveRange(8.0, 12.0),
        reason:
            'Rotation needs a wider camera step than tilt jitter so it can catch the bounded target without visible delay.',
      );

      final gainStart = view.indexOf('double _compassRenderGainFor(');
      final clampStart = view.indexOf(
        'double _compassRenderMaxStepFor',
        gainStart,
      );
      expect(gainStart, isNonNegative);
      expect(clampStart, greaterThan(gainStart));
      final gainFor = view.substring(gainStart, clampStart);

      expect(gainFor, contains('required bool rotationResponsive'));
      expect(gainFor, contains('if (rotationResponsive)'));

      final pumpStart = view.indexOf('void _pumpCompassCamera');
      final modeStart = view.indexOf('void _set3DMode', pumpStart);
      expect(pumpStart, isNonNegative);
      expect(modeStart, greaterThan(pumpStart));
      final pump = view.substring(pumpStart, modeStart);

      expect(
        pump,
        contains('final rotationResponsive'),
        reason:
            'Camera responsiveness must be driven by the latest confirmed rotation path, not by tilt recovery/quarantine state.',
      );
      expect(
        pump,
        contains('_compassTargetPath == _CompassTargetPath.rotation'),
      );
      expect(pump, contains('rotationResponsive: rotationResponsive'));
      expect(pump, contains('renderIntervalMs: renderIntervalMs'));
      expect(pump, contains('renderGain='));
    });

    test('paces confirmed rotation camera updates across render frames', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final gainStart = view.indexOf('double _compassRotationRenderGainFor(');
      final renderGainStart = view.indexOf(
        'double _compassRenderGainFor',
        gainStart,
      );
      expect(gainStart, isNonNegative);
      expect(renderGainStart, greaterThan(gainStart));
      final rotationGain = view.substring(gainStart, renderGainStart);

      expect(rotationGain, contains('_lastCompassEventDtMs'));
      expect(rotationGain, contains('renderIntervalMs / targetEventDtMs'));
      expect(rotationGain, contains('_compassRotationRenderMinGain'));
      expect(rotationGain, contains('_compassRotationRenderMaxGain'));

      final renderGainEnd = view.indexOf(
        'double _compassRenderMaxStepFor',
        renderGainStart,
      );
      expect(renderGainEnd, greaterThan(renderGainStart));
      final renderGain = view.substring(renderGainStart, renderGainEnd);
      expect(
        renderGain,
        contains('return _compassRotationRenderGainFor(renderIntervalMs);'),
      );

      final handleStart = view.indexOf('void _handleCompassEvent');
      final pumpStart = view.indexOf('void _pumpCompassCamera', handleStart);
      expect(handleStart, isNonNegative);
      expect(pumpStart, greaterThan(handleStart));
      final handle = view.substring(handleStart, pumpStart);

      expect(handle, contains('_lastCompassEventDtMs = eventDt;'));

      final pumpEnd = view.indexOf('void _set3DMode', pumpStart);
      expect(pumpEnd, greaterThan(pumpStart));
      final pump = view.substring(pumpStart, pumpEnd);

      expect(pump, contains('renderIntervalMs: renderIntervalMs'));
      expect(pump, contains('targetEventDtMs='));
      expect(
        pump,
        isNot(contains('return _compassRotationRenderGain;')),
        reason:
            'The 11:37 trace has renderStep equal to dCamera because the old fixed gain snapped rotation targets in one frame.',
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

    test('keeps lag-only rotation catch-up below direct yaw follow steps', () {
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
        constant('_compassRotationLagFollowMaxStep'),
        lessThan(constant('_compassRotationFollowMaxStep')),
        reason:
            'The 22:10 trace shows lag-only catch-up using 10-12 degree target jumps after target freeze, which makes rotation visibly step instead of glide.',
      );
      expect(
        constant('_compassRotationLagFollowMaxStep'),
        lessThanOrEqualTo(6.0),
        reason:
            'Lag-only catch-up should stay near the sensor/coast step size so camera frames do not get repeated 5 degree jumps.',
      );

      final followStart = view.indexOf('double _followCompassRotationIntent({');
      final followEnd = view.indexOf(
        'void _resetCompassBlockedRotationEvidence',
        followStart,
      );
      expect(followStart, isNonNegative);
      expect(followEnd, greaterThan(followStart));
      final follow = view.substring(followStart, followEnd);

      expect(follow, contains('required bool lagFollowCandidate'));
      expect(
        follow,
        contains('? _compassRotationLagFollowMaxStep'),
        reason: 'Lag-only follow must select the smaller max step branch.',
      );
      expect(
        follow,
        contains(
          'rotationIntent && rawDelta.abs() >= _compassRotationFollowLagBoostDelta',
        ),
        reason:
            'The extra lag boost should only apply to direct rotation intent, not to lag-only recovery after tilt quarantine.',
      );
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
        contains('immediateLagFollowCandidate || lagBuildCandidate'),
        reason:
            'The latest rotation log froze with sensorDelta near zero but persistent target/camera lag; blocked lag evidence must build before immediate lag-follow is confirmed.',
      );
    });

    test('escapes tilt burst on sustained sub-threshold rotation lag', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double constant(String name) {
        final match = RegExp(
          'static const double $name =\\s*([0-9.]+);',
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be a double constant.');
        return double.parse(match!.group(1)!);
      }

      expect(
        constant('_compassRotationLagBuildMinDelta'),
        lessThanOrEqualTo(8.0),
        reason:
            'The latest trace freezes at rawDelta 8-11 degrees for about a second, below the 18 degree immediate lag-follow threshold.',
      );
      expect(view, contains('_isCompassLagBuildCandidate'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassHeading({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      for (final token in [
        'immediateLagFollowCandidate',
        'lagBuildCandidate',
        'blockedRotationCandidate =',
        'immediateLagFollowCandidate || lagBuildCandidate',
        'final lagFollowCandidate =',
        'immediateLagFollowCandidate || sustainedRotationEscape',
        'rotationIntent || lagFollowCandidate',
        'lagBuildCandidate=',
      ]) {
        expect(stabilizer, contains(token));
      }

      expect(
        stabilizer,
        isNot(contains('blockedRotationCandidate = lagFollowCandidate;')),
        reason:
            'Blocked rotation evidence must build before the old immediate lag-follow threshold is reached.',
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
      expect(rotation, contains('_lastBearing + compensatedDelta'));
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

    test(
      'keeps sensor rotation available through a protected tilt escape gate',
      () {
        final view = File(
          'lib/widgets/maplibre_new_view.dart',
        ).readAsStringSync();

        final wrapperStart = view.indexOf('double _stabilizeCompassHeading({');
        final rotationStart = view.indexOf(
          'double? _followCompassSensorRotation({',
        );
        final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
        expect(wrapperStart, isNonNegative);
        expect(rotationStart, greaterThan(wrapperStart));
        expect(tiltStart, greaterThan(rotationStart));

        final wrapper = view.substring(wrapperStart, rotationStart);
        expect(wrapper, contains('_isCompassTiltProtectionActive(now)'));
        expect(wrapper, contains('tiltProtectionActive: tiltProtectionActive'));
        expect(
          wrapper.indexOf('_followCompassSensorRotation('),
          lessThan(wrapper.indexOf('_stabilizeCompassTilt(')),
          reason:
              'Rotation still needs the first chance, but protected tilt state must be passed into the rotation gate.',
        );

        final rotation = view.substring(rotationStart, tiltStart);
        expect(rotation, contains('required bool tiltProtectionActive'));
        expect(rotation, contains('_compassSensorRotationSamples'));
        expect(rotation, contains('_compassRotationSensorSamplesRequired'));
        expect(rotation, contains('_compassRotationSensorImmediateDelta'));
        expect(
          rotation,
          contains('_compassRotationSensorProtectedMinRawDelta'),
        );
        expect(rotation, contains('_compassRotationSensorProtectedMaxDelta'));
        expect(
          rotation,
          contains('_compassRotationSensorProtectedMaxRateDegPerSec'),
        );
        expect(rotation, contains('protectedRotationCandidate'));
        expect(rotation, contains('!protectedRotationCandidate'));
        expect(rotation, contains('_compassSensorRotationSamples = 0;'));
        expect(rotation, contains('protectedRotationEvidence'));
        expect(rotation, contains('!protectedRotationEvidence'));
        expect(rotation, contains('final targetGain'));
        expect(rotation, contains('_compassFastTurnGain'));
        expect(rotation, contains('followedDelta / targetGain'));
        expect(rotation, contains('compensatedDelta'));
        expect(rotation, contains('_lastBearing + compensatedDelta'));
        expect(
          rotation,
          isNot(contains('_compassRotationSensorMaxLag')),
          reason:
              'Steady rotation in the log accumulates rawDelta while the target is frozen; direct sensor follow must use a protected escape gate, not a global raw-lag cutoff.',
        );
      },
    );

    test('does not promote local tilt wobble to protected sensor rotation', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();
      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));

      final rotation = view.substring(rotationStart, tiltStart);
      expect(
        rotation,
        contains('rawAbs >= _compassRotationSensorProtectedMinRawDelta'),
        reason:
            'In the failing log, tilt quarantine samples with rawDelta around 0-6 degrees were incorrectly promoted to COMPASS_SENSOR_ROTATION.',
      );
      expect(
        rotation,
        contains('sensorAbs <= _compassRotationSensorProtectedMaxDelta'),
        reason:
            'Large tilt-produced sensor jumps should remain in tilt damping instead of being followed as yaw.',
      );
      expect(rotation, contains('turnRateDegPerSec.abs()'));
      expect(
        rotation,
        contains('_compassRotationSensorProtectedMaxRateDegPerSec'),
        reason:
            'The tilt regression shows very high rate compass swings during quarantine; protected rotation must reject those before target drift starts.',
      );
      expect(
        rotation,
        contains('rawDelta.sign == sensorDelta.sign'),
        reason:
            'Protected rotation should only escape when lag and sensor motion agree.',
      );
    });

    test('keeps protected rotation moving while raw lag is still growing', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();
      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));

      final rotation = view.substring(rotationStart, tiltStart);
      expect(
        rotation,
        contains('protectedFastRotationCandidate'),
        reason:
            'The rotation log shows target/camera updates stop while tilt quarantine is active, then jump after raw lag grows past 30 degrees.',
      );
      expect(rotation, contains('protectedLagGrowing'));
      expect(
        rotation,
        contains('_compassRotationSensorProtectedFastSamplesRequired'),
      );
      expect(rotation, contains('_compassRotationSensorProtectedFastMaxDelta'));
      expect(
        rotation,
        contains('_compassRotationSensorProtectedFastMaxRateDegPerSec'),
      );
      expect(rotation, contains('_compassSensorRotationLastRawAbs'));
      expect(
        rotation,
        contains(
          'final previousProtectedRawAbs = _compassSensorRotationLastRawAbs',
        ),
        reason:
            'A rejected high-lag tilt spike must remain in memory so a smaller follow-up wobble cannot look like growing rotation.',
      );
      expect(rotation, contains('protectedRotationSamplesRequired'));
      expect(
        rotation,
        contains('protectedFastRotationCandidate'),
        reason:
            'Fast protected rotation should need fewer sustained samples than local tilt wobble, without weakening the normal protected tilt gate.',
      );
      expect(
        rotation,
        isNot(contains('_stabilizeCompassTilt(')),
        reason:
            'The escape belongs to the rotation gate; the tilt stabilizer should stay isolated.',
      );
    });

    test('escapes protected tilt when sustained rotation lag is building', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();
      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));

      final rotation = view.substring(rotationStart, tiltStart);
      expect(
        rotation,
        contains('protectedLagEscapeCandidate'),
        reason:
            'The failing log freezes target updates during tilt-burst until raw lag jumps beyond 40 degrees; sustained same-direction lag needs a rotation-only escape before tilt can absorb it.',
      );
      expect(
        rotation,
        contains('_compassRotationSensorProtectedLagEscapeMaxDelta'),
      );
      expect(
        rotation,
        contains('_compassRotationSensorProtectedLagEscapeMaxRateDegPerSec'),
      );
      expect(
        rotation,
        contains('_compassRotationSensorProtectedLagEscapeSamplesRequired'),
      );
      expect(rotation, contains('protectedLagGrowing'));
      expect(rotation, contains('rawDelta.sign == sensorDelta.sign'));
      expect(
        rotation,
        isNot(contains('_dampenCompassTiltJitter')),
        reason:
            'The lag escape must live in the rotation gate, leaving the tilt dampening behavior unchanged.',
      );
    });

    test('starts protected rotation before tilt burst lag becomes visible', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();
      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));

      final rotation = view.substring(rotationStart, tiltStart);
      expect(
        rotation,
        contains('protectedLagSeedCandidate'),
        reason:
            'The 21:10 trace still waits several tilt-burst samples before rotation resumes; a moderate same-direction lag should seed rotation earlier while tilt remains dampened.',
      );
      expect(
        rotation,
        contains('_compassRotationSensorProtectedLagSeedMinRawDelta'),
      );
      expect(
        rotation,
        contains('_compassRotationSensorProtectedLagSeedSamplesRequired'),
      );
      expect(
        rotation,
        contains('sensorAbs >= _compassRotationSensorImmediateDelta'),
        reason:
            'The early path should only follow real sensor movement, not stationary tilt quarantine noise.',
      );
      expect(
        rotation,
        isNot(contains('_dampenCompassTiltJitter')),
        reason:
            'Earlier rotation follow must stay isolated from the tilt dampener.',
      );
    });

    test('keeps protected rotation target close to real sensor turns', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double doubleConstant(String name) {
        final match = RegExp(
          'static const double $name =\\s*([0-9.]+);',
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be a double constant.');
        return double.parse(match!.group(1)!);
      }

      expect(
        doubleConstant('_compassRotationSensorProtectedLagSeedMinRawDelta'),
        greaterThanOrEqualTo(12.0),
        reason:
            'The 10:12 trace shows 8-12 degree tilt-quarantine drift can tremble when the protected lag seed is too permissive.',
      );
      expect(
        doubleConstant('_compassRotationSensorMaxStep'),
        greaterThanOrEqualTo(5.5),
        reason:
            'Real yaw samples in the latest trace move 5-6 degrees per event; a 4 degree cap makes the target fall behind while rendering is already responsive.',
      );
      expect(
        doubleConstant('_compassRotationSensorMaxRateDegPerSec'),
        greaterThanOrEqualTo(320.0),
        reason:
            'At 32-38ms sensor cadence, the rotation-only rate cap must allow those 5-6 degree steps without touching the tilt stabilizer.',
      );

      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));

      final rotation = view.substring(rotationStart, tiltStart);
      expect(rotation, contains('protectedLagSeedCandidate'));
      expect(rotation, contains('_compassRotationSensorMaxRateDegPerSec'));
      expect(rotation, contains('_compassRotationSensorMaxStep'));
      expect(rotation, isNot(contains('_dampenCompassTiltJitter')));
    });

    test('uses rolling drift to start slow rotation before raw threshold', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double doubleConstant(String name) {
        final match = RegExp(
          'static const double $name =\\s*([0-9.]+);',
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be a double constant.');
        return double.parse(match!.group(1)!);
      }

      int intConstant(String name) {
        final match = RegExp(
          'static const int $name = ([0-9]+);',
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be an int constant.');
        return int.parse(match!.group(1)!);
      }

      expect(
        intConstant('_compassRotationDriftSamplesRequired'),
        inInclusiveRange(3, 5),
      );
      expect(
        doubleConstant('_compassRotationDriftEnterYaw'),
        lessThanOrEqualTo(4.0),
      );
      expect(
        doubleConstant('_compassRotationDriftExitYaw'),
        lessThan(doubleConstant('_compassRotationDriftEnterYaw')),
      );
      expect(
        doubleConstant('_compassRotationDriftMinRateDegPerSec'),
        lessThanOrEqualTo(10.0),
      );
      expect(
        doubleConstant('_compassRotationDriftMinRawDelta'),
        lessThanOrEqualTo(1.5),
      );

      final detectorStart = view.indexOf('bool _recordCompassRotationDrift({');
      final detectorEnd = view.indexOf(
        'double _dampenCompassTiltJitter',
        detectorStart,
      );
      expect(detectorStart, isNonNegative);
      expect(detectorEnd, greaterThan(detectorStart));
      final detector = view.substring(detectorStart, detectorEnd);

      for (final token in [
        '_compassRotationDriftYaw',
        '_compassRotationDriftSamples',
        'windowYawAbs',
        'avgWindowRateDegPerSec',
        '_compassRotationDriftActiveUntil = now.add',
        '_compassRotationDriftEnterYaw',
        '_compassRotationDriftExitYaw',
      ]) {
        expect(detector, contains(token));
      }
      expect(
        detector,
        isNot(contains('_compassRotationSensorProtectedMinRawDelta')),
      );

      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));
      final rotation = view.substring(rotationStart, tiltStart);

      for (final token in [
        'protectedDriftRotationCandidate',
        '!protectedDriftRotationCandidate',
        '? _compassRotationSensorProtectedDriftSamplesRequired',
        'protectedDriftCandidate=',
        'driftYaw=',
        'driftSamples=',
      ]) {
        expect(rotation, contains(token));
      }
    });

    test('uses a separate protected burst gate for fast rotation', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double doubleConstant(String name) {
        final match = RegExp(
          'static const double $name =\\s*([0-9.]+);',
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be a double constant.');
        return double.parse(match!.group(1)!);
      }

      int intConstant(String name) {
        final match = RegExp(
          'static const int $name = ([0-9]+);',
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be an int constant.');
        return int.parse(match!.group(1)!);
      }

      expect(
        intConstant('_compassRotationSensorProtectedBurstSamplesRequired'),
        equals(2),
        reason:
            'Fast rotation in the 10:12 trace has two clear same-direction burst samples before spike clamp creates 50+ degrees of lag.',
      );
      expect(
        doubleConstant('_compassRotationSensorProtectedBurstMinRawDelta'),
        lessThanOrEqualTo(9.4),
        reason:
            'The latest trace starts the real fast-turn lag at 9.4 degrees raw lag; this gate must catch that burst before tilt quarantine turns it into spike-clamp lag.',
      );
      expect(
        doubleConstant('_compassRotationSensorProtectedBurstMinDelta'),
        lessThanOrEqualTo(7.2),
      );
      expect(
        doubleConstant('_compassRotationSensorProtectedBurstMinRateDegPerSec'),
        lessThanOrEqualTo(189.1),
      );
      expect(
        doubleConstant('_compassRotationSensorProtectedBurstMaxDelta'),
        greaterThanOrEqualTo(24.7),
      );
      expect(
        doubleConstant('_compassRotationSensorProtectedBurstMaxRateDegPerSec'),
        greaterThanOrEqualTo(667.2),
      );

      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));

      final rotation = view.substring(rotationStart, tiltStart);
      expect(rotation, contains('protectedBurstRotationCandidate'));
      expect(rotation, contains('!protectedBurstRotationCandidate'));
      expect(
        rotation,
        contains('? _compassRotationSensorProtectedBurstSamplesRequired'),
      );
      expect(
        rotation,
        contains('sensorAbs >= _compassRotationSensorProtectedBurstMinDelta'),
      );
      expect(rotation, contains('turnRateDegPerSec.abs() >='));
      expect(rotation, isNot(contains('_stabilizeCompassTilt(')));
    });

    test('applies full rotation follow steps after fast-turn lag', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();
      final followStart = view.indexOf('double _followCompassRotationIntent({');
      final followEnd = view.indexOf(
        'void _resetCompassBlockedRotationEvidence',
        followStart,
      );
      expect(followStart, isNonNegative);
      expect(followEnd, greaterThan(followStart));

      final follow = view.substring(followStart, followEnd);
      expect(follow, contains('final targetGain'));
      expect(
        follow,
        contains('final compensatedDelta = followedDelta / targetGain'),
      );
      expect(follow, contains('_lastBearing + compensatedDelta'));
      expect(follow, contains('targetGain=\${targetGain.toStringAsFixed(2)}'));
    });

    test('uses a wider isolated sensor step only for fast rotation', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      double doubleConstant(String name) {
        final match = RegExp(
          'static const double $name =\\s*([0-9.]+);',
        ).firstMatch(view);
        expect(match, isNotNull, reason: '$name should be a double constant.');
        return double.parse(match!.group(1)!);
      }

      expect(
        doubleConstant('_compassRotationSensorFastMaxStep'),
        greaterThanOrEqualTo(12.0),
        reason:
            'The 08:19 fast-turn trace has 20-30 degree sensor deltas while the target is capped at 6 degrees per sample, building 70-80 degrees of raw lag.',
      );
      expect(
        doubleConstant('_compassRotationSensorFastMaxRateDegPerSec'),
        greaterThanOrEqualTo(600.0),
        reason:
            'Fast rotation should be capped by the isolated rotation path, not by the conservative 360 deg/s tilt-safe cap.',
      );

      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));

      final rotation = view.substring(rotationStart, tiltStart);
      expect(rotation, contains('fastSensorStepCandidate'));
      expect(rotation, contains('sensorModeMaxStep'));
      expect(rotation, contains('sensorModeMaxRateDegPerSec'));
      expect(rotation, contains('sensorModeMaxStep='));
      expect(
        rotation,
        isNot(contains('_dampenCompassTiltJitter')),
        reason:
            'The wider cap must stay in the isolated rotation path so tilt damping remains unchanged.',
      );
    });

    test('rejects single-sample high-rate sensor spikes', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassRotationSensorSingleSpikeMinDelta'));
      expect(
        view,
        contains('_compassRotationSensorSingleSpikeMinRateDegPerSec'),
      );

      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));
      final rotation = view.substring(rotationStart, tiltStart);

      expect(rotation, contains('unprotectedSingleSampleSpike'));
      expect(
        rotation,
        contains(
          '_compassSensorRotationSamples < _compassRotationSensorSamplesRequired',
        ),
        reason:
            'A first high-rate sample should not become rotation until a second same-direction sample confirms it.',
      );
      expect(rotation, contains('_compassSensorRotationLastRawAbs = rawAbs;'));
      expect(
        rotation.indexOf('unprotectedSingleSampleSpike'),
        lessThan(rotation.indexOf('final sensorRotationConfirmed')),
        reason:
            'The spike guard must run before immediate sensor-delta confirmation can accept the jump.',
      );
      expect(
        rotation,
        isNot(contains('_dampenCompassTiltJitter')),
        reason: 'The fast-spike guard belongs to the isolated rotation gate.',
      );
    });

    test('keeps post-tilt lateral wobble locked out of rotation', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassTiltLateralLockUntil'));
      expect(view, contains('_compassTiltLateralLockDuration'));
      expect(view, contains('_compassTiltLateralLockDelta'));
      expect(view, contains('_isCompassTiltLateralLockActive'));
      expect(view, contains('_isCompassTiltLateralLockJitter'));
      expect(view, contains("return 'tilt-lateral-lock-jitter';"));

      final protectionStart = view.indexOf(
        'bool _isCompassTiltProtectionActive(DateTime now)',
      );
      final protectionEnd = view.indexOf(
        'bool _isCompassRotationIntent({',
        protectionStart,
      );
      expect(protectionStart, isNonNegative);
      expect(protectionEnd, greaterThan(protectionStart));
      final protection = view.substring(protectionStart, protectionEnd);
      expect(protection, contains('_isCompassTiltLateralLockActive(now)'));

      final wrapperStart = view.indexOf('double _stabilizeCompassHeading({');
      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
        wrapperStart,
      );
      expect(wrapperStart, isNonNegative);
      expect(rotationStart, greaterThan(wrapperStart));
      final wrapper = view.substring(wrapperStart, rotationStart);
      expect(wrapper, contains('tiltLateralLockActive'));
      expect(wrapper, contains('tiltLateralLockActive: tiltLateralLockActive'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassTilt({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);

      expect(
        stabilizer,
        contains(
          '_compassTiltLateralLockUntil = now.add(_compassTiltLateralLockDuration)',
        ),
        reason:
            'Tilt quarantine should leave a short side-motion lock after release so upward tilt wobble cannot pass raw heading.',
      );
      expect(stabilizer, contains('tiltLateralLockActive'));
      expect(stabilizer, contains('tiltLateralLockActive='));
      expect(
        stabilizer,
        contains('tiltLateralLockActive: tiltLateralLockActive'),
      );

      final start = view.indexOf('void _startCompassFollow() {');
      final end = view.indexOf('final events = FlutterCompass.events;', start);
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final startFollow = view.substring(start, end);
      expect(
        startFollow,
        contains(
          '_compassTiltLateralLockUntil = DateTime.fromMillisecondsSinceEpoch(0);',
        ),
      );
    });

    test('coasts protected rotation through brief sensor wobble', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();
      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));

      final rotation = view.substring(rotationStart, tiltStart);
      expect(
        rotation,
        contains('protectedRotationCoastCandidate'),
        reason:
            'After protected rotation has already been confirmed, a short sensor wobble must not drop into tilt-dampen and freeze the target.',
      );
      expect(rotation, contains('_isCompassRotationIntentActive(now)'));
      expect(rotation, contains('_compassSensorRotationDirection'));
      expect(
        rotation,
        contains('_compassRotationSensorProtectedCoastMaxOpposingDelta'),
      );
      expect(
        rotation,
        contains('_followCompassProtectedRotationCoast('),
        reason:
            'The coast should stay inside the rotation gate and return a small heading step before the tilt stabilizer can absorb the frame.',
      );
      expect(rotation, contains('COMPASS_SENSOR_ROTATION_COAST'));

      final firstReset = rotation.indexOf('resetSensorRotationEvidence();');
      final coast = rotation.indexOf('protectedRotationCoastCandidate');
      expect(firstReset, isNonNegative);
      expect(coast, isNonNegative);
      expect(
        coast,
        lessThan(firstReset),
        reason:
            'The protected coast must be evaluated before tiny or opposite sensor deltas reset rotation evidence.',
      );
      expect(
        rotation,
        isNot(contains('_stabilizeCompassTilt(')),
        reason: 'This must not change the tilt stabilizer path.',
      );
    });

    test('does not build lag escape while tilt side lock is active', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final followStart = view.indexOf('bool _isCompassLagFollowCandidate({');
      final followEnd = view.indexOf(
        'bool _isCompassLagBuildCandidate({',
        followStart,
      );
      expect(followStart, isNonNegative);
      expect(followEnd, greaterThan(followStart));
      final lagFollow = view.substring(followStart, followEnd);
      expect(lagFollow, contains('if (tiltLateralLockActive)'));
      expect(lagFollow, contains('return false;'));

      final buildStart = view.indexOf('bool _isCompassLagBuildCandidate({');
      final buildEnd = view.indexOf(
        'bool _shouldHoldCompassTilt({',
        buildStart,
      );
      expect(buildStart, isNonNegative);
      expect(buildEnd, greaterThan(buildStart));
      final lagBuild = view.substring(buildStart, buildEnd);

      expect(lagBuild, contains('required bool tiltQuarantineActive'));
      expect(lagBuild, contains('required bool tiltLateralLockActive'));
      expect(
        lagBuild,
        contains('if (tiltQuarantineActive || tiltLateralLockActive)'),
        reason:
            'Tilt/quarantine frames must not accumulate blockedRotationSamples into a sustained rotation escape.',
      );
      expect(lagBuild, contains('return false;'));

      final stabilizerStart = view.indexOf('double _stabilizeCompassTilt({');
      final recordStart = view.indexOf(
        'void _recordCompassEventDt',
        stabilizerStart,
      );
      expect(stabilizerStart, isNonNegative);
      expect(recordStart, greaterThan(stabilizerStart));
      final stabilizer = view.substring(stabilizerStart, recordStart);
      expect(
        stabilizer,
        contains('tiltQuarantineActive: tiltQuarantineBefore'),
      );
      expect(
        stabilizer,
        contains('tiltLateralLockActive: tiltLateralLockBefore'),
      );
    });

    test('requires stricter rotation escape while tilt side lock is active', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      for (final token in [
        '_compassRotationSensorLateralLockEscapeSamplesRequired',
        '_compassRotationSensorLateralLockEscapeMinRawDelta',
        '_compassRotationSensorLateralLockEscapeMinRateDegPerSec',
      ]) {
        expect(view, contains(token));
      }

      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));
      final rotation = view.substring(rotationStart, tiltStart);

      expect(rotation, contains('lateralLockRotationEscapeCandidate'));
      expect(
        rotation,
        contains(
          'tiltLateralLockActive && !lateralLockRotationEscapeCandidate',
        ),
        reason:
            'During upward tilt side-lock, low-rate sensor drift must stay isolated from the rotation path.',
      );
      expect(rotation, contains('resetSensorRotationEvidence();'));
      expect(rotation, contains('return null;'));
      expect(
        rotation.indexOf('lateralLockRotationEscapeCandidate'),
        lessThan(rotation.indexOf('if (tiltProtectionActive &&')),
        reason:
            'The stricter side-lock escape must gate protected rotation before the generic protected candidates can pass.',
      );
    });

    test('keeps protected burst fast step scoped to tilt protection', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));
      final rotation = view.substring(rotationStart, tiltStart);

      expect(rotation, contains('activeProtectedBurstRotationCandidate'));
      expect(
        rotation,
        contains('tiltProtectionActive && protectedBurstRotationCandidate'),
        reason:
            'An unprotected first burst sample should not inherit the protected fast-step cap and jump by 12+ degrees.',
      );
      final fastStepStart = rotation.indexOf('final fastSensorStepCandidate');
      expect(fastStepStart, isNonNegative);
      final fastStepEnd = rotation.indexOf(
        'final sensorModeMaxStep',
        fastStepStart,
      );
      expect(fastStepEnd, greaterThan(fastStepStart));
      final fastStep = rotation.substring(fastStepStart, fastStepEnd);
      expect(fastStep, contains('activeProtectedBurstRotationCandidate'));
      expect(fastStep, contains('unprotectedFastSensorStepCandidate'));
    });

    test('keeps protected coast small and disabled during tilt side lock', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassRotationSensorProtectedCoastMaxStep'));

      final rotationStart = view.indexOf(
        'double? _followCompassSensorRotation({',
      );
      final tiltStart = view.indexOf('double _stabilizeCompassTilt({');
      expect(rotationStart, isNonNegative);
      expect(tiltStart, greaterThan(rotationStart));
      final rotation = view.substring(rotationStart, tiltStart);

      expect(
        rotation,
        contains('!tiltLateralLockActive &&'),
        reason:
            'A protected coast frame must not move the camera sideways while the tilt side lock is absorbing wobble.',
      );

      final coastStart = view.indexOf(
        'double _followCompassProtectedRotationCoast({',
      );
      final coastEnd = view.indexOf(
        'double _stabilizeCompassTilt({',
        coastStart,
      );
      expect(coastStart, isNonNegative);
      expect(coastEnd, greaterThan(coastStart));
      final coast = view.substring(coastStart, coastEnd);
      expect(coast, contains('_compassRotationSensorProtectedCoastMaxStep'));
      expect(
        coast,
        isNot(contains('_compassRotationSensorMaxStep,')),
        reason:
            'Coast should have a smaller cap than direct sensor follow so it cannot create a 6 degree raw-lag jump from wobble.',
      );
    });

    test('resets sensor rotation evidence when compass follow starts', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();
      final start = view.indexOf('void _startCompassFollow() {');
      final end = view.indexOf('final events = FlutterCompass.events;', start);
      expect(start, isNonNegative);
      expect(end, greaterThan(start));

      final startFollow = view.substring(start, end);
      expect(startFollow, contains('_compassSensorRotationSamples = 0;'));
      expect(startFollow, contains('_compassSensorRotationDirection = 0;'));
      expect(startFollow, contains('_compassSensorRotationLastRawAbs = 0;'));
    });
  });
}
