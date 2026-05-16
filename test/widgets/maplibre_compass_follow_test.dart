import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapLibre 3D compass follow', () {
    test('uses immediate camera bearing updates for live compass samples', () {
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
      final method = view.substring(start, end);

      expect(
        method,
        contains('_safeMoveCamera('),
        reason:
            'Compass sensor samples should update bearing immediately; native camera animations add visible lag and can queue behind sensor data.',
      );
      expect(
        method,
        isNot(contains('_safeAnimateCamera(')),
        reason: 'High-frequency compass updates must not use animateCamera.',
      );
      expect(
        method,
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
  });
}
