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
      expect(stabilizer, contains('reason=rate-only-jitter'));
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

      expect(stabilizer, contains('reason=tilt-stall-jitter'));
      expect(stabilizer, contains('eventDt >= _compassTiltJitterStallEventMs'));
      expect(
        stabilizer,
        contains('if (tiltJitter) return dampedHeading;'),
        reason:
            'Stalled tilt jitter must be damped even when the old clamp predicate is true.',
      );
    });
  });
}
