import 'dart:async';

import 'package:flutter/foundation.dart';

import '../avatar/kokoro_audio_backend.dart';
import '../avatar/kokoro_video_clip.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../avatar/lip_sync.dart';
import '../avatar/speech_audio.dart';
import '../models/coach.dart';
import 'reply_language.dart';
import 'speech_text.dart';

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
    required this.kokoroVoice,
  });

  final List<String> locales;
  final List<String> preferredNames;

  /// Names of known voices of the other gender, avoided when the voice
  /// metadata has no gender.
  final List<String> otherGenderNames;
  final double pitch;
  final double rate;

  /// The server-rendered Kokoro voice of this coach (the Kokoro path sends
  /// this name, never an Apple voice identifier). Spanish coaches use the
  /// Spanish Kokoro voices, so the phonemes match the Spanish text.
  final String kokoroVoice;

  static const _enFemale = ['Ava', 'Samantha', 'Allison', 'Susan', 'Zoe', 'Nicky', 'Joelle', 'Noelle'];
  static const _enMale = ['Evan', 'Nathan', 'Alex', 'Tom', 'Aaron', 'Daniel', 'Fred', 'Reed'];
  static const _esFemale = ['Paulina', 'Mónica', 'Monica', 'Marisol', 'Angélica', 'Angelica', 'Isabela', 'Soledad'];
  static const _esMale = ['Juan', 'Jorge', 'Diego', 'Carlos', 'Eddy', 'Reed'];

  static const _enLocales = ['en-US', 'en-GB', 'en-AU', 'en'];
  /// Mexican Spanish first (the owner's choice), then US and Latin-American
  /// Spanish; Spain's es-ES only as a last resort.
  static const _esLocales = ['es-MX', 'es-US', 'es-419', 'es-ES', 'es'];

  // Rates (flutter_tts: iOS AVSpeechUtterance.rate, Android rate*2; 0.5 is the
  // platform default of about 170 words a minute, see SpeechPace). The owner
  // found build 203 (Ava 0.54, about 185 wpm) much too fast, so every coach
  // now sits at 140-165 wpm of speech, plus 380 ms between sentences:
  //   Ava 0.45 (~158 wpm en), Ethan 0.44 (~155), Sofia 0.455 (~143 es),
  //   Diego 0.445 (~140.5 es; Spanish words are longer, so the same rate
  //   gives fewer words a minute).
  //
  // Pitch: system voices turn synthetic when pitch is pushed (AVSpeech
  // sounds artificial beyond roughly +-1.5 semitones). Ava keeps her own
  // voice unshifted (1.0). The others only lean a little so a device with a
  // single voice per language still tells them apart: Ethan 0.97 (-0.5
  // semitone), Sofia 1.05 (+0.8), Diego 0.92 (-1.4), instead of the old
  // +-2 semitone shifts.
  static const ava = CoachVoiceProfile(
      locales: _enLocales,
      preferredNames: _enFemale,
      otherGenderNames: _enMale,
      pitch: 1.0,
      rate: 0.45,
      kokoroVoice: 'af_bella');
  static const ethan = CoachVoiceProfile(
      locales: _enLocales,
      preferredNames: _enMale,
      otherGenderNames: _enFemale,
      pitch: 0.97,
      rate: 0.44,
      kokoroVoice: 'am_michael');
  static const sofia = CoachVoiceProfile(
      locales: _esLocales,
      preferredNames: _esFemale,
      otherGenderNames: _esMale,
      pitch: 1.05,
      rate: 0.455,
      kokoroVoice: 'ef_dora');
  static const diego = CoachVoiceProfile(
      locales: _esLocales,
      preferredNames: _esMale,
      otherGenderNames: _esFemale,
      pitch: 0.92,
      rate: 0.445,
      kokoroVoice: 'em_alex');

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
  /// Base URL of the server-rendered Kokoro speech service (lib/avatar/kokoro_audio_backend.dart). Empty (the default): the
  /// native audio path or the device voice is used. Set with --dart-define=DW_KOKORO_SPEECH_URL=https://... on iOS only.
  static const String kokoroSpeechUrl = String.fromEnvironment('DW_KOKORO_SPEECH_URL');

  /// How long to wait for the native path to start playing before giving
  /// up and speaking through flutter_tts instead.
  static Duration audioStartTimeout = const Duration(seconds: 3);

  /// The Kokoro path renders the whole reply on the server before it plays, so its start
  /// timeout is much longer than [audioStartTimeout]. It also bounds a request that never answers.
  static Duration kokoroStartTimeout = const Duration(seconds: 20);
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
    final audio = _audio;
    if (audio is KokoroSpeechAudioBackend) await audio.dispose();
  }

  void _wireTts() {
    final lip = lipSync;
    _tts.setStartHandler(() {
      if (!_ttsCurrent) return; // a replaced utterance
      _speaking.value = true;
      lip.started();
    });
    // AVSpeechSynthesizer reports each word as it starts (character range
    // in the spoken text); the avatar's mouth follows it.
    _tts.setProgressHandler((_, start, end, _) {
      if (_ttsCurrent) lip.word(start, end);
    });
    _tts.setCompletionHandler(() {
      if (!_ttsCurrent) return;
      _chunkEnded(ok: true);
    });
    _tts.setCancelHandler(() {
      if (!_ttsCurrent) return;
      _chunkEnded(ok: false);
    });
    _tts.setErrorHandler((_) {
      _chunkEnded(ok: false);
    });
  }

  // -- sentence by sentence ---------------------------------------------------

  /// Pause between chunks; replaced in tests to record or skip the waits.
  @visibleForTesting
  static Future<void> Function(Duration) pauseFor = (d) => Future<void>.delayed(d);

  Completer<bool>? _chunkDone;
  bool _lastChunk = true;

  /// The current chunk finished ([ok]) or was cut short. The lips rest; the
  /// speaking state stays on between the chunks of one reply and goes off
  /// after the last one (or after any interruption).
  void _chunkEnded({required bool ok}) {
    lipSync.end();
    if (_lastChunk || !ok) _speaking.value = false;
    final c = _chunkDone;
    _chunkDone = null;
    if (c != null && !c.isCompleted) c.complete(ok);
  }

  /// Unblocks a sequencer waiting on a replaced or stopped utterance.
  void _releaseChunk() {
    final c = _chunkDone;
    _chunkDone = null;
    if (c != null && !c.isCompleted) c.complete(false);
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
      case SpeechAudioDone(:final interrupted):
        // Also after an interruption, a lost route, an engine reset or
        // backgrounding (then the rest of the reply is not spoken).
        _audioWatchdog?.cancel();
        _fallback = null;
        _chunkEnded(ok: !interrupted);
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

  /// The generation of the utterance flutter_tts is currently speaking; its
  /// callbacks are ignored once a newer utterance has started.
  int _ttsGeneration = -1;

  bool get _ttsCurrent => _ttsGeneration == _generation;

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
      final SpeechAudioBackend? audio = defaultTargetPlatform == TargetPlatform.iOS && DeviceVoiceService.useAudioPath
          ? audioBackendFor(DeviceVoiceService.kokoroSpeechUrl)
          : null;
      final service = DeviceVoiceService._(tts, voices, audio);
      return service;
    } catch (_) {
      return NoVoiceService();
    }
  }

  /// The https base URL of the Kokoro speech service, or null when [raw] is empty, not a URL, or not https with a host.
  @visibleForTesting
  static Uri? kokoroBaseUrl(String raw) {
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }

  /// The native speech-audio backend for [kokoroUrl]: the Kokoro service when it is a valid https URL, else the
  /// platform channel. An invalid URL is logged and does not disable the audio path.
  @visibleForTesting
  static SpeechAudioBackend audioBackendFor(String kokoroUrl) {
    if (kokoroUrl.isEmpty) return ChannelSpeechAudioBackend();
    final base = kokoroBaseUrl(kokoroUrl);
    if (base == null) {
      debugPrint('DW_KOKORO_SPEECH_URL is not a valid https URL; using the native audio path instead of Kokoro.');
      return ChannelSpeechAudioBackend();
    }
    return KokoroSpeechAudioBackend(baseUrl: base, player: VideoPlayerClipPlayer());
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

    String ident(Map<String, String> v) => '${v['identifier'] ?? ''} ${v['name'] ?? ''}'.toLowerCase();
    // Siri / neural voices > Premium > Enhanced > default > "compact" > the
    // old novelty voices (Fred, Albert, Bells...). The identifier is used
    // when the quality field is missing.
    int quality(Map<String, String> v) {
      final q = norm(v['quality']);
      final id = ident(v);
      if (id.contains('siri') || id.contains('neural')) return 5;
      if (q == 'premium' || id.contains('.premium.') || id.contains('(premium)')) return 4;
      if (q == 'enhanced' || id.contains('.enhanced.') || id.contains('(enhanced)')) return 3;
      if (id.contains('speech.synthesis.voice.')) return 0;
      if (id.contains('.compact.') || id.contains('(compact)')) return 1;
      return 2;
    }

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
    final stripped = SpeechText.stripMarkup(text);
    if (stripped.isEmpty) return;
    final gen = ++_generation;
    _releaseChunk();
    await _stopEngines();
    if (!_audioPathOn) await _prepareAudioSession();
    if (gen != _generation) return;
    // Coaches answer in the user's language, so the voice follows the
    // language of the text, not the coach's default.
    final language = ReplyLanguage.detect(stripped, fallback: coach.language);
    final clean = SpeechText.normalize(stripped, language);
    final chunks = SpeechText.chunks(clean);
    if (chunks.isEmpty) return;
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
    // The first sentence starts now; the rest follow with a pause between.
    // The Kokoro voice follows the language of the text, like the device voice does.
    final kokoroVoice = CoachVoiceProfile.forLanguage(coach, language).kokoroVoice;
    await _speakChunk(gen, chunks, 0, voice, language, profile, kokoroVoice);
    if (chunks.length > 1) unawaited(_continueChunks(gen, chunks, voice, language, profile, kokoroVoice));
  }

  Future<void> _continueChunks(int gen, List<SpeechChunk> chunks, Map<String, String>? voice, CoachLanguage language,
      CoachVoiceProfile profile, String kokoroVoice) async {
    for (var i = 0; i < chunks.length - 1; i++) {
      final completer = _chunkDone;
      final ok = completer == null ? false : await completer.future;
      if (!ok || gen != _generation) return;
      await pauseFor(chunks[i].pause);
      if (gen != _generation) return;
      await _speakChunk(gen, chunks, i + 1, voice, language, profile, kokoroVoice);
    }
  }

  /// Starts chunk [i] (returns once it has been handed to the synthesizer;
  /// its end arrives through [_chunkEnded]).
  Future<void> _speakChunk(int gen, List<SpeechChunk> chunks, int i, Map<String, String>? voice, CoachLanguage language,
      CoachVoiceProfile profile, String kokoroVoice) async {
    final text = chunks[i].text;
    _lastChunk = i == chunks.length - 1;
    _chunkDone = Completer<bool>();
    lipSync.begin(text, language, rate: profile.rate);
    Future<void> viaTts() async {
      if (gen != _generation) return;
      await _prepareAudioSession();
      if (gen != _generation) return;
      _ttsGeneration = gen;
      await _tts.speak(text);
    }

    if (_audioPathOn) {
      _audioGeneration = gen;
      _fallback = viaTts;
      // Nothing heard within the timeout (a silent failure): fall back. Kokoro renders the whole reply first, so it
      // gets the longer timeout; the native path sends the Apple voice identifier, Kokoro the Kokoro voice name.
      final audio = _audio!;
      final isKokoro = audio is KokoroSpeechAudioBackend;
      _audioWatchdog?.cancel();
      _audioWatchdog = Timer(isKokoro ? kokoroStartTimeout : audioStartTimeout, () {
        if (_audioGeneration == _generation && _fallback != null) _audioFailure(replay: true, timeout: true);
      });
      try {
        await audio.speak(
          text: text,
          voice: isKokoro ? kokoroVoice : voice?['identifier'],
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
      fallback(); // the chunk's end then arrives from flutter_tts
    } else {
      _releaseChunk(); // nothing more is spoken
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

  /// The longest a native stop may take. On an iPhone the speech engine can fail to report that it stopped; an
  /// unbounded wait left the send button, the talk button and the next reply waiting for ever.
  static const engineStopWait = Duration(milliseconds: 1200);

  /// Stops the native audio path and flutter_tts together (not one after the other, so one that hangs cannot keep the
  /// other speaking), each bounded by [engineStopWait]. Errors are ignored: a stop that fails has nothing left to stop.
  Future<void> _stopEngines() => Future.wait([
        if (_audioPathOn) _stopAudio(),
        Future<void>(() => _tts.stop()),
      ].map((f) => f.timeout(engineStopWait, onTimeout: () {}).catchError((_) {})));

  @override
  Future<void> stop() async {
    _generation++;
    _releaseChunk();
    _fallback = null;
    _audioWatchdog?.cancel();
    // The state is final before anything is awaited, so a stop that completes late cannot end a reply started since.
    _speaking.value = false;
    lipSync.end();
    await _stopEngines();
  }
}
