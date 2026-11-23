import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/coach.dart';
import 'reply_language.dart';

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

/// How a coach sounds: the system-voice locales to try in order, the voice
/// names known to fit the coach (iOS ships these; Android voices are matched
/// by locale and gender), and a pitch/rate that keeps the four coaches
/// distinguishable even when a device has a single voice per language.
@immutable
class CoachVoiceProfile {
  const CoachVoiceProfile({
    required this.locales,
    required this.preferredNames,
    required this.otherGenderNames,
    required this.pitch,
    required this.rate,
  });

  final List<String> locales;
  final List<String> preferredNames;

  /// Names of known voices of the other gender, avoided when the voice
  /// metadata has no gender.
  final List<String> otherGenderNames;
  final double pitch;
  final double rate;

  static const _enFemale = ['Ava', 'Samantha', 'Allison', 'Susan', 'Zoe', 'Nicky', 'Joelle', 'Noelle'];
  static const _enMale = ['Evan', 'Nathan', 'Alex', 'Tom', 'Aaron', 'Daniel', 'Fred', 'Reed'];
  static const _esFemale = ['Paulina', 'Mónica', 'Monica', 'Marisol', 'Angélica', 'Angelica', 'Isabela', 'Soledad'];
  static const _esMale = ['Juan', 'Jorge', 'Diego', 'Carlos', 'Eddy', 'Reed'];

  static const _enLocales = ['en-US', 'en-GB', 'en-AU', 'en'];
  static const _esLocales = ['es-MX', 'es-US', 'es-ES', 'es'];

  static const ava = CoachVoiceProfile(
      locales: _enLocales, preferredNames: _enFemale, otherGenderNames: _enMale, pitch: 1.05, rate: 0.5);
  static const ethan = CoachVoiceProfile(
      locales: _enLocales, preferredNames: _enMale, otherGenderNames: _enFemale, pitch: 0.92, rate: 0.47);
  static const sofia = CoachVoiceProfile(
      locales: _esLocales, preferredNames: _esFemale, otherGenderNames: _esMale, pitch: 1.08, rate: 0.49);
  static const diego = CoachVoiceProfile(
      locales: _esLocales, preferredNames: _esMale, otherGenderNames: _esFemale, pitch: 0.9, rate: 0.46);

  /// The voice (locales and names) for [coach] speaking [language]: their
  /// own profile, or for the other language the profile of the same-gender
  /// coach of that language. Pitch and rate always come from [of].
  static CoachVoiceProfile forLanguage(Coach coach, CoachLanguage language) => language == coach.language
      ? of(coach)
      : of(Coaches.forLanguage(language).firstWhere((c) => c.gender == coach.gender,
          orElse: () => Coaches.forLanguage(language).first));

  static CoachVoiceProfile of(Coach coach) => switch (coach.id) {
        'ethan' => ethan,
        'sofia' => sofia,
        'diego' => diego,
        'ava' => ava,
        _ => coach.language == CoachLanguage.es
            ? (coach.gender == CoachGender.female ? sofia : diego)
            : (coach.gender == CoachGender.female ? ava : ethan),
      };
}

/// On-device TTS for iOS and Android. Picks, per coach, the installed system
/// voice that fits their language and gender (see [pickVoice]) and speaks
/// with the coach's own pitch and rate.
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
      // No audio session is configured or activated here: launching the app
      // must not stop or duck the user's music, and must not touch the
      // microphone. The session is set up on the first [speak].
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

  Map<String, String>? _voiceFor(Coach coach, CoachLanguage language) =>
      _chosen.putIfAbsent('${coach.id}/${language.name}', () => pickVoice(_voices, coach, language: language));

  /// The best installed voice for [coach] among [voices] (flutter_tts
  /// `getVoices` maps: name, locale, and on iOS also quality, gender and
  /// identifier). Order of preference:
  ///  1. a voice of the coach's gender (from the metadata, or else a known
  ///     voice name), trying the coach's locales in order (en-US; es-MX,
  ///     es-US, es-ES); within a locale, known names first, then quality;
  ///  2. any voice in those locales not known to be the other gender;
  ///  3. any voice in those locales (pitch then keeps the coaches apart).
  /// Null when no voice matches the language (the default voice is used).
  /// [language] (default: the coach's own) is the language of the text: a
  /// coach answering in the other language gets a same-gender voice of it.
  @visibleForTesting
  static Map<String, String>? pickVoice(List<Map<String, String>> voices, Coach coach, {CoachLanguage? language}) {
    final profile = CoachVoiceProfile.forLanguage(coach, language ?? coach.language);
    final want = coach.gender == CoachGender.female ? 'female' : 'male';

    String norm(String? s) => (s ?? '').replaceAll('_', '-').toLowerCase();
    bool inLocale(Map<String, String> v, String loc) {
      final l = norm(v['locale']);
      return loc.length == 2 ? l == loc || l.startsWith('$loc-') : l == loc.toLowerCase();
    }

    String baseName(Map<String, String> v) => (v['name'] ?? '').split(RegExp(r'[ (]')).first.toLowerCase();
    int nameRank(Map<String, String> v, List<String> names) {
      final n = baseName(v);
      for (var i = 0; i < names.length; i++) {
        if (names[i].toLowerCase() == n) return i;
      }
      return -1;
    }

    // true = coach's gender, false = other gender, null = unknown.
    bool? genderMatch(Map<String, String> v) {
      final g = norm(v['gender']);
      if (g.contains('female')) return want == 'female';
      if (g.contains('male')) return want == 'male';
      if (nameRank(v, profile.preferredNames) >= 0) return true;
      if (nameRank(v, profile.otherGenderNames) >= 0) return false;
      return null;
    }

    int quality(Map<String, String> v) => switch (norm(v['quality'])) {
          'premium' => 3,
          'enhanced' => 2,
          _ => 1,
        };

    int score(Map<String, String> v) {
      final rank = nameRank(v, profile.preferredNames);
      return (rank >= 0 ? 100 - rank : 0) * 10 + quality(v);
    }

    Map<String, String>? best(bool Function(Map<String, String>) accept) {
      for (final loc in profile.locales) {
        final matches = voices.where((v) => inLocale(v, loc) && accept(v)).toList();
        if (matches.isEmpty) continue;
        matches.sort((a, b) => score(b).compareTo(score(a)));
        return matches.first;
      }
      return null;
    }

    return best((v) => genderMatch(v) == true) ??
        best((v) => genderMatch(v) == null) ??
        best((_) => true);
  }

  @override
  Future<void> speak(String text, Coach coach) async {
    final clean = text
        .replaceAll(RegExp(r'\*\*|__|[*_#>`]'), '')
        .replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '')
        .trim();
    if (clean.isEmpty) return;
    await _tts.stop();
    await _prepareAudioSession();
    // Coaches answer in the user's language, so the voice follows the
    // language of the text, not the coach's default.
    final language = ReplyLanguage.detect(clean, fallback: coach.language);
    final voice = _voiceFor(coach, language);
    if (voice != null && voice['name'] != null && voice['locale'] != null) {
      await _tts.setVoice({
        'name': voice['name']!,
        'locale': voice['locale']!,
        if (voice['identifier'] != null) 'identifier': voice['identifier']!,
      });
    } else {
      await _tts.setLanguage(language.locale);
    }
    // The coach's own pitch and rate, whichever language they speak.
    final profile = CoachVoiceProfile.of(coach);
    await _tts.setPitch(profile.pitch);
    await _tts.setSpeechRate(profile.rate);
    await _tts.speak(clean);
  }

  /// Configures the iOS audio session only when the coach is about to speak:
  /// playback (no recording, so never a microphone prompt) that ducks and
  /// mixes with the user's own audio instead of stopping it. flutter_tts
  /// deactivates the session again when the utterance finishes. Set before
  /// every utterance, since hold-to-talk recognition changes the category.
  Future<void> _prepareAudioSession() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ],
        IosTextToSpeechAudioMode.spokenAudio,
      );
      await _tts.setSharedInstance(true);
    } catch (_) {
      // Speaking still works with the system's default session.
    }
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _speaking.value = false;
  }
}
