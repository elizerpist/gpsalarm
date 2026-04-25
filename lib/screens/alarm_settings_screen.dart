import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/alarm_point.dart';
import '../providers/settings_provider.dart';
import '../services/audio_service.dart';
import '../services/platform_service.dart';

class AlarmSettingsScreen extends StatelessWidget {
  const AlarmSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProv = context.watch<SettingsProvider>();
    final settings = settingsProv.settings;

    return Scaffold(
      appBar: AppBar(title: Text(tr('alarm_settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Alarm type
          Text(tr('alarm_type'),
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _AlarmTypeRadio(
            label: tr('sound_and_vibration'),
            value: AlarmType.soundAndVibration,
            groupValue: settings.defaultAlarmType,
            onChanged: (v) => settingsProv.updateSettings(
                settings.copyWith(defaultAlarmType: v)),
          ),
          _AlarmTypeRadio(
            label: tr('notification_only'),
            value: AlarmType.notificationOnly,
            groupValue: settings.defaultAlarmType,
            onChanged: (v) => settingsProv.updateSettings(
                settings.copyWith(defaultAlarmType: v)),
          ),
          if (PlatformService.supportsFullScreenAlarm)
            _AlarmTypeRadio(
              label: tr('full_screen_alarm'),
              value: AlarmType.fullScreenAlarm,
              groupValue: settings.defaultAlarmType,
              onChanged: (v) => settingsProv.updateSettings(
                  settings.copyWith(defaultAlarmType: v)),
            ),
          const SizedBox(height: 24),
          // Alarm sound
          Text(tr('alarm_sound'),
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...AudioService.hardcodedSounds.keys.map((name) {
            final displayName = name.replaceAll('_', ' ');
            return _SoundTile(
              name: displayName[0].toUpperCase() + displayName.substring(1),
              selected: settings.defaultAlarmSound == name,
              onTap: () => settingsProv.updateSettings(
                  settings.copyWith(defaultAlarmSound: name)),
            );
          }),
          const SizedBox(height: 24),
          // Vibration toggle (mobile only)
          if (PlatformService.supportsVibration)
            SwitchListTile(
              title: Text(tr('vibration')),
              value: settings.vibrationEnabled,
              onChanged: (v) => settingsProv
                  .updateSettings(settings.copyWith(vibrationEnabled: v)),
            ),
          const SizedBox(height: 16),
          // Volume slider
          Text(tr('volume'),
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600)),
          Slider(
            value: settings.volume,
            min: 0,
            max: 1,
            divisions: 10,
            label: '${(settings.volume * 100).round()}%',
            onChanged: (v) =>
                settingsProv.updateSettings(settings.copyWith(volume: v)),
          ),
        ],
      ),
    );
  }
}

class _AlarmTypeRadio extends StatelessWidget {
  final String label;
  final AlarmType value;
  final AlarmType groupValue;
  final void Function(AlarmType) onChanged;

  const _AlarmTypeRadio({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<AlarmType>(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      groupValue: groupValue,
      onChanged: (v) => onChanged(v!),
      dense: true,
    );
  }
}

class _SoundTile extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _SoundTile({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.volume_up,
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey),
      title: Text(name,
          style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      selected: selected,
      onTap: onTap,
      dense: true,
    );
  }
}
