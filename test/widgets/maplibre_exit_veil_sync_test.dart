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

    test('defers live exit annulus handoff until after save close', () {
      final lifecycle = File(
        'lib/widgets/maplibre_new_view/maplibre_assign_lifecycle.dart',
      ).readAsStringSync();
      final veilLayer = File(
        'lib/widgets/maplibre_new_view/maplibre_veil_layer.dart',
      ).readAsStringSync();

      expect(
        veilLayer,
        isNot(contains('_revealStaticExitVeilBehindLiveAnnulus')),
        reason:
            'The save handoff must not keep a full static veil and the live annulus visible for a separate render pass.',
      );
      expect(
        veilLayer,
        contains('void _scheduleLiveExitVeilStaticHandoffAfterClose'),
        reason:
            'Save must schedule the native veil handoff after the assignment UI has closed instead of doing it in the save render path.',
      );

      final handoffStart = veilLayer.indexOf(
        'Future<void> _handoffLiveExitVeilToStatic',
      );
      expect(handoffStart, isNonNegative);
      final handoffEnd = veilLayer.indexOf(
        'Future<void> _clearHiddenLiveExitVeilAfterStaticHandoff',
        handoffStart < 0 ? 0 : handoffStart,
      );
      expect(handoffEnd, greaterThan(handoffStart));
      final handoffMethod = veilLayer.substring(handoffStart, handoffEnd);
      expect(handoffMethod, contains("layerId: 'veil-fill'"));
      expect(handoffMethod, contains('value: 0.15'));
      expect(handoffMethod, contains("layerId: 'veil-live-annulus'"));
      expect(handoffMethod, contains("property: 'circle-stroke-opacity'"));
      expect(handoffMethod, contains('value: 0.0'));
      expect(
        handoffMethod,
        isNot(contains('veil-live-annulus-src')),
        reason:
            'The handoff may hide the live annulus, but clearing its source in the same render pass can create a flash.',
      );
      expect(
        handoffMethod,
        isNot(contains("property: 'circle-radius'")),
        reason:
            'The live annulus geometry should only be cleared after the hidden handoff has rendered.',
      );

      final hiddenClearEnd = veilLayer.indexOf(
        'Future<void> _syncNativeLiveExitVeilMode',
        handoffEnd,
      );
      expect(hiddenClearEnd, greaterThan(handoffEnd));
      final hiddenClearMethod = veilLayer.substring(handoffEnd, hiddenClearEnd);
      expect(hiddenClearMethod, contains('veil-live-annulus-src'));
      expect(hiddenClearMethod, contains("property: 'circle-radius'"));
      expect(hiddenClearMethod, contains("property: 'circle-stroke-width'"));

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

      final inPlaceAck = lifecycle.indexOf(
        "_waitForNativeRenderAck(\n          reason: 'save-in-place-native-flush'",
      );
      final inPlaceSchedule = lifecycle.indexOf(
        "reason: 'save-in-place-veil-handoff'",
        inPlaceAck,
      );
      expect(inPlaceAck, isNonNegative);
      expect(inPlaceSchedule, isNonNegative);
      expect(inPlaceAck, lessThan(inPlaceSchedule));

      final inPlaceCriticalPath = lifecycle.substring(
        inPlaceAck,
        inPlaceSchedule,
      );
      expect(
        inPlaceCriticalPath,
        isNot(contains('_handoffLiveExitVeilToStatic')),
        reason:
            'The native save flush window must not hide the live annulus or reveal static fill directly.',
      );
      expect(
        inPlaceCriticalPath,
        isNot(contains('_clearHiddenLiveExitVeilAfterStaticHandoff')),
        reason:
            'Clearing live annulus geometry in the save flush window can produce a visible empty frame.',
      );

      final rebuildAck = lifecycle.indexOf(
        "_waitForNativeRenderAck(reason: 'save-native-flush')",
      );
      final rebuildSchedule = lifecycle.indexOf(
        "reason: 'save-veil-handoff'",
        rebuildAck,
      );
      expect(rebuildAck, isNonNegative);
      expect(rebuildSchedule, isNonNegative);
      expect(rebuildAck, lessThan(rebuildSchedule));

      final rebuildCriticalPath = lifecycle.substring(
        rebuildAck,
        rebuildSchedule,
      );
      expect(
        rebuildCriticalPath,
        isNot(contains('_handoffLiveExitVeilToStatic')),
      );
      expect(
        rebuildCriticalPath,
        isNot(contains('_clearHiddenLiveExitVeilAfterStaticHandoff')),
      );
    });

    test(
      'smooths delayed save veil handoff with native opacity blend frames',
      () {
        final veilLayer = File(
          'lib/widgets/maplibre_new_view/maplibre_veil_layer.dart',
        ).readAsStringSync();

        final handoffStart = veilLayer.indexOf(
          'Future<void> _handoffLiveExitVeilToStatic',
        );
        final handoffEnd = veilLayer.indexOf(
          'Future<void> _clearHiddenLiveExitVeilAfterStaticHandoff',
          handoffStart < 0 ? 0 : handoffStart,
        );
        expect(handoffStart, isNonNegative);
        expect(handoffEnd, greaterThan(handoffStart));
        final handoffMethod = veilLayer.substring(handoffStart, handoffEnd);

        expect(handoffMethod, contains('bool smooth = false'));
        expect(handoffMethod, contains('if (smooth)'));
        expect(handoffMethod, contains('fillOpacity=0.05'));
        expect(handoffMethod, contains('annulusOpacity=0.10'));
        expect(handoffMethod, contains("reason: '\$reason-blend-1'"));
        expect(handoffMethod, contains('fillOpacity=0.10'));
        expect(handoffMethod, contains('annulusOpacity=0.05'));
        expect(handoffMethod, contains("reason: '\$reason-blend-2'"));

        final scheduleStart = veilLayer.indexOf(
          'void _scheduleLiveExitVeilStaticHandoffAfterClose',
        );
        final scheduleEnd = veilLayer.indexOf(
          'Future<void> _syncNativeLiveExitVeilMode',
          scheduleStart < 0 ? 0 : scheduleStart,
        );
        expect(scheduleStart, isNonNegative);
        expect(scheduleEnd, greaterThan(scheduleStart));
        final scheduleMethod = veilLayer.substring(scheduleStart, scheduleEnd);
        expect(
          scheduleMethod,
          contains('smooth: true'),
          reason:
              'Only the delayed save-close handoff should use blend frames; direct zone switches stay immediate.',
        );
      },
    );

    test('keeps promoted draft marker visible until native pin settles', () {
      final lifecycle = File(
        'lib/widgets/maplibre_new_view/maplibre_assign_lifecycle.dart',
      ).readAsStringSync();

      final promotedMarker = lifecycle.indexOf(
        'final keepPromotedMarker = promotedCircle != null;',
      );
      expect(
        promotedMarker,
        isNonNegative,
        reason:
            'New alarm saves promote a draft native circle, but the pin layer is created only during promotion. The Flutter draft pin must remain visible briefly after close.',
      );

      final closeStart = lifecycle.indexOf(
        '_beginClosingAssignVisual(',
        promotedMarker,
      );
      final closeEnd = lifecycle.indexOf(
        '_scheduleAssignVisualClear(',
        closeStart,
      );
      expect(closeStart, isNonNegative);
      expect(closeEnd, greaterThan(closeStart));

      final closeBlock = lifecycle.substring(closeStart, closeEnd);
      expect(closeBlock, contains('keepMarker: keepPromotedMarker'));

      final clearEnd = lifecycle.indexOf(');', closeEnd);
      expect(clearEnd, greaterThan(closeEnd));
      final clearCall = lifecycle.substring(closeEnd, clearEnd);
      expect(clearCall, contains('keepPromotedMarker'));
      expect(clearCall, contains('const Duration(milliseconds: 260)'));
      expect(
        clearCall,
        contains('Duration.zero'),
        reason:
            'Existing alarm saves should keep the current immediate cleanup path; only draft promotion needs marker overlap.',
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
