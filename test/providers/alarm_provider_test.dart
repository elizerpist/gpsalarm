import 'package:flutter_test/flutter_test.dart';
import 'package:gpsalarm/models/alarm_point.dart';
import 'package:gpsalarm/providers/alarm_provider.dart';

void main() {
  group('AlarmProvider', () {
    late AlarmProvider provider;

    setUp(() {
      provider = AlarmProvider(enablePersistence: false);
    });

    test('starts with empty list', () {
      expect(provider.alarmPoints, isEmpty);
      expect(provider.activeCount, 0);
    });

    test('addAlarmPoint adds to list', () async {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      await provider.addAlarmPoint(point);
      expect(provider.alarmPoints.length, 1);
      expect(provider.activeCount, 1);
    });

    test('enforces 50 alarm limit', () async {
      for (int i = 0; i < 50; i++) {
        await provider.addAlarmPoint(AlarmPoint(
          id: 'p$i',
          latitude: 47.0 + i * 0.01,
          longitude: 19.0,
          radiusMeters: 100,
          triggerType: TriggerType.distance,
        ));
      }
      expect(provider.canAddAlarm, false);
    });

    test('toggleActive switches isActive', () async {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      await provider.addAlarmPoint(point);
      await provider.toggleActive('1');
      expect(provider.alarmPoints.first.isActive, false);
      expect(provider.activeCount, 0);
    });

    test('removeAlarmPoint removes from list', () async {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      await provider.addAlarmPoint(point);
      await provider.removeAlarmPoint('1');
      expect(provider.alarmPoints, isEmpty);
    });

    test('updateAlarmPoint replaces existing', () async {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      await provider.addAlarmPoint(point);
      await provider.updateAlarmPoint(point.copyWith(name: 'Work'));
      expect(provider.alarmPoints.first.name, 'Work');
    });

    test('findNearby returns point within 50m', () async {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      await provider.addAlarmPoint(point);
      final found = provider.findNearby(47.5001, 19.0001);
      expect(found, isNotNull);
      expect(found?.id, '1');
    });
  });
}
