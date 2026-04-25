import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/alarm_provider.dart';
import '../providers/settings_provider.dart';
import '../models/app_settings.dart';
import 'alarm_settings_screen.dart';
import 'gps_settings_screen.dart';
import 'map_settings_screen.dart';
import 'alarm_list_screen.dart';

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final alarmProv = context.watch<AlarmProvider>();
    final settingsProv = context.watch<SettingsProvider>();
    final settings = settingsProv.settings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDark ? const Color(0xFF1a1a2e) : null,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF3F7FBF), Color(0xFF2D5F8F)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('app_title'),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  const Text('v1.0.0',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Menu items
            _MenuItem(
              icon: Icons.location_on,
              title: tr('saved_locations'),
              subtitle: tr('active_alarms',
                  args: [alarmProv.activeCount.toString()]),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AlarmListScreen()));
              },
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            _MenuItem(
              icon: Icons.notifications,
              title: tr('alarm_settings'),
              subtitle: tr('sound_and_vibration'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AlarmSettingsScreen()));
              },
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            _MenuItem(
              icon: Icons.satellite_alt,
              title: tr('gps_settings'),
              subtitle: settings.gpsPollingMode == GpsPollingMode.continuous
                  ? tr('continuous')
                  : tr('custom_interval'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GpsSettingsScreen()));
              },
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            _MenuItem(
              icon: Icons.map,
              title: tr('map_settings'),
              subtitle: tr('start_view'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MapSettingsScreen()));
              },
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            // Theme
            _MenuItem(
              icon: Icons.palette,
              title: tr('appearance'),
              subtitle: settings.themeMode == ThemeMode.light
                  ? tr('light')
                  : settings.themeMode == ThemeMode.dark
                      ? tr('dark')
                      : tr('system'),
              onTap: () => _showThemePicker(context, settingsProv),
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            // Language
            _MenuItem(
              icon: Icons.language,
              title: tr('language'),
              subtitle: settings.locale == 'hu' ? 'Magyar' : 'English',
              onTap: () => _toggleLanguage(context, settingsProv),
            ),
          ],
        ),
      ),
    );
  }

  void _showThemePicker(
      BuildContext context, SettingsProvider settingsProv) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(tr('appearance')),
        children: [
          _ThemeOption(
            label: tr('light'),
            mode: ThemeMode.light,
            current: settingsProv.settings.themeMode,
            onTap: () {
              settingsProv.updateSettings(
                  settingsProv.settings.copyWith(themeMode: ThemeMode.light));
              Navigator.pop(context);
            },
          ),
          _ThemeOption(
            label: tr('dark'),
            mode: ThemeMode.dark,
            current: settingsProv.settings.themeMode,
            onTap: () {
              settingsProv.updateSettings(
                  settingsProv.settings.copyWith(themeMode: ThemeMode.dark));
              Navigator.pop(context);
            },
          ),
          _ThemeOption(
            label: tr('system'),
            mode: ThemeMode.system,
            current: settingsProv.settings.themeMode,
            onTap: () {
              settingsProv.updateSettings(
                  settingsProv.settings.copyWith(themeMode: ThemeMode.system));
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _toggleLanguage(
      BuildContext context, SettingsProvider settingsProv) {
    final current = settingsProv.settings.locale;
    final newLocale = current == 'hu' ? 'en' : 'hu';
    settingsProv
        .updateSettings(settingsProv.settings.copyWith(locale: newLocale));
    context.setLocale(Locale(newLocale));
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle:
          Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      trailing: Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
      onTap: onTap,
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final ThemeMode mode;
  final ThemeMode current;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.mode,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<ThemeMode>(
      title: Text(label),
      value: mode,
      groupValue: current,
      onChanged: (_) => onTap(),
    );
  }
}
