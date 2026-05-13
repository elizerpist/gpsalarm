import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../models/alarm_point.dart';
import '../models/app_settings.dart';
import '../screens/alarm_trigger_screen.dart';
import 'audio_service.dart';
import 'background_monitoring_service.dart';
import 'debug_console.dart';
import 'notification_service.dart';

class AlarmDeliveryService {
  AlarmDeliveryService._();

  static final AudioService _audioService = AudioService();

  static Future<void> trigger({
    required BuildContext context,
    required AlarmPoint point,
    required AppSettings settings,
    double? distanceMeters,
  }) async {
    final title = point.name ?? 'GPS Alarm';
    final body = _bodyFor(point, distanceMeters);
    final alarmType = point.customAlarmType ?? settings.defaultAlarmType;
    final sound = point.customAlarmSound ?? settings.defaultAlarmSound;
    final playOutput = alarmType != AlarmType.notificationOnly;

    await NotificationService.showAlarmNotification(
      title: 'GPS Alarm: $title',
      body: body,
      id: point.id.hashCode,
      playSound: alarmType == AlarmType.notificationOnly,
      enableVibration:
          alarmType == AlarmType.notificationOnly && settings.vibrationEnabled,
      fullScreenIntent: alarmType == AlarmType.fullScreenAlarm,
    );

    if (playOutput) {
      try {
        await _audioService.playAlarm(sound, volume: settings.volume);
      } catch (e) {
        DebugConsole.log('Alarm audio failed: $e');
      }
      if (!kIsWeb && settings.vibrationEnabled) {
        try {
          Vibration.vibrate(pattern: const [0, 700, 300, 700], repeat: 0);
        } catch (e) {
          DebugConsole.log('Alarm vibration failed: $e');
        }
      }
    }

    if (alarmType == AlarmType.notificationOnly) return;

    if (!context.mounted) return;
    if (alarmType == AlarmType.fullScreenAlarm) {
      await BackgroundMonitoringService.setLockScreenAlarmMode(true);
      try {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => AlarmTriggerScreen(
              alarmPoint: point,
              distanceMeters: distanceMeters ?? point.radiusMeters,
              message: body,
              onDismiss: () async {
                await stop();
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                }
              },
            ),
          ),
        );
      } finally {
        await BackgroundMonitoringService.setLockScreenAlarmMode(false);
      }
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.alarm, color: Colors.red, size: 48),
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () async {
              await stop();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<void> stop() async {
    try {
      await _audioService.stop();
    } catch (_) {}
    if (!kIsWeb) {
      try {
        Vibration.cancel();
      } catch (_) {}
      await BackgroundMonitoringService.stopAlarmOutput();
    }
  }

  static String _bodyFor(AlarmPoint point, double? distanceMeters) {
    final zoneText =
        point.zoneTrigger == ZoneTrigger.onEntry ? 'Belepes' : 'Kilepes';
    if (point.triggerType == TriggerType.time) {
      final minutes = point.timeTrigger?.inMinutes ?? 0;
      return '$zoneText - $minutes min';
    }
    final radius = point.radiusMeters.round();
    if (distanceMeters == null) return '$zoneText - ${radius}m';
    return '$zoneText - ${distanceMeters.round()}m / ${radius}m';
  }
}
