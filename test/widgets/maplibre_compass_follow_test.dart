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

    test('coalesces compass samples through a frame-paced render pump', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(view, contains('_compassRenderInterval'));
      expect(view, contains('_compassRenderTimer'));
      expect(view, contains('_startCompassRenderPump'));
      expect(view, contains('_pumpCompassCamera'));
      expect(view, contains('_compassRenderSlowGain'));
      expect(view, contains('_compassRenderFastGain'));
      expect(view, contains('path=render-pump'));

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
  });
}
