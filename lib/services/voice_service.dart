import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../avatar/lip_sync.dart';
import '../avatar/speech_audio.dart';
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

  // When two coaches of the same gender share the only installed voice of
  // a language (Ava answering in Spanish with Sofía's voice, Ethan with
  // Diego's), rate and pitch keep them apart: Ava and Sofía about 16% in
  // rate and 2 semitones in pitch, Ethan and Diego about 8% and 1.3.
  static const ava = CoachVoiceProfile(
      locales: _enLocales, preferredNames: _enFemale, otherGenderNames: _enMale, pitch: 0.98, rate: 0.54);
  static const ethan = CoachVoiceProfile(
      locales: _enLocales, preferredNames: _enMale, otherGenderNames: _enFemale, pitch: 0.91, rate: 0.49);
  static const sofia = CoachVoiceProfile(
      locales: _esLocales, preferredNames: _esFemale, otherGenderNames: _esMale, pitch: 1.1, rate: 0.46);
  static const diego = CoachVoiceProfile(
      locales: _esLocales, preferredNames: _esMale, otherGenderNames: _esFemale, pitch: 0.88, rate: 0.45);

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
class DeviceVoiceService implements VoiceService, LipSyncSource {
  DeviceVoiceService._(this._tts, this._voices, this._audio) {
    _audioSub = _audio?.events.listen(_onAudioEvent);
    _wireTts();
  }

  /// A service over [tts] and an optional native [audio] path, for tests.
  @visibleForTesting
  factory DeviceVoiceService.forTesting(FlutterTts tts, List<Map<String, String>> voices, {SpeechAudioBackend? audio}) =>
      DeviceVoiceService._(tts, voices, audio);

  /// Speak through the native audio path (ios/Runner/AppDelegate.swift),
  /// which renders the speech to PCM and reports its loudness so the
  /// avatar's jaw follows the real audio. Any failure falls back to
  /// flutter_tts for the rest of the session.
  ///
  /// Off unless the build sets `--dart-define=DW_AVATAR_AUDIO_PATH=true`:
  /// it has not been tested on an iPhone yet, so App Store builds keep the
  /// flutter_tts path; TestFlight builds turn it on to test it
  /// (docs/avatar/TALKING_AVATARS.md).
  static bool useAudioPath = const bool.fromEnvironment('DW_AVATAR_AUDIO_PATH');

  /// How long to wait for the native path to start playing before giving
  /// up and speaking through flutter_tts instead.
  static Duration audioStartTimeout = const Duration(seconds: 3);
  Timer? _audioWatchdog;

  /// Consecutive replies whose playback did not start in time. A cold
  /// Premium voice can be slow once, so the path is turned off only after
  /// [maxStartTimeouts] in a row.
  int _startTimeouts = 0;
  static const int maxStartTimeouts = 2;

  final SpeechAudioBackend? _audio;
  StreamSubscription<SpeechAudioEvent>? _audioSub;
  bool _audioFailed = false;

  /// The flutter_tts utterance to play if the audio path fails before it
  /// starts (same text, voice, pitch and rate).
  Future<void> Function()? _fallback;
  int _audioGeneration = -1;

  bool get _audioPathOn => useAudioPath && _audio != null && !_audioFailed;

  /// Stops listening to the native audio path (tests; the app keeps one
  /// service while it runs).
  @visibleForTesting
  Future<void> dispose() async {
    _audioWatchdog?.cancel();
    await _audioSub?.cancel();
  }

  void _wireTts() {
    final lip = lipSync;
    _tts.setStartHandler(() {
      _speaking.value = true;
      lip.started();
    });
    // AVSpeechSynthesizer reports each word as it starts (character range
    // in the spoken text); the avatar's mouth follows it.
    _tts.setProgressHandler((_, start, end, _) => lip.word(start, end));
    _tts.setCompletionHandler(() {
      _speaking.value = false;
      lip.end();
    });
    _tts.setCancelHandler(() {
      _speaking.value = false;
      lip.end();
    });
    _tts.setErrorHandler((_) {
      _speaking.value = false;
      lip.end();
    });
  }

  void _onAudioEvent(SpeechAudioEvent e) {
    if (_audioGeneration != _generation) return; // a stopped or replaced utterance
    switch (e) {
      case SpeechAudioStarted(:final latency):
        _audioWatchdog?.cancel();
        _startTimeouts = 0;
        _fallback = null;
        _speaking.value = true;
        lipSync.started(latency: latency);
      case SpeechAudioLevels(:final t0, :final hop, :final values):
        lipSync.addLevels(t0, hop, values);
      case SpeechAudioMarker(:final charStart, :final t):
        lipSync.addMarker(charStart, t);
      case SpeechAudioSynthesized():
        lipSync.audioComplete();
      case SpeechAudioDone():
        // Also after an interruption, a lost route, an engine reset or
        // backgrounding.
        _audioWatchdog?.cancel();
        _fallback = null;
        _speaking.value = false;
        lipSync.end();
      case SpeechAudioError(:final started):
        _audioFailure(replay: !started);
    }
  }

  /// Mouth timing for the talking avatar (lib/avatar/): fed from the
  /// synthesizer's start, word-range and completion callbacks.
  @override
  final LipSyncDriver lipSync = LipSyncDriver();

  final FlutterTts _tts;
  final List<Map<String, String>> _voices;
  final _speaking = ValueNotifier<bool>(false);
  final Map<String, Map<String, String>?> _chosen = {};

  /// Bumped by every [speak] and [stop]: a speak whose awaits are overtaken
  /// by a stop (or a newer speak) does not go on to start the audio.
  int _generation = 0;

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
      final service = DeviceVoiceService._(
          tts, voices, defaultTargetPlatform == TargetPlatform.iOS ? ChannelSpeechAudioBackend() : null);
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
      _chosen.putIfAbsent('${coach.id}/${language.name}', () => pickVoiceDistinct(_voices, coach, language));

  /// [pickVoice], but a coach speaking the other language avoids the voice
  /// of that language's own same-gender coach when the device has another
  /// fitting voice (Ava answering in Spanish does not borrow Sofía's voice).
  /// With a single voice per language and gender they share it; pitch and
  /// rate still tell them apart.
  @visibleForTesting
  static Map<String, String>? pickVoiceDistinct(List<Map<String, String>> voices, Coach coach, CoachLanguage language) {
    if (language == coach.language) return pickVoice(voices, coach, language: language);
    final natives = Coaches.forLanguage(language).where((c) => c.gender == coach.gender);
    final taken = natives.isEmpty ? null : pickVoice(voices, natives.first, language: language);
    String id(Map<String, String> v) => v['identifier'] ?? '${v['name']}|${v['locale']}';
    return pickVoice(voices, coach, language: language, avoid: {if (taken != null) id(taken)});
  }

  /// The best installed voice for [coach] among [voices] (flutter_tts
  /// `getVoices` maps: name, locale, and on iOS also quality, gender and
  /// identifier). Order of preference:
  ///  1. a voice of the coach's gender (from the metadata, or else a known
  ///     voice name), trying the coach's locales in order (en-US; es-MX,
  ///     es-US, es-ES); within a locale, Premium > Enhanced > default
  ///     quality, then known names;
  ///  2. any voice in those locales not known to be the other gender;
  ///  3. any voice in those locales (pitch then keeps the coaches apart).
  /// Null when no voice matches the language (the default voice is used).
  /// [language] (default: the coach's own) is the language of the text: a
  /// coach answering in the other language gets a same-gender voice of it.
  @visibleForTesting
  static Map<String, String>? pickVoice(List<Map<String, String>> voices, Coach coach,
      {CoachLanguage? language, Set<String> avoid = const {}}) {
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

    // Premium and Enhanced voices (free downloads in iOS Settings) sound far
    // more natural, so quality comes first, then the coach's known names.
    int score(Map<String, String> v) {
      final rank = nameRank(v, profile.preferredNames);
      return quality(v) * 1000 + (rank >= 0 ? 100 - rank : 0);
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

    bool free(Map<String, String> v) => !avoid.contains(v['identifier'] ?? '${v['name']}|${v['locale']}');
    return best((v) => genderMatch(v) == true && free(v)) ??
        best((v) => genderMatch(v) == true) ??
        best((v) => genderMatch(v) == null && free(v)) ??
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
    final gen = ++_generation;
    await _tts.stop();
    if (_audioPathOn) await _stopAudio();
    if (!_audioPathOn) await _prepareAudioSession();
    if (gen != _generation) return;
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
    if (gen != _generation) return;
    lipSync.begin(clean, language, rate: profile.rate);
    Future<void> viaTts() async {
      if (gen != _generation) return;
      await _prepareAudioSession();
      if (gen != _generation) return;
      await _tts.speak(clean);
    }

    if (_audioPathOn) {
      _audioGeneration = gen;
      _fallback = viaTts;
      // Nothing heard within the timeout (a silent failure): fall back.
      _audioWatchdog?.cancel();
      _audioWatchdog = Timer(audioStartTimeout, () {
        if (_audioGeneration == _generation && _fallback != null) _audioFailure(replay: true, timeout: true);
      });
      try {
        await _audio!.speak(
          text: clean,
          voice: voice?['identifier'],
          language: voice?['locale'] ?? language.locale,
          rate: profile.rate,
          pitch: profile.pitch,
        );
        return;
      } catch (_) {
        // No native channel (MissingPluginException) or it refused: use
        // flutter_tts from now on.
        _audioWatchdog?.cancel();
        _audioFailed = true;
        _fallback = null;
      }
    }
    await viaTts();
  }

  /// The native path failed: stop it, clear the speaking state, and (when
  /// nothing was heard yet) speak the same reply through flutter_tts. After
  /// an error the native path stays off for the session; after a start
  /// timeout only this reply falls back, unless it happens twice in a row.
  void _audioFailure({required bool replay, bool timeout = false}) {
    _audioWatchdog?.cancel();
    // Late events of this attempt (a "start" after the timeout) are ignored.
    _audioGeneration = -1;
    if (timeout) {
      _startTimeouts++;
      if (_startTimeouts >= maxStartTimeouts) _audioFailed = true;
    } else {
      _audioFailed = true;
    }
    _speaking.value = false;
    lipSync.end();
    final fallback = _fallback;
    _fallback = null;
    if (replay && fallback != null) {
      unawaited(_audio?.stop().catchError((Object _) {}));
      fallback();
    }
  }

  Future<void> _stopAudio() async {
    try {
      await _audio?.stop();
    } catch (_) {
      _audioFailed = true;
    }
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
    _generation++;
    _fallback = null;
    _audioWatchdog?.cancel();
    if (_audioPathOn) await _stopAudio();
    await _tts.stop();
    _speaking.value = false;
    lipSync.end();
  }
}
