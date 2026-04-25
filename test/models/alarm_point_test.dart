import 'package:flutter_test/flutter_test.dart';
import 'package:gpsalarm/models/alarm_point.dart';

void main() {
  group('AlarmPoint', () {
    test('creates with required fields', () {
      final point = AlarmPoint(
        id: 'test-1',
        latitude: 47.4979,
        longitude: 19.0402,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      expect(point.id, 'test-1');
      expect(point.isActive, true);
      expect(point.name, isNull);
      expect(point.customAlarmSound, isNull);
      expect(point.customAlarmType, isNull);
    });

    test('creates time-based trigger', () {
      final point = AlarmPoint(
        id: 'test-2',
        latitude: 47.5,
        longitude: 19.08,
        radiusMeters: 0,
        triggerType: TriggerType.time,
        timeTrigger: const Duration(minutes: 30),
      );
      expect(point.triggerType, TriggerType.time);
      expect(point.timeTrigger?.inMinutes, 30);
    });

    test('toMap and fromMap roundtrip', () {
      final original = AlarmPoint(
        id: 'test-3',
        name: 'Work',
        latitude: 47.4979,
        longitude: 19.0402,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
        isActive: false,
      );
      final map = original.toMap();
      final restored = AlarmPoint.fromMap(map);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.latitude, original.latitude);
      expect(restored.isActive, false);
    });

    test('copyWith updates fields', () {
      final point = AlarmPoint(
        id: 'test-4',
        latitude: 47.0,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      final updated = point.copyWith(name: 'Home', radiusMeters: 200);
      expect(updated.name, 'Home');
      expect(updated.radiusMeters, 200);
      expect(updated.id, 'test-4');
    });
  });
}
