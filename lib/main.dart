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
          seedColor: const Color(0xFF009688),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF009688),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1a1a2e),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
