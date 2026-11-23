import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

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

  /// Asks for permission the first time and reports whether listening works.
  Future<bool> ensureReady();

  /// After a denial: checks again (without prompting) whether the user has
  /// since allowed access in Settings, so voice comes back. Call on resume.
  Future<void> recheckPermission();

  /// Starts listening in [localeId], or the first of [fallbackLocales] the
  /// device can recognize when it cannot; [onWords] gets the running
  /// transcript. [onUnsupported] is called if recognition fails later.
  Future<SpeechStart> start({
    required String localeId,
    List<String> fallbackLocales = const [],
    required void Function(String words) onWords,
    void Function()? onUnsupported,
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
  Future<bool> ensureReady() async => false;
  @override
  Future<void> recheckPermission() async {}
  @override
  Future<SpeechStart> start({
    required String localeId,
    List<String> fallbackLocales = const [],
    required void Function(String words) onWords,
    void Function()? onUnsupported,
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

  /// Locale ids the recognizer supports on this device (read once).
  List<String>? _locales;

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
          if (_isUnsupported(e.errorMsg)) _onUnsupported?.call();
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
  }) async {
    if (!await ensureReady()) return _denied ? SpeechStart.denied : SpeechStart.unsupported;
    _words = '';
    _onUnsupported = onUnsupported;
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
  /// while it still holds the microphone. Cancelling an idle recognizer is
  /// harmless.
  Future<void> _cancelRecognizer() async {
    _onUnsupported = null;
    try {
      await _stt.cancel();
    } catch (_) {}
  }

  @override
  Future<String> stop() async {
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
