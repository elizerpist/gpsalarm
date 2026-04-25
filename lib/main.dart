import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';
import 'providers/alarm_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/map_provider.dart';
import 'screens/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Hive.initFlutter();

  // Initialize sqflite for web
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }

  final alarmProvider = AlarmProvider();
  await alarmProvider.init();

  final settingsProvider = SettingsProvider();
  await settingsProvider.init();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('hu'), Locale('en')],
      path: 'lib/l10n',
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
          seedColor: const Color(0xFF1976D2),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1976D2),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1a1a2e),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
