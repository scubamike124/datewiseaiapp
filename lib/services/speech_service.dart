import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/coach.dart';

/// How a hold-to-talk start ended.
enum SpeechStart {
  /// Listening.
  started,

  /// No microphone or speech permission.
  denied,

  /// On-device recognition is not available for this language on this
  /// device (or the recognizer failed to start).
  unsupported,
}

/// Hold-to-talk speech recognition, on the device (speech_to_text, BSD-3).
abstract class SpeechService {
  /// False on web, in tests, or when the user denied microphone or speech
  /// permission: the chat then shows text input only.
  bool get available;

  /// True when voice is hidden because the user denied microphone or speech
  /// recognition permission (not because the device has no recognizer):
  /// the app then says so and offers [openSettings].
  bool get permissionDenied;

  /// Whether [openSettings] can open DateWise's page in the Settings app.
  bool get canOpenSettings;

  /// Opens DateWise's page in the Settings app (microphone and speech
  /// recognition switches), where a denial can be undone.
  Future<void> openSettings();

  /// Asks for permission the first time and reports whether listening works.
  Future<bool> ensureReady();

  /// After a denial: checks again (without prompting) whether the user has
  /// since allowed access in Settings, so voice comes back. Call on resume.
  Future<void> recheckPermission();

  /// Starts listening in [localeId], or the first of [fallbackLocales] the
  /// device can recognize when it cannot; [onWords] gets the running
  /// transcript. [onUnsupported] is called if recognition fails later
  /// because of the language. [onEnded] is called once if recognition ends
  /// by itself (silence timeout, no match, another recognizer error), with
  /// the transcript so far (empty when nothing was understood); never after
  /// [stop] or [cancel].
  Future<SpeechStart> start({
    required String localeId,
    List<String> fallbackLocales = const [],
    required void Function(String words) onWords,
    void Function()? onUnsupported,
    void Function(String words)? onEnded,
  });

  /// The recognition locales to try for [language], best first. A bare
  /// language code ("es") means any regional variant of it.
  static List<String> localesFor(CoachLanguage language) => switch (language) {
        CoachLanguage.es => const ['es-MX', 'es-US', 'es-ES', 'es'],
        CoachLanguage.en => const ['en-US', 'en-GB', 'en'],
      };

  /// The first of [wanted] among the device's [available] locale ids (either
  /// "es_MX" or "es-MX"), returned as the device spells it. When the device
  /// list is unknown (empty) or has none of them, the first wanted locale.
  static String pickLocale(List<String> available, List<String> wanted) {
    String norm(String s) => s.replaceAll('_', '-').toLowerCase();
    for (final w in wanted) {
      final want = norm(w);
      for (final a in available) {
        final n = norm(a);
        if (want.contains('-') ? n == want : (n == want || n.startsWith('$want-'))) return a;
      }
    }
    return wanted.first;
  }

  /// Stops listening and returns the final transcript.
  Future<String> stop();

  /// Stops listening and discards the transcript.
  Future<void> cancel();
}

class NoSpeechService implements SpeechService {
  @override
  bool get available => false;
  @override
  bool get permissionDenied => false;
  @override
  bool get canOpenSettings => false;
  @override
  Future<void> openSettings() async {}
  @override
  Future<bool> ensureReady() async => false;
  @override
  Future<void> recheckPermission() async {}
  @override
  Future<SpeechStart> start({
    required String localeId,
    List<String> fallbackLocales = const [],
    required void Function(String words) onWords,
    void Function()? onUnsupported,
    void Function(String words)? onEnded,
  }) async =>
      SpeechStart.denied;
  @override
  Future<String> stop() async => '';
  @override
  Future<void> cancel() async {}
}

class DeviceSpeechService implements SpeechService {
  DeviceSpeechService._() : _stt = SpeechToText();

  /// For tests: a service around a fake recognizer.
  @visibleForTesting
  DeviceSpeechService.withRecognizer(SpeechToText recognizer) : _stt = recognizer;

  final SpeechToText _stt;
  bool _ready = false;
  bool _denied = false;
  String _words = '';
  void Function()? _onUnsupported;
  void Function(String words)? _onEnded;

  /// True once the current session reported "listening": an end status
  /// before that belongs to an earlier session and is ignored.
  bool _sessionListening = false;

  static SpeechService create() {
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      return NoSpeechService();
    }
    return DeviceSpeechService._();
  }

  @override
  bool get available => !_denied;

  @override
  bool get permissionDenied => _denied;

  /// iOS's "app-settings:" URL opens the app's own page in Settings
  /// (url_launcher, already a dependency).
  @override
  bool get canOpenSettings => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<void> openSettings() async {
    if (!canOpenSettings) return;
    try {
      await launchUrl(Uri.parse('app-settings:'));
    } catch (_) {}
  }

  /// Locale ids the recognizer supports on this device (read once).
  List<String>? _locales;

  /// Recognizer errors that mean microphone or speech access is missing.
  /// speech_to_text's Android permission error code (and its iOS
  /// equivalents that name the permission explicitly); not any message that
  /// merely mentions the word.
  static bool _isPermissionError(String msg) {
    final m = msg.toLowerCase().trim();
    return m == 'error_permission' || m.startsWith('error_permission') || m.contains('permission denied') || m.contains('not authorized');
  }

  /// Recognizer errors that mean the language cannot be recognized here.
  static bool _isUnsupported(String msg) {
    final m = msg.toLowerCase();
    return m.contains('language') || m.contains('locale') || m.contains('device') || m.contains('unavailable');
  }

  @override
  Future<bool> ensureReady() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onError: (e) {
          if (_isPermissionError(e.errorMsg)) {
            // Android's "error_permission" (access revoked or never given):
            // a denial, not a normal end. Voice hides until a recheck.
            _denied = true;
            _endedBySelf();
          } else if (_isUnsupported(e.errorMsg)) {
            final cb = _onUnsupported;
            _onEnded = null;
            cb?.call();
          } else {
            // No match, speech timeout and the like: the session is over.
            _endedBySelf();
          }
        },
        onStatus: (status) {
          if (status == SpeechToText.listeningStatus) {
            _sessionListening = true;
          } else if (_sessionListening &&
              (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus)) {
            _endedBySelf();
          }
        },
      );
    } catch (_) {
      _ready = false;
    }
    if (_ready) {
      _denied = false;
    } else {
      // Not ready is not always a denial: the recognizer can be unavailable
      // (e.g. Siri & Dictation off). Only a missing permission hides voice.
      try {
        _denied = !(await _stt.hasPermission);
      } catch (_) {
        _denied = true;
      }
    }
    return _ready;
  }

  @override
  Future<void> recheckPermission() async {
    if (!_denied) return;
    try {
      // hasPermission only checks; it never shows the system prompt.
      if (await _stt.hasPermission) _denied = false;
    } catch (_) {}
  }

  @override
  Future<SpeechStart> start({
    required String localeId,
    List<String> fallbackLocales = const [],
    required void Function(String words) onWords,
    void Function()? onUnsupported,
    void Function(String words)? onEnded,
  }) async {
    if (!await ensureReady()) return _denied ? SpeechStart.denied : SpeechStart.unsupported;
    _words = '';
    _onUnsupported = onUnsupported;
    _onEnded = onEnded;
    _sessionListening = false;
    try {
      _locales ??= [for (final l in await _stt.locales()) l.localeId];
    } catch (_) {
      _locales = const [];
    }
    final locale = SpeechService.pickLocale(_locales!, [localeId, ...fallbackLocales]);
    try {
      await _stt.listen(
        onResult: (r) {
          _words = r.recognizedWords;
          onWords(_words);
        },
        listenOptions: SpeechListenOptions(
          localeId: locale.replaceAll('-', '_'),
          partialResults: true,
          onDevice: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 6),
        ),
      );
    } on ListenFailedException {
      await _cancelRecognizer();
      return SpeechStart.unsupported;
    } on PlatformException {
      await _cancelRecognizer();
      return SpeechStart.unsupported;
    } catch (_) {
      await _cancelRecognizer();
      return SpeechStart.unsupported;
    }
    return SpeechStart.started;
  }

  /// Cancels the recognizer whatever `isListening` says: a session that is
  /// still starting, or one that failed half-way, can report not listening
  /// while it still holds the microphone. Canceling an idle recognizer is
  /// harmless.
  Future<void> _cancelRecognizer() async {
    _onUnsupported = null;
    _onEnded = null;
    try {
      await _stt.cancel();
    } catch (_) {}
  }

  /// Recognition ended without [stop] or [cancel]: tells the session once.
  void _endedBySelf() {
    final cb = _onEnded;
    _onEnded = null;
    _onUnsupported = null;
    _sessionListening = false;
    cb?.call(_words.trim());
  }

  @override
  Future<String> stop() async {
    // Stopping on purpose is not an end "by itself".
    _onEnded = null;
    if (_stt.isListening) {
      await _stt.stop();
      // Give the recognizer a moment to deliver its final result.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    _onUnsupported = null;
    return _words.trim();
  }

  @override
  Future<void> cancel() async {
    _words = '';
    await _cancelRecognizer();
  }
}
