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
          const Divider(),
          const SizedBox(height: 16),

          // Map Provider selection
          Text('Térkép forrás',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          // Free OSM
          _ProviderCard(
            title: 'Ingyenes (OpenStreetMap)',
            subtitle: 'Korlátlan, API kulcs nélkül, 6 stílus',
            icon: Icons.public,
            selected: settings.mapProvider == MapTileProvider.free,
            onTap: () => settingsProv
                .updateSettings(settings.copyWith(mapProvider: MapTileProvider.free)),
          ),
          if (settings.mapProvider == MapTileProvider.free) ...[
            const SizedBox(height: 8),
            _FreeTileStylePicker(
              current: settings.mapTileStyle,
              onChanged: (style) => settingsProv
                  .updateSettings(settings.copyWith(mapTileStyle: style)),
            ),
          ],

          const SizedBox(height: 12),

          // Google Maps
          _ProviderCard(
            title: 'Google Maps',
            subtitle: 'Havi \$200 kredit ingyenes, API kulcs szükséges',
            icon: Icons.map,
            selected: settings.mapProvider == MapTileProvider.googleMaps,
            onTap: () => settingsProv.updateSettings(
                settings.copyWith(mapProvider: MapTileProvider.googleMaps)),
          ),
          if (settings.mapProvider == MapTileProvider.googleMaps) ...[
            const SizedBox(height: 8),
            _ApiKeyInput(
              label: 'Google Maps API Key',
              value: settings.googleMapsApiKey ?? '',
              onSaved: (key) => settingsProv
                  .updateSettings(settings.copyWith(googleMapsApiKey: key)),
            ),
          ],

          const SizedBox(height: 12),

          // MapTiler
          _ProviderCard(
            title: 'MapTiler',
            subtitle: '100k betöltés/hó ingyenes, testreszabható stílusok',
            icon: Icons.layers,
            selected: settings.mapProvider == MapTileProvider.mapTiler,
            onTap: () => settingsProv.updateSettings(
                settings.copyWith(mapProvider: MapTileProvider.mapTiler)),
          ),
          if (settings.mapProvider == MapTileProvider.mapTiler) ...[
            const SizedBox(height: 8),
            _ApiKeyInput(
              label: 'MapTiler API Key',
              value: settings.mapTilerApiKey ?? '',
              onSaved: (key) => settingsProv
                  .updateSettings(settings.copyWith(mapTilerApiKey: key)),
            ),
            const SizedBox(height: 8),
            _MapTilerStylePicker(
              current: settings.mapTilerStyle,
              onChanged: (style) => settingsProv
                  .updateSettings(settings.copyWith(mapTilerStyle: style)),
            ),
          ],

          const SizedBox(height: 12),

          // Vector (MapLibre)
          _ProviderCard(
            title: 'Vektor (MapLibre)',
            subtitle: 'Éles szövegek, smooth zoom, 60fps, ingyenes',
            icon: Icons.auto_awesome,
            selected: settings.mapProvider == MapTileProvider.vector,
            onTap: () => settingsProv.updateSettings(
                settings.copyWith(mapProvider: MapTileProvider.vector)),
          ),
          if (settings.mapProvider == MapTileProvider.vector) ...[
            const SizedBox(height: 8),
            _VectorStylePicker(
              current: settings.vectorStyleUrl,
              onChanged: (url) => settingsProv
                  .updateSettings(settings.copyWith(vectorStyleUrl: url)),
            ),
          ],
        ],
      ),
    );
  }
}

// --- Provider Card ---

class _ProviderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderCard({
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

// --- API Key Input ---

class _ApiKeyInput extends StatefulWidget {
  final String label;
  final String value;
  final void Function(String) onSaved;

  const _ApiKeyInput({
    required this.label,
    required this.value,
    required this.onSaved,
  });

  @override
  State<_ApiKeyInput> createState() => _ApiKeyInputState();
}

class _ApiKeyInputState extends State<_ApiKeyInput> {
  late TextEditingController _controller;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _ApiKeyInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  obscureText: _obscure,
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'Illeszd be az API kulcsot...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          size: 18),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  widget.onSaved(_controller.text.trim());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('API kulcs mentve'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('Mentés', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Free Tile Style Picker ---

class _FreeTileStylePicker extends StatelessWidget {
  final MapTileStyle current;
  final void Function(MapTileStyle) onChanged;

  const _FreeTileStylePicker({
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _styleChip('Standard', MapTileStyle.standard),
          _styleChip('Humanitarian', MapTileStyle.humanitarian),
          _styleChip('Topo', MapTileStyle.topo),
          _styleChip('Positron', MapTileStyle.positron),
          _styleChip('Voyager', MapTileStyle.voyager),
          _styleChip('Dark', MapTileStyle.darkMatter),
        ],
      ),
    );
  }

  Widget _styleChip(String label, MapTileStyle style) {
    final selected = current == style;
    return Builder(builder: (context) {
      return GestureDetector(
        onTap: () => onChanged(style),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[400]!,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? Colors.white : Colors.grey[600],
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );
    });
  }
}

// --- MapTiler Style Picker ---

class _MapTilerStylePicker extends StatelessWidget {
  final String current;
  final void Function(String) onChanged;

  const _MapTilerStylePicker({
    required this.current,
    required this.onChanged,
  });

  static const styles = {
    'streets-v2': 'Streets',
    'basic-v2': 'Basic',
    'bright-v2': 'Bright',
    'pastel': 'Pastel',
    'toner-v2': 'Toner',
    'satellite': 'Satellite',
    'hybrid': 'Hybrid',
    'openstreetmap': 'OpenStreetMap',
    'winter-v2': 'Winter',
    'dataviz': 'Dataviz',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MapTiler stílus',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: styles.entries.map((e) {
              final selected = current == e.key;
              return GestureDetector(
                onTap: () => onChanged(e.key),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[400]!,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? Colors.white : Colors.grey[600],
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// --- Vector Style Picker ---

class _VectorStylePicker extends StatelessWidget {
  final String current;
  final void Function(String) onChanged;

  const _VectorStylePicker({
    required this.current,
    required this.onChanged,
  });

  static const styles = {
    'https://tiles.openfreemap.org/styles/liberty': 'Liberty',
    'https://tiles.openfreemap.org/styles/bright': 'Bright',
    'https://tiles.openfreemap.org/styles/positron': 'Positron',
    'https://demotiles.maplibre.org/style.json': 'MapLibre Demo',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vektor stílus (ingyenes, API kulcs nélkül)',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: styles.entries.map((e) {
              final selected = current == e.key;
              return GestureDetector(
                onTap: () => onChanged(e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[400]!,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? Colors.white : Colors.grey[600],
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
