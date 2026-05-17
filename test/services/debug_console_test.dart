import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpsalarm/services/debug_console.dart';

void main() {
  test('batches notifier updates during log bursts', () async {
    DebugConsole.clear();
    var notifications = 0;
    void listener() {
      notifications++;
    }

    DebugConsole.notifier.addListener(listener);
    try {
      for (var i = 0; i < 20; i++) {
        DebugConsole.log('burst $i');
      }

      expect(DebugConsole.entries.length, greaterThanOrEqualTo(20));
      expect(
        notifications,
        equals(0),
        reason:
            'Log bursts should be captured immediately but notify the debug dialog in a batch, not once per compass log line.',
      );

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(notifications, equals(1));
    } finally {
      DebugConsole.notifier.removeListener(listener);
      DebugConsole.clear();
    }
  });

  test(
    'debug dialog renders logs lazily instead of rebuilding one huge text field',
    () {
      final source = File('lib/services/debug_console.dart').readAsStringSync();

      expect(source, contains('ListView.builder'));
      expect(source, contains('DebugConsole.entries'));
      expect(source, contains('DebugConsole.allText'));
      expect(source, isNot(contains('TextEditingController')));
      expect(source, isNot(contains('_textCtrl.value =')));
    },
  );
}
