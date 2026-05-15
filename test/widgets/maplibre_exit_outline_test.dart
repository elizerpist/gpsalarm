import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapLibre exit trigger live outline', () {
    test('keeps native radius circle live while annulus veil is live', () {
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
        reason: 'The GeoJSON veil outline must not become a second circle.',
      );
      expect(
        veilLayer,
        contains('const nativeCircleOpacity = 1.0;'),
        reason:
            'The live native radius circle must stay visible during exit drags so it can move with the veil.',
      );
      expect(
        assignLifecycle,
        contains('const visibleOpacity = 1.0;'),
        reason:
            'Live exit suppression should keep the active native radius circle visible; ghost prevention belongs to stale paths.',
      );
      expect(
        radiusRebuild,
        matches(
          RegExp(
            r'bool _shouldHideLiveExitNativeCircle\(_RadiusCircleData [^)]+\) => false;',
          ),
        ),
        reason:
            'Static circles can stay normal; live annulus mode must not reintroduce a separate hidden rebuild path.',
      );
    });
  });
}
