import 'package:flutter/foundation.dart';

class PlatformService {
  static bool get isWeb => kIsWeb;
  static bool get isMobile => !kIsWeb;

  static bool get supportsBackgroundLocation => isMobile;
  static bool get supportsVibration => isMobile;
  static bool get supportsFilePicker => isMobile;
  static bool get supportsFullScreenAlarm => isMobile;
  static bool get supportsNotifications => isMobile;
}
