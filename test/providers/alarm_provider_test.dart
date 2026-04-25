import 'package:flutter_test/flutter_test.dart';
import 'package:gpsalarm/models/alarm_point.dart';
import 'package:gpsalarm/providers/alarm_provider.dart';

void main() {
  group('AlarmProvider', () {
    late AlarmProvider provider;

    setUp(() {
      provider = AlarmProvider();
    });

    test('starts with empty list', () {
      expect(provider.alarmPoints, isEmpty);
      expect(provider.activeCount, 0);
    });

    test('addAlarmPoint adds to list', () {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      provider.addAlarmPoint(point);
      expect(provider.alarmPoints.length, 1);
      expect(provider.activeCount, 1);
    });

    test('enforces 50 alarm limit', () {
      for (int i = 0; i < 50; i++) {
        provider.addAlarmPoint(AlarmPoint(
          id: 'p$i',
          latitude: 47.0 + i * 0.01,
          longitude: 19.0,
          radiusMeters: 100,
          triggerType: TriggerType.distance,
        ));
      }
      expect(provider.canAddAlarm, false);
    });

    test('toggleActive switches isActive', () {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      provider.addAlarmPoint(point);
      provider.toggleActive('1');
      expect(provider.alarmPoints.first.isActive, false);
      expect(provider.activeCount, 0);
    });

    test('removeAlarmPoint removes from list', () {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      provider.addAlarmPoint(point);
      provider.removeAlarmPoint('1');
      expect(provider.alarmPoints, isEmpty);
    });

    test('updateAlarmPoint replaces existing', () {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      provider.addAlarmPoint(point);
      provider.updateAlarmPoint(point.copyWith(name: 'Work'));
      expect(provider.alarmPoints.first.name, 'Work');
    });

    test('findNearby returns point within 50m', () {
      final point = AlarmPoint(
        id: '1',
        latitude: 47.5,
        longitude: 19.0,
        radiusMeters: 500,
        triggerType: TriggerType.distance,
      );
      provider.addAlarmPoint(point);
      final found = provider.findNearby(47.5001, 19.0001);
      expect(found, isNotNull);
      expect(found?.id, '1');
    });
  });
}
