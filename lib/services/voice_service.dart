import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/coach.dart';

/// Reads coach text aloud with the device's own text-to-speech voices
/// (flutter_tts, MIT). Nothing is sent to a server.
abstract class VoiceService {
  /// False on web and in tests: the UI hides every "listen" control.
  bool get available;

  /// True while a coach is speaking (drives the portrait's "speaking" glow).
  ValueListenable<bool> get speaking;

  Future<void> speak(String text, Coach coach);
  Future<void> stop();
}

/// No text-to-speech (web, tests, unsupported platforms).
class NoVoiceService implements VoiceService {
  NoVoiceService();
  final _speaking = ValueNotifier<bool>(false);
  @override
  bool get available => false;
  @override
  ValueListenable<bool> get speaking => _speaking;
  @override
  Future<void> speak(String text, Coach coach) async {}
  @override
  Future<void> stop() async {}
}

/// On-device TTS for iOS and Android. Picks the best installed system voice
/// for the coach's locale (en-US; es-MX, then es-ES/es-US), preferring
/// premium/enhanced quality and the coach's gender.
class DeviceVoiceService implements VoiceService {
  DeviceVoiceService._(this._tts, this._voices);

  final FlutterTts _tts;
  final List<Map<String, String>> _voices;
  final _speaking = ValueNotifier<bool>(false);
  final Map<String, Map<String, String>?> _chosen = {};

  static Future<VoiceService> create() async {
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      return NoVoiceService();
    }
    try {
      final tts = FlutterTts();
      await tts.awaitSpeakCompletion(false);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await tts.setSharedInstance(true);
        await tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      }
      final raw = await tts.getVoices;
      final voices = <Map<String, String>>[
        if (raw is List)
          for (final v in raw)
            if (v is Map) {for (final e in v.entries) '${e.key}': '${e.value}'},
      ];
      final service = DeviceVoiceService._(tts, voices);
      tts.setStartHandler(() => service._speaking.value = true);
      tts.setCompletionHandler(() => service._speaking.value = false);
      tts.setCancelHandler(() => service._speaking.value = false);
      tts.setErrorHandler((_) => service._speaking.value = false);
      return service;
    } catch (_) {
      return NoVoiceService();
    }
  }

  @override
  bool get available => true;

  @override
  ValueListenable<bool> get speaking => _speaking;

  static const _locales = {
    CoachLanguage.en: ['en-US', 'en-GB', 'en-AU', 'en'],
    CoachLanguage.es: ['es-MX', 'es-ES', 'es-US', 'es'],
  };

  Map<String, String>? _voiceFor(Coach coach) =>
      _chosen.putIfAbsent(coach.id, () => pickVoice(_voices, coach));

  /// Best voice for [coach] among [voices] (maps with name, locale, quality,
  /// gender). Visible for tests.
  @visibleForTesting
  static Map<String, String>? pickVoice(List<Map<String, String>> voices, Coach coach) {
    int qualityScore(String? q) => switch (q) {
          'premium' => 3,
          'enhanced' => 2,
          _ => 1,
        };
    final wantGender = coach.gender == CoachGender.female ? 'female' : 'male';
    final prefs = _locales[coach.language]!;
    for (final loc in prefs) {
      final matches = voices.where((v) {
        final l = (v['locale'] ?? '').replaceAll('_', '-').toLowerCase();
        return loc.length == 2 ? l.startsWith(loc) : l == loc.toLowerCase();
      }).toList();
      if (matches.isEmpty) continue;
      int score(Map<String, String> v) =>
          qualityScore(v['quality']) * 10 + ((v['gender'] ?? '') == wantGender ? 5 : 0);
      matches.sort((a, b) => score(b).compareTo(score(a)));
      return matches.first;
    }
    return null;
  }

  @override
  Future<void> speak(String text, Coach coach) async {
    final clean = text
        .replaceAll(RegExp(r'\*\*|__|[*_#>`]'), '')
        .replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '')
        .trim();
    if (clean.isEmpty) return;
    await _tts.stop();
    final voice = _voiceFor(coach);
    if (voice != null && voice['name'] != null && voice['locale'] != null) {
      await _tts.setVoice({
        'name': voice['name']!,
        'locale': voice['locale']!,
        if (voice['identifier'] != null) 'identifier': voice['identifier']!,
      });
    } else {
      await _tts.setLanguage(coach.language.locale);
    }
    await _tts.setSpeechRate(0.5);
    await _tts.speak(clean);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _speaking.value = false;
  }
}
