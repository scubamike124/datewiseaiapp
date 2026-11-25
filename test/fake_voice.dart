import 'package:flutter/foundation.dart';

import 'package:datewise_ai/avatar/lip_sync.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/services/reply_language.dart';
import 'package:datewise_ai/services/voice_service.dart';

/// A voice that "speaks" without audio on a clock the test controls: the
/// lip-sync driver is planned from the spoken text exactly as the device
/// voice does, so the chat screen's subtitle follows it. Counts every
/// `speak` call (a reply must be spoken once).
class ScriptedVoice implements VoiceService, LipSyncSource {
  ScriptedVoice() {
    lipSync = LipSyncDriver(clock: () => now);
  }

  /// The driver's clock; advance it to move the speech along.
  Duration now = Duration.zero;
  final spoken = <String>[];
  final _speaking = ValueNotifier<bool>(false);

  @override
  late final LipSyncDriver lipSync;

  @override
  bool get available => true;

  @override
  ValueListenable<bool> get speaking => _speaking;

  @override
  Future<void> speak(String text, Coach coach) async {
    spoken.add(text);
    final clean = text.replaceAll(RegExp(r'\*\*|__|[*_#>`]'), '').trim();
    lipSync.begin(clean, ReplyLanguage.detect(clean, fallback: coach.language));
    lipSync.started();
    _speaking.value = true;
  }

  /// The speech finished.
  void finish() {
    lipSync.end();
    _speaking.value = false;
  }

  @override
  Future<void> stop() async => finish();
}
