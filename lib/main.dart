import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'providers/alarm_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/map_provider.dart';
import 'screens/map_screen.dart';
import 'services/debug_console.dart';
import 'services/notification_service.dart';
import 'services/background_monitoring_service.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Catch Flutter framework errors and show on screen
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      DebugConsole.log('FLUTTER ERROR: ${details.exceptionAsString()}');
    };

    try {
      await EasyLocalization.ensureInitialized();
      await Hive.initFlutter();

      if (!kIsWeb) {
        DebugConsole.log('Native mode: SQLite + Hive');
        await NotificationService.init();
        await NotificationService.requestPermission();
      } else {
        DebugConsole.log('Web mode: Hive only');
      }

      final alarmProvider = AlarmProvider();
      await alarmProvider.init();

      final settingsProvider = SettingsProvider();
      await settingsProvider.init();

      final triggeredIds = await BackgroundMonitoringService.consumeTriggeredAlarmIds();
      for (final id in triggeredIds) {
        await alarmProvider.setActive(id, false);
      }
      _setupBackgroundMonitoring(alarmProvider, settingsProvider);

      runApp(
        EasyLocalization(
          supportedLocales: const [Locale('hu'), Locale('en')],
          path: 'assets/l10n',
          fallbackLocale: const Locale('hu'),
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: alarmProvider),
              ChangeNotifierProvider.value(value: settingsProvider),
              ChangeNotifierProvider(create: (_) => MapProvider()),
            ],
            child: const GpsAlarmApp(),
          ),
        ),
      );
    } catch (e, stack) {
      DebugConsole.log('STARTUP CRASH: $e');
      runApp(CrashApp(error: '$e\n\n$stack'));
    }
  }, (error, stack) {
    DebugConsole.log('ZONE ERROR: $error');
  });
}

final List<WidgetsBindingObserver> _backgroundObservers = [];

void _setupBackgroundMonitoring(
  AlarmProvider alarmProvider,
  SettingsProvider settingsProvider,
) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

  Future<void> sync() => BackgroundMonitoringService.sync(
        alarms: alarmProvider.alarmPoints,
        settings: settingsProvider.settings,
      );

  Future<void> consumeTriggeredIds() async {
    final ids = await BackgroundMonitoringService.consumeTriggeredAlarmIds();
    for (final id in ids) {
      await alarmProvider.setActive(id, false);
    }
  }

  void scheduleSync() => unawaited(sync());

  alarmProvider.addListener(scheduleSync);
  settingsProvider.addListener(scheduleSync);
  final observer = _BackgroundTriggerObserver(
    consumeTriggeredIds: consumeTriggeredIds,
    sync: sync,
  );
  WidgetsBinding.instance.addObserver(observer);
  _backgroundObservers.add(observer);
  scheduleSync();
}

class _BackgroundTriggerObserver extends WidgetsBindingObserver {
  final Future<void> Function() consumeTriggeredIds;
  final Future<void> Function() sync;

  _BackgroundTriggerObserver({
    required this.consumeTriggeredIds,
    required this.sync,
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(() async {
      await consumeTriggeredIds();
      await sync();
    }());
  }
}

/// Shown when the app crashes during startup
class CrashApp extends StatelessWidget {
  final String error;
  const CrashApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF1a1a2e),
        appBar: AppBar(
          title: const Text('GPS Alarm - Crash'),
          backgroundColor: Colors.red,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: SelectableText(
              error,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GpsAlarmApp extends StatelessWidget {
  const GpsAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    return MaterialApp(
      title: 'GPS Alarm',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      themeMode: settings.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3FA2FF),
          primary: const Color(0xFF3FA2FF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFF3FA2FF),
          thumbColor: Color(0xFF3FA2FF),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? const Color(0xFF3FA2FF) : null),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? const Color(0xFF3FA2FF).withOpacity(0.5) : null),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF3FA2FF),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: Color(0xFF3FA2FF), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3FA2FF),
          primary: const Color(0xFF3FA2FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1a1a2e),
        useMaterial3: true,
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFF3FA2FF),
          thumbColor: Color(0xFF3FA2FF),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? const Color(0xFF3FA2FF) : null),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? const Color(0xFF3FA2FF).withOpacity(0.5) : null),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF3FA2FF),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: Colors.grey[700]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: Color(0xFF3FA2FF), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      home: const MapScreen(),
    );
  }
}
