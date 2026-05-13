import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/alarm_point.dart';
import '../models/app_settings.dart';
import 'debug_console.dart';

class BackgroundMonitoringService {
  BackgroundMonitoringService._();

  static const MethodChannel _channel = MethodChannel('gpsalarm/background');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> sync({
    required List<AlarmPoint> alarms,
    required AppSettings settings,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('syncBackgroundMonitoring', {
        'settings': settings.toMap(),
        'alarms': alarms.map(_alarmToMap).toList(),
      });
    } catch (e) {
      DebugConsole.log('Background monitoring sync failed: $e');
    }
  }

  static Future<List<String>> consumeTriggeredAlarmIds() async {
    if (!_isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'consumeTriggeredAlarms',
      );
      if (raw is List) {
        return raw.whereType<String>().toList(growable: false);
      }
      return const [];
    } catch (e) {
      DebugConsole.log('Background trigger consume failed: $e');
      return const [];
    }
  }

  static Future<void> setLockScreenAlarmMode(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setLockScreenAlarmMode', enabled);
    } catch (e) {
      DebugConsole.log('Lockscreen alarm mode failed: $e');
    }
  }

  static Future<void> stopAlarmOutput() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopAlarmOutput');
    } catch (_) {}
  }

  static Map<String, Object?> _alarmToMap(AlarmPoint point) => {
        'id': point.id,
        'name': point.name,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'radiusMeters': point.radiusMeters,
        'timeTriggerMinutes': point.timeTrigger?.inMinutes,
        'triggerType': point.triggerType.index,
        'zoneTrigger': point.zoneTrigger.index,
        'isActive': point.isActive,
        'customAlarmSound': point.customAlarmSound,
        'customAlarmType': point.customAlarmType?.index,
      };
}
