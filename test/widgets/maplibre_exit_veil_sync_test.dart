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
      expect(
        styleState,
        contains('VEIL_SOURCE_UPDATE'),
        reason:
            'Exit veil debugging must show whether the sync or fallback source path was used.',
      );
      expect(
        styleState,
        contains('path=android-sync'),
        reason:
            'The source update log should make the Android sync path observable.',
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

    test(
      'uses native annulus paint for live exit veil while native radius stays live',
      () {
        final view = File(
          'lib/widgets/maplibre_new_view.dart',
        ).readAsStringSync();
        final veilLayer = File(
          'lib/widgets/maplibre_new_view/maplibre_veil_layer.dart',
        ).readAsStringSync();
        final radiusInit = File(
          'lib/widgets/maplibre_new_view/maplibre_radius_layer_init.dart',
        ).readAsStringSync();

        expect(veilLayer, contains('_usesNativeLiveExitVeil'));
        expect(veilLayer, contains('_syncNativeLiveExitVeilMode'));
        expect(veilLayer, contains('_setNativeLiveExitVeilRadiusPaint'));
        expect(veilLayer, contains('EXIT_NATIVE_VEIL_MODE'));
        expect(veilLayer, contains('EXIT_NATIVE_VEIL_PAINT'));
        expect(
          radiusInit,
          contains('veil-live-annulus'),
          reason:
              'Live exit editing should use a native circle annulus layer, not a Flutter repaint overlay.',
        );
        expect(
          view,
          isNot(contains('_LiveExitVeilOverlayPainter')),
          reason:
              'The live exit veil should share the native paint path instead of running a separate Flutter painter.',
        );
      },
    );

    test('aligns native annulus inner edge with live radius paint', () {
      final veilLayer = File(
        'lib/widgets/maplibre_new_view/maplibre_veil_layer.dart',
      ).readAsStringSync();

      final start = veilLayer.indexOf(
        'Future<void> _setNativeLiveExitVeilRadiusPaint',
      );
      final end = veilLayer.indexOf(
        'Future<void> _syncAssignVeilWithRadiusPaint',
        start,
      );
      expect(start, isNonNegative);
      expect(end, greaterThan(start));

      final method = veilLayer.substring(start, end);
      expect(
        method,
        contains('final annulusRadiusPx = innerPx;'),
        reason:
            'Android MapLibre draws circle stroke outward, so circle-radius must be the desired inner edge.',
      );
      expect(
        method,
        isNot(contains('innerPx + strokeWidthPx / 2.0')),
        reason:
            'Centering the stroke makes the transparent inner hole much larger than the native radius circle.',
      );
      expect(method, contains('innerEdgePx='));
      expect(method, contains('outerEdgePx='));
    });

    test('bypasses GeoJSON veil writes during live exit radius drags', () {
      final veilLayer = File(
        'lib/widgets/maplibre_new_view/maplibre_veil_layer.dart',
      ).readAsStringSync();

      final start = veilLayer.indexOf(
        'Future<void> _syncAssignVeilWithRadiusPaint',
      );
      final end = veilLayer.indexOf(
        'Future<void> _syncAssignVeilWithOverlay',
        start,
      );
      expect(start, isNonNegative);
      expect(end, greaterThan(start));

      final method = veilLayer.substring(start, end);
      final nativePath = method.indexOf('_syncNativeLiveExitVeilMode');
      final geoJsonPath = method.indexOf('_updateVeil');

      expect(nativePath, isNonNegative);
      expect(geoJsonPath, isNonNegative);
      expect(
        nativePath,
        lessThan(geoJsonPath),
        reason:
            'Fast live exit radius changes must update the native annulus paint before any MapLibre GeoJSON fallback.',
      );
    });

    test('does not hold live exit radius updates near the center', () {
      final lifecycle = File(
        'lib/widgets/maplibre_new_view/maplibre_assign_lifecycle.dart',
      ).readAsStringSync();
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();

      expect(
        lifecycle,
        isNot(contains('_shouldHoldExitRadiusAtCenter')),
        reason:
            'Exit radius edits must not pause for a center guard; that creates visible veil lag.',
      );
      expect(
        lifecycle,
        isNot(contains('EXIT_CENTER_GUARD')),
        reason:
            'The old center guard intentionally held the previous radius for hundreds of milliseconds.',
      );
      expect(
        view,
        isNot(contains('_shouldHoldExitRadiusAtCenter(')),
        reason:
            'Both long-press and overlay drags should feed every radius sample through the same live path.',
      );
    });

    test('clears live exit veil mode before save rebuild flushes static veil', () {
      final lifecycle = File(
        'lib/widgets/maplibre_new_view/maplibre_assign_lifecycle.dart',
      ).readAsStringSync();
      final saveRebuild = lifecycle.indexOf("reason: 'save-rebuild'");
      final clearBeforeSaveRebuild = lifecycle.lastIndexOf(
        "_clearLiveExitAssignVeilBeforeNativeRestore(\n          'save-rebuild-pre-native'",
        saveRebuild,
      );

      expect(saveRebuild, isNonNegative);
      expect(
        clearBeforeSaveRebuild,
        isNonNegative,
        reason:
            'Saving a new exit alarm must restore native veil visibility before writing the static save-rebuild veil.',
      );
      expect(
        clearBeforeSaveRebuild,
        lessThan(saveRebuild),
        reason:
            'The live veil mode must be cleared before the static GeoJSON veil is flushed on save.',
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
