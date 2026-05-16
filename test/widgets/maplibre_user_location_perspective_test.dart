import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapLibre user location perspective', () {
    test('renders user location as native map-pitched circle layers', () {
      final view = File(
        'lib/widgets/maplibre_new_view.dart',
      ).readAsStringSync();
      final userLayer = File(
        'lib/widgets/maplibre_new_view/maplibre_user_location_layer.dart',
      ).readAsStringSync();
      final initLayer = File(
        'lib/widgets/maplibre_new_view/maplibre_radius_layer_init.dart',
      ).readAsStringSync();

      expect(
        view,
        contains("part 'maplibre_new_view/maplibre_user_location_layer.dart';"),
      );
      expect(view, contains('_syncUserLocationSource'));
      expect(view, isNot(contains('points: [Point(coordinates: _userPos!)]')));

      expect(initLayer, contains('_initUserLocationLayer(style)'));
      expect(userLayer, contains("GeoJsonSource(id: 'user-location-src'"));
      expect(
        userLayer,
        contains("const _userLocationGlowLayerId = 'user-location-glow'"),
      );
      expect(
        userLayer,
        contains("const _userLocationDotLayerId = 'user-location-dot'"),
      );
      expect(userLayer, contains('id: _userLocationGlowLayerId'));
      expect(userLayer, contains('id: _userLocationDotLayerId'));
      expect(userLayer, contains("sourceId: 'user-location-src'"));
      expect(userLayer, contains("'circle-pitch-alignment': 'map'"));
      expect(userLayer, contains("'circle-pitch-scale': 'map'"));
      expect(userLayer, contains('USER_POS_NATIVE_SYNC'));
    });
  });
}
