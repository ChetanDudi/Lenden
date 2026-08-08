import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static bool _soundEnabled = true;
  static final AudioPlayer _player = AudioPlayer();

  static void update({bool? sound}) {
    if (sound != null) _soundEnabled = sound;
  }

  static Future<void> playNotification() async {
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('sounds/notification.wav'));
    } catch (_) {}
  }
}
