import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/alarm_point.dart';
import '../providers/settings_provider.dart';
import '../services/audio_service.dart';
import '../services/platform_service.dart';

class AlarmSettingsScreen extends StatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  State<AlarmSettingsScreen> createState() => _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends State<AlarmSettingsScreen> {
  final AudioService _audioService = AudioService();
  String? _playingSound;

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  void _togglePreview(String soundKey) async {
    if (_playingSound == soundKey) {
      await _audioService.stop();
      setState(() => _playingSound = null);
    } else {
      await _audioService.playPreview(soundKey);
      setState(() => _playingSound = soundKey);
    }
  }

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

          // System sounds (mobile only)
          if (PlatformService.isMobile) ...[
            Text('Rendszer hangok',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const SizedBox(height: 4),
            _SoundTile(
              name: 'Rendszer alarm',
              icon: Icons.alarm,
              selected: settings.defaultAlarmSound == AudioService.systemAlarmKey,
              playing: _playingSound == AudioService.systemAlarmKey,
              onTap: () => settingsProv.updateSettings(
                  settings.copyWith(defaultAlarmSound: AudioService.systemAlarmKey)),
              onPreview: () => _togglePreview(AudioService.systemAlarmKey),
            ),
            _SoundTile(
              name: 'Rendszer értesítés',
              icon: Icons.notifications,
              selected: settings.defaultAlarmSound == AudioService.systemNotificationKey,
              playing: _playingSound == AudioService.systemNotificationKey,
              onTap: () => settingsProv.updateSettings(
                  settings.copyWith(defaultAlarmSound: AudioService.systemNotificationKey)),
              onPreview: () => _togglePreview(AudioService.systemNotificationKey),
            ),
            _SoundTile(
              name: 'Rendszer csengőhang',
              icon: Icons.ring_volume,
              selected: settings.defaultAlarmSound == AudioService.systemRingtoneKey,
              playing: _playingSound == AudioService.systemRingtoneKey,
              onTap: () => settingsProv.updateSettings(
                  settings.copyWith(defaultAlarmSound: AudioService.systemRingtoneKey)),
              onPreview: () => _togglePreview(AudioService.systemRingtoneKey),
            ),
            const SizedBox(height: 12),
            Text('Beépített hangok',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const SizedBox(height: 4),
          ],

          // Built-in asset sounds
          ...AudioService.assetSounds.keys.map((key) {
            final name = AudioService.hardcodedSounds[key] ?? key;
            return _SoundTile(
              name: name,
              icon: Icons.music_note,
              selected: settings.defaultAlarmSound == key,
              playing: _playingSound == key,
              onTap: () => settingsProv
                  .updateSettings(settings.copyWith(defaultAlarmSound: key)),
              onPreview: () => _togglePreview(key),
            );
          }),

          const SizedBox(height: 24),

          // Vibration toggle (mobile only)
          if (PlatformService.supportsVibration)
            SwitchListTile(
              title: Text(tr('vibration')),
              subtitle: const Text('Alarm vibráció', style: TextStyle(fontSize: 11)),
              value: settings.vibrationEnabled,
              onChanged: (v) => settingsProv
                  .updateSettings(settings.copyWith(vibrationEnabled: v)),
            ),
          // Haptic feedback toggle (mobile only)
          if (PlatformService.supportsVibration)
            SwitchListTile(
              title: const Text('Haptikus visszajelzés'),
              subtitle: const Text('Long press, fast assign', style: TextStyle(fontSize: 11)),
              value: settings.hapticFeedback,
              onChanged: (v) => settingsProv
                  .updateSettings(settings.copyWith(hapticFeedback: v)),
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
  final IconData icon;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  const _SoundTile({
    required this.name,
    required this.icon,
    required this.selected,
    required this.playing,
    required this.onTap,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey,
          size: 20),
      title: Text(name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          )),
      selected: selected,
      trailing: IconButton(
        icon: Icon(
          playing ? Icons.stop_circle : Icons.play_circle,
          color: playing
              ? Colors.red
              : Theme.of(context).colorScheme.primary,
        ),
        onPressed: onPreview,
      ),
      onTap: onTap,
      dense: true,
    );
  }
}
