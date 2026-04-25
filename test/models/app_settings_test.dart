import 'package:flutter_test/flutter_test.dart';
import 'package:gpsalarm/models/app_settings.dart';
import 'package:gpsalarm/models/alarm_point.dart';

void main() {
  group('AppSettings', () {
    test('creates with defaults', () {
      final settings = AppSettings();
      expect(settings.defaultAlarmType, AlarmType.soundAndVibration);
      expect(settings.defaultAlarmSound, 'classic_bell');
      expect(settings.vibrationEnabled, true);
      expect(settings.volume, 0.7);
      expect(settings.gpsPollingMode, GpsPollingMode.continuous);
      expect(settings.locale, 'hu');
    });

    test('toMap and fromMap roundtrip', () {
      final original = AppSettings(
        volume: 0.5,
        locale: 'en',
        gpsPollingMode: GpsPollingMode.custom,
        customPollingInterval: const Duration(seconds: 30),
      );
      final map = original.toMap();
      final restored = AppSettings.fromMap(map);
      expect(restored.volume, 0.5);
      expect(restored.locale, 'en');
      expect(restored.gpsPollingMode, GpsPollingMode.custom);
      expect(restored.customPollingInterval.inSeconds, 30);
    });
  });
}
