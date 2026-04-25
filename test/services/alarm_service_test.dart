import 'package:flutter_test/flutter_test.dart';
import 'package:gpsalarm/services/alarm_service.dart';

void main() {
  group('AlarmService', () {
    test('isWithinRadius returns true when inside', () {
      final result = AlarmService.isWithinRadius(
        userLat: 47.4979,
        userLng: 19.0402,
        pointLat: 47.4980,
        pointLng: 19.0403,
        radiusMeters: 500,
      );
      expect(result, true);
    });

    test('isWithinRadius returns false when outside', () {
      final result = AlarmService.isWithinRadius(
        userLat: 47.4979,
        userLng: 19.0402,
        pointLat: 47.51,
        pointLng: 19.06,
        radiusMeters: 500,
      );
      expect(result, false);
    });

    test('calculateEtaMinutes returns correct estimate', () {
      final eta = AlarmService.calculateEtaMinutes(
        distanceMeters: 5000,
        speedKmh: 60,
      );
      expect(eta, 5.0);
    });

    test('calculateEtaMinutes returns null for zero speed', () {
      final eta = AlarmService.calculateEtaMinutes(
        distanceMeters: 5000,
        speedKmh: 0,
      );
      expect(eta, isNull);
    });

    test('calculateAverageSpeed computes moving average', () {
      final speeds = [50.0, 60.0, 55.0, 65.0, 70.0];
      final avg = AlarmService.calculateAverageSpeed(speeds);
      expect(avg, 60.0);
    });

    test('distanceMeters calculates Haversine correctly', () {
      final d = AlarmService.distanceMeters(47.4979, 19.0402, 47.498, 19.041);
      expect(d, greaterThan(0));
      expect(d, lessThan(100));
    });
  });
}
