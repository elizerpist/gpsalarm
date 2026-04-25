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
          // Start view
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
          const SizedBox(height: 24),
          // Map tile style
          Text('Térkép stílus',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _TileStyleCard(
            title: 'Standard',
            subtitle: 'Utcák, épületek, alap térkép',
            icon: Icons.map,
            selected: settings.mapTileStyle == MapTileStyle.standard,
            onTap: () => settingsProv.updateSettings(
                settings.copyWith(mapTileStyle: MapTileStyle.standard)),
          ),
          const SizedBox(height: 8),
          _TileStyleCard(
            title: 'Humanitarian',
            subtitle: 'Világos, utca-fókuszú, tiszta',
            icon: Icons.streetview,
            selected: settings.mapTileStyle == MapTileStyle.humanitarian,
            onTap: () => settingsProv.updateSettings(
                settings.copyWith(mapTileStyle: MapTileStyle.humanitarian)),
          ),
          const SizedBox(height: 8),
          _TileStyleCard(
            title: 'Topográfiai',
            subtitle: 'Domborzat, szintvonalak, terep',
            icon: Icons.terrain,
            selected: settings.mapTileStyle == MapTileStyle.topo,
            onTap: () => settingsProv.updateSettings(
                settings.copyWith(mapTileStyle: MapTileStyle.topo)),
          ),
        ],
      ),
    );
  }
}

class _TileStyleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TileStyleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
                size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : null)),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
