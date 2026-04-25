import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'debug_console.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (kIsWeb || _initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);
    _initialized = true;
    DebugConsole.log('Notification service initialized');
  }

  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      DebugConsole.log('Notification permission: $granted');
      return granted ?? false;
    }
    return false;
  }

  static Future<void> showAlarmNotification({
    required String title,
    required String body,
    int id = 0,
  }) async {
    if (kIsWeb || !_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'gps_alarm_channel',
      'GPS Alarm',
      channelDescription: 'GPS Alarm értesítések',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
    );

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
    DebugConsole.log('Notification sent: $title - $body');
  }
}
