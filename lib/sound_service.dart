import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';

class SoundService {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> playSosAlarm() async {
    await _player.play(UrlSource('https://actions.google.com/sounds/v1/alarms/alarm_clock.ogg'));
    if (await Vibrate.canVibrate) {
      Vibrate.vibrateWithPauses([
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 200),
        const Duration(milliseconds: 500),
      ]);
    }
  }

  static Future<void> playMessageBeep() async {
    await _player.play(UrlSource('https://actions.google.com/sounds/v1/communication/beep_short.ogg'));
  }
}
