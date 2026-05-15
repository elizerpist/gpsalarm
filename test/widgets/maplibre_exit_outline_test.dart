import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapLibre exit trigger live outline', () {
    test('keeps native alarm circle as the visible edit outline', () {
      final veilLayer = File(
        'lib/widgets/maplibre_new_view/maplibre_veil_layer.dart',
      ).readAsStringSync();
      final assignLifecycle = File(
        'lib/widgets/maplibre_new_view/maplibre_assign_lifecycle.dart',
      ).readAsStringSync();
      final radiusRebuild = File(
        'lib/widgets/maplibre_new_view/maplibre_radius_layer_rebuild.dart',
      ).readAsStringSync();

      expect(
        veilLayer,
        contains('const outlineOpacity = 0.0;'),
        reason: 'The veil outline must not become the visible edit circle.',
      );
      expect(
        veilLayer,
        matches(RegExp(r"property: 'circle-stroke-opacity',\s*value: 1\.0,")),
        reason: 'The native circle stroke must stay visible in exit edit mode.',
      );
      expect(veilLayer, contains('nativeStrokeHidden=false'));
      expect(
        assignLifecycle,
        contains('const strokeOpacity = 1.0;'),
        reason:
            'Suppression may keep the circle active, but must not hide stroke.',
      );
      expect(
        radiusRebuild,
        matches(
          RegExp(
            r'bool _shouldHideLiveExitNativeCircle\(_RadiusCircleData [^)]+\) => false;',
          ),
        ),
      );
    });
  });
}
