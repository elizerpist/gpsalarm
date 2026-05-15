import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapLibre exit trigger live outline', () {
    test('hides the stale native radius circle while annulus veil is live', () {
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
        contains('final nativeCircleOpacity = active ? 0.0 : 1.0;'),
        reason:
            'When the native annulus draws the live exit veil, the old radius circle must be hidden so it cannot trail fast swipes.',
      );
      expect(
        assignLifecycle,
        contains('final opacity = shouldSuppress ? 0.0 : 1.0;'),
        reason:
            'Live exit suppression must actually hide the stale native circle instead of just marking it suppressed.',
      );
      expect(
        radiusRebuild,
        matches(
          RegExp(
            r'bool _shouldHideLiveExitNativeCircle\(_RadiusCircleData [^)]+\) => false;',
          ),
        ),
        reason:
            'Static circles can stay normal; live annulus mode handles the temporary hide explicitly.',
      );
    });
  });
}
