import 'dart:math';

class AlarmService {
  static double distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static bool isWithinRadius({
    required double userLat,
    required double userLng,
    required double pointLat,
    required double pointLng,
    required double radiusMeters,
  }) {
    return distanceMeters(userLat, userLng, pointLat, pointLng) <= radiusMeters;
  }

  static double? calculateEtaMinutes({
    required double distanceMeters,
    required double speedKmh,
  }) {
    if (speedKmh < 1.0) return null;
    final speedMps = speedKmh * 1000 / 3600;
    return (distanceMeters / speedMps) / 60;
  }

  static double calculateAverageSpeed(List<double> recentSpeeds) {
    if (recentSpeeds.isEmpty) return 0;
    return recentSpeeds.reduce((a, b) => a + b) / recentSpeeds.length;
  }

  static double _toRad(double deg) => deg * pi / 180;
}
