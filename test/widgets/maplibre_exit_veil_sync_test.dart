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
      'uses native annulus paint for live exit veil while native radius circle stays live',
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

    test('keeps live exit annulus until static save veil renders', () {
      final lifecycle = File(
        'lib/widgets/maplibre_new_view/maplibre_assign_lifecycle.dart',
      ).readAsStringSync();
      final veilLayer = File(
        'lib/widgets/maplibre_new_view/maplibre_veil_layer.dart',
      ).readAsStringSync();

      final revealStart = veilLayer.indexOf(
        'Future<void> _revealStaticExitVeilBehindLiveAnnulus',
      );
      expect(revealStart, isNonNegative);
      final revealEnd = veilLayer.indexOf(
        'Future<void> _syncNativeLiveExitVeilMode',
        revealStart < 0 ? 0 : revealStart,
      );
      expect(revealEnd, greaterThan(revealStart));
      final revealMethod = veilLayer.substring(revealStart, revealEnd);
      expect(revealMethod, contains("property: 'fill-opacity'"));
      expect(revealMethod, contains('value: 0.15'));
      expect(
        revealMethod,
        isNot(contains('veil-live-annulus-src')),
        reason:
            'The static fill reveal must not clear the live annulus in the same native render pass.',
      );

      final prepareStart = lifecycle.indexOf(
        'Future<bool> _prepareLiveExitAssignVeilBeforeNativeRestore',
      );
      expect(prepareStart, isNonNegative);
      final prepareEnd = lifecycle.indexOf(
        'Future<void> _clearLiveExitAssignVeilAfterNativeRestore',
        prepareStart < 0 ? 0 : prepareStart,
      );
      expect(prepareEnd, greaterThan(prepareStart));

      final prepareMethod = lifecycle.substring(prepareStart, prepareEnd);
      expect(prepareMethod, contains('_flushVeilSync'));
      expect(
        prepareMethod,
        isNot(contains('_syncNativeLiveExitVeilMode')),
        reason:
            'The static veil source must be prepared while the live annulus still covers the map.',
      );

      final clearEnd = lifecycle.indexOf(
        'Future<void> _clearLiveExitAssignVeilBeforeNativeRestore',
        prepareEnd,
      );
      expect(clearEnd, greaterThan(prepareEnd));
      final clearMethod = lifecycle.substring(prepareEnd, clearEnd);
      expect(clearMethod, contains('_syncNativeLiveExitVeilMode'));

      final inPlaceAck = lifecycle.indexOf(
        "_waitForNativeRenderAck(\n          reason: 'save-in-place-native-flush'",
      );
      final inPlaceReveal = lifecycle.indexOf(
        "_revealStaticExitVeilBehindLiveAnnulus(\n          liveStyle,\n          reason: 'save-in-place-veil-fill-ready'",
      );
      final inPlaceFillAck = lifecycle.indexOf(
        "_waitForNativeRenderAck(\n          reason: 'save-in-place-veil-fill-ready'",
      );
      final inPlaceClear = lifecycle.indexOf(
        "_clearLiveExitAssignVeilAfterNativeRestore(\n          'save-in-place-native-flush-post-native'",
      );
      expect(inPlaceAck, isNonNegative);
      expect(inPlaceReveal, isNonNegative);
      expect(inPlaceFillAck, isNonNegative);
      expect(inPlaceClear, isNonNegative);
      expect(
        inPlaceAck,
        lessThan(inPlaceReveal),
        reason:
            'In-place saves must keep the live annulus visible until the native radius/source update has rendered.',
      );
      expect(
        inPlaceReveal,
        lessThan(inPlaceFillAck),
        reason:
            'The static fill must be requested before waiting for its own render pass.',
      );
      expect(
        inPlaceFillAck,
        lessThan(inPlaceClear),
        reason:
            'The live annulus must only be cleared after the static fill render pass is visible.',
      );

      final rebuildAck = lifecycle.indexOf(
        "_waitForNativeRenderAck(reason: 'save-native-flush')",
      );
      final rebuildReveal = lifecycle.indexOf(
        "_revealStaticExitVeilBehindLiveAnnulus(\n          liveStyle,\n          reason: 'save-veil-fill-ready'",
      );
      final rebuildFillAck = lifecycle.indexOf(
        "_waitForNativeRenderAck(reason: 'save-veil-fill-ready')",
      );
      final rebuildClear = lifecycle.indexOf(
        "_clearLiveExitAssignVeilAfterNativeRestore(\n          'save-native-flush-post-native'",
      );
      expect(rebuildAck, isNonNegative);
      expect(rebuildReveal, isNonNegative);
      expect(rebuildFillAck, isNonNegative);
      expect(rebuildClear, isNonNegative);
      expect(
        rebuildAck,
        lessThan(rebuildReveal),
        reason:
            'New/rebuilt exit saves must keep the live annulus through the native save render.',
      );
      expect(
        rebuildReveal,
        lessThan(rebuildFillAck),
        reason:
            'New/rebuilt exit saves must reveal the static fill before waiting for that render pass.',
      );
      expect(
        rebuildFillAck,
        lessThan(rebuildClear),
        reason:
            'New/rebuilt exit saves must not clear the live annulus until the static fill has rendered.',
      );
    });

    test('updates native radius paint during live exit annulus drags', () {
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
      final nativePaint = method.indexOf('_setCircleLayerRadiusPaint');
      final veilPaint = method.indexOf('_syncAssignVeilWithRadiusPaint');

      expect(nativePaint, isNonNegative);
      expect(veilPaint, isNonNegative);
      expect(
        nativePaint,
        lessThan(veilPaint),
        reason:
            'Fast exit swipes must move the native radius circle before syncing the annulus veil to the same radius.',
      );
      expect(
        method,
        contains('nativeSkipped=false'),
        reason:
            'Exit debug logs should prove live drag samples update the native circle instead of skipping it.',
      );
      expect(method, isNot(contains('nativeSkipped=\$liveExitVeil')));
    });
  });
}
