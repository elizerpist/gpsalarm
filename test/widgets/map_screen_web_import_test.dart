import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapScreen web MapLibre import boundary', () {
    test('does not import the Android MapLibre view directly', () {
      final screen = File('lib/screens/map_screen.dart').readAsStringSync();

      expect(
        screen,
        contains("import '../widgets/maplibre_view_entry.dart';"),
        reason:
            'MapScreen must import the platform entry point so web builds never resolve JNI-backed MapLibre sources.',
      );
      expect(
        screen,
        isNot(contains("import '../widgets/maplibre_new_view.dart';")),
        reason:
            'A runtime kIsWeb guard is too late: dart2js still compiles directly imported Android/JNI code.',
      );
    });

    test('provides a web stub before native MapLibre is resolved', () {
      final entryFile = File('lib/widgets/maplibre_view_entry.dart');
      final webStubFile = File('lib/widgets/maplibre_view_web.dart');

      expect(entryFile.existsSync(), isTrue);
      expect(webStubFile.existsSync(), isTrue);

      final entry = entryFile.readAsStringSync();
      final webStub = webStubFile.readAsStringSync();

      expect(entry, contains("export 'maplibre_view_native.dart'"));
      expect(
        entry,
        contains("if (dart.library.html) 'maplibre_view_web.dart'"),
      );
      expect(
        webStub,
        contains('class MaplibreNewView extends StatelessWidget'),
      );
      expect(webStub, isNot(contains('package:maplibre')));
      expect(webStub, isNot(contains('package:jni')));
    });
  });
}
