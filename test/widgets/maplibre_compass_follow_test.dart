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
        contains('tiltRecoveryActive || holdActive'),
        reason:
            'Recovery is a low-confidence compass state and must clear rotation confidence before a new rotation can confirm.',
      );
      expect(
        stabilizer,
        contains('!tiltRecoveryActive'),
        reason:
            'Rotation candidates should only accumulate while the signal is outside recovery.',
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

    test('keeps confirmed rotation responsive without raising tilt render clamp', () {
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
        lessThanOrEqualTo(3.5),
        reason:
            'A 6 degree render frame is visible as a jump on MapLibre; rotation should be velocity-limited, not frame-step heavy.',
      );
      expect(
        doubleConstant('_compassRotationFollowMaxRateDegPerSec'),
        greaterThanOrEqualTo(120.0),
        reason:
            'Confirmed rotation still needs enough velocity to avoid feeling detached.',
      );
      expect(
        doubleConstant('_compassRotationFollowMaxRateDegPerSec'),
        lessThanOrEqualTo(180.0),
        reason:
            'Rotation follow should not produce 14-17 degree target jumps per compass sample.',
      );
      expect(
        view,
        contains('rotationResponsive: _isCompassRotationIntentActive(now)'),
        reason:
            'Only confirmed rotation should use the larger render step; tilt/unconfirmed jitter must keep the base clamp.',
      );
    });
  });
}
