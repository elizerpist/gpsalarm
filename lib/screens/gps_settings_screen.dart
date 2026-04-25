import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/app_settings.dart';
import '../providers/settings_provider.dart';

class GpsSettingsScreen extends StatelessWidget {
  const GpsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProv = context.watch<SettingsProvider>();
    final settings = settingsProv.settings;

    return Scaffold(
      appBar: AppBar(title: Text(tr('gps_settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('polling_mode'),
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          RadioListTile<GpsPollingMode>(
            title: Text(tr('continuous')),
            value: GpsPollingMode.continuous,
            groupValue: settings.gpsPollingMode,
            onChanged: (v) => settingsProv.updateSettings(
                settings.copyWith(gpsPollingMode: v)),
          ),
          RadioListTile<GpsPollingMode>(
            title: Text(tr('custom_interval')),
            value: GpsPollingMode.custom,
            groupValue: settings.gpsPollingMode,
            onChanged: (v) => settingsProv.updateSettings(
                settings.copyWith(gpsPollingMode: v)),
          ),
          if (settings.gpsPollingMode == GpsPollingMode.custom) ...[
            const SizedBox(height: 16),
            Text('Intervallum: ${settings.customPollingInterval.inSeconds}s',
                style: const TextStyle(fontSize: 14)),
            Slider(
              value: settings.customPollingInterval.inSeconds.toDouble(),
              min: 10,
              max: 300,
              divisions: 29,
              label: '${settings.customPollingInterval.inSeconds}s',
              onChanged: (v) => settingsProv.updateSettings(
                settings.copyWith(
                    customPollingInterval: Duration(seconds: v.round())),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('10s', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                Text('5min', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
