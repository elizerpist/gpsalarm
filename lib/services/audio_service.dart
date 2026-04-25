import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();

  static const Map<String, String> hardcodedSounds = {
    'classic_bell': 'sounds/classic_bell.mp3',
    'radar_ping': 'sounds/radar_ping.mp3',
    'gentle_wake': 'sounds/gentle_wake.mp3',
  };

  Future<void> playAlarm(String soundName, {double volume = 0.7}) async {
    await _player.setVolume(volume);
    if (hardcodedSounds.containsKey(soundName)) {
      await _player.play(AssetSource(hardcodedSounds[soundName]!));
    } else {
      if (!kIsWeb) {
        await _player.play(DeviceFileSource(soundName));
      }
    }
  }

  Future<void> stop() async {
    await _player.stop();
  }

  void dispose() {
    _player.dispose();
  }
}
