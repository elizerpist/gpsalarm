import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/app_settings.dart';
import '../providers/settings_provider.dart';

class MapSettingsScreen extends StatelessWidget {
  const MapSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProv = context.watch<SettingsProvider>();
    final settings = settingsProv.settings;

    return Scaffold(
      appBar: AppBar(title: Text(tr('map_settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('start_view'),
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          RadioListTile<MapStartView>(
            title: Text(tr('current_gps')),
            value: MapStartView.currentGps,
            groupValue: settings.mapStartView,
            onChanged: (v) => settingsProv
                .updateSettings(settings.copyWith(mapStartView: v)),
          ),
          RadioListTile<MapStartView>(
            title: Text(tr('last_position')),
            value: MapStartView.lastPosition,
            groupValue: settings.mapStartView,
            onChanged: (v) => settingsProv
                .updateSettings(settings.copyWith(mapStartView: v)),
          ),
        ],
      ),
    );
  }
}
