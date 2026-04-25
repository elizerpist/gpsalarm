import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  final List<double> _recentSpeeds = [];
  static const int speedWindowSize = 5;

  Position? lastPosition;

  Future<bool> requestPermission() async {
    if (kIsWeb) {
      final permission = await Geolocator.requestPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    }
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      lastPosition = position;
      return position;
    } catch (e) {
      return null;
    }
  }

  void startTracking({
    required void Function(Position) onPosition,
    Duration? interval,
  }) {
    _positionSubscription?.cancel();
    final LocationSettings settings;
    if (!kIsWeb && interval != null) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        intervalDuration: interval,
      );
    } else {
      settings = const LocationSettings(accuracy: LocationAccuracy.high);
    }

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings)
            .listen((position) {
      lastPosition = position;
      _recordSpeed(position.speed * 3.6); // m/s to km/h
      onPosition(position);
    });
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _recordSpeed(double speedKmh) {
    _recentSpeeds.add(speedKmh);
    if (_recentSpeeds.length > speedWindowSize) {
      _recentSpeeds.removeAt(0);
    }
  }

  double get averageSpeedKmh {
    if (_recentSpeeds.isEmpty) return 0;
    return _recentSpeeds.reduce((a, b) => a + b) / _recentSpeeds.length;
  }

  void dispose() {
    stopTracking();
  }
}
