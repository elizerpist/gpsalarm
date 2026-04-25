import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  final FlutterRingtonePlayer _ringtonePlayer = FlutterRingtonePlayer();
  bool _isPlayingRingtone = false;

  static const String systemAlarmKey = 'system_alarm';
  static const String systemNotificationKey = 'system_notification';
  static const String systemRingtoneKey = 'system_ringtone';

  static const Map<String, String> hardcodedSounds = {
    systemAlarmKey: 'Rendszer alarm',
    systemNotificationKey: 'Rendszer értesítés',
    systemRingtoneKey: 'Rendszer csengőhang',
    'classic_bell': 'Classic Bell',
    'radar_ping': 'Radar Ping',
    'gentle_wake': 'Gentle Wake',
  };

  static const Map<String, String> assetSounds = {
    'classic_bell': 'sounds/classic_bell.wav',
    'radar_ping': 'sounds/radar_ping.wav',
    'gentle_wake': 'sounds/gentle_wake.wav',
  };

  Future<void> playAlarm(String soundName, {double volume = 0.7, bool loop = true}) async {
    await stop();

    if (kIsWeb) {
      // Web: only asset sounds work
      if (assetSounds.containsKey(soundName)) {
        await _player.setVolume(volume);
        await _player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
        await _player.play(AssetSource(assetSounds[soundName]!));
      }
      return;
    }

    // System sounds via ringtone player
    if (soundName == systemAlarmKey) {
      _isPlayingRingtone = true;
      _ringtonePlayer.playAlarm(
        volume: volume,
        looping: loop,
        asAlarm: true,
      );
      return;
    }
    if (soundName == systemNotificationKey) {
      _isPlayingRingtone = true;
      _ringtonePlayer.playNotification(
        volume: volume,
        looping: loop,
      );
      return;
    }
    if (soundName == systemRingtoneKey) {
      _isPlayingRingtone = true;
      _ringtonePlayer.playRingtone(
        volume: volume,
        looping: loop,
      );
      return;
    }

    // Asset sounds
    if (assetSounds.containsKey(soundName)) {
      await _player.setVolume(volume);
      await _player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
      await _player.play(AssetSource(assetSounds[soundName]!));
      return;
    }

    // Custom file path
    await _player.setVolume(volume);
    await _player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
    await _player.play(DeviceFileSource(soundName));
  }

  Future<void> playPreview(String soundName) async {
    await playAlarm(soundName, volume: 0.5, loop: false);
  }

  Future<void> stop() async {
    if (_isPlayingRingtone) {
      _ringtonePlayer.stop();
      _isPlayingRingtone = false;
    }
    await _player.stop();
  }

  void dispose() {
    stop();
    _player.dispose();
  }
}
