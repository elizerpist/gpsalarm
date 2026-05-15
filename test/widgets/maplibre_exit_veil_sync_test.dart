import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapLibre exit trigger veil sync', () {
    test('uses Android synchronous GeoJSON update for veil sources', () {
      final styleState = File(
        'lib/widgets/maplibre_new_view/maplibre_style_state.dart',
      ).readAsStringSync();

      expect(styleState, contains('_tryUpdateGeoJsonSourceSyncAndroid'));
      expect(
        styleState,
        contains('setGeoJsonSync\$3'),
        reason:
            'The exit veil mask must use MapLibre Android sync GeoJSON updates when available.',
      );

      final syncCall = styleState.indexOf('_tryUpdateGeoJsonSourceSyncAndroid');
      final fallbackCall = styleState.indexOf('style.updateGeoJsonSource');

      expect(syncCall, isNonNegative);
      expect(fallbackCall, isNonNegative);
      expect(
        syncCall,
        lessThan(fallbackCall),
        reason:
            'The public async GeoJSON update should remain only as the fallback path.',
      );
      expect(
        styleState,
        contains('for (var viewId = 63; viewId >= 0; viewId--)'),
        reason:
            'MapLibre keeps old maps in its registry, so the latest view id should be checked first.',
      );
    });

    test('updates native radius paint before the live exit veil mask', () {
      final lifecycle = File(
        'lib/widgets/maplibre_new_view/maplibre_assign_lifecycle.dart',
      ).readAsStringSync();

      final start = lifecycle.indexOf(
        'Future<void> _applyAssignRadiusPaint({required String debugReason})',
      );
      final end = lifecycle.indexOf(
        'void _syncAssignRadiusPaintImmediate',
        start,
      );
      expect(start, isNonNegative);
      expect(end, greaterThan(start));

      final method = lifecycle.substring(start, end);
      final paintCall = method.indexOf(
        'final updated = await this._setCircleLayerRadiusPaint',
      );
      final firstVeilSync = method.indexOf(
        'await this._syncAssignVeilWithRadiusPaint',
      );
      final veilSyncAfterPaint = method.indexOf(
        'await this._syncAssignVeilWithRadiusPaint',
        paintCall,
      );

      expect(paintCall, isNonNegative);
      expect(firstVeilSync, isNonNegative);
      expect(veilSyncAfterPaint, isNonNegative);
      expect(
        firstVeilSync,
        equals(veilSyncAfterPaint),
        reason:
            'The live exit veil must not be submitted before the native border radius paint.',
      );
      expect(
        paintCall,
        lessThan(veilSyncAfterPaint),
        reason:
            'The veil hole should be built after the native circle radius has been updated.',
      );
    });
  });
}
