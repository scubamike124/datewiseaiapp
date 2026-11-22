import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

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

  /// Starts listening in [localeId]; [onWords] gets the running transcript.
  /// [onUnsupported] is called if recognition for the language fails later.
  Future<SpeechStart> start({
    required String localeId,
    required void Function(String words) onWords,
    void Function()? onUnsupported,
  });

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
  DeviceSpeechService._();

  final SpeechToText _stt = SpeechToText();
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
    _denied = !_ready;
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
    required void Function(String words) onWords,
    void Function()? onUnsupported,
  }) async {
    if (!await ensureReady()) return SpeechStart.denied;
    _words = '';
    _onUnsupported = onUnsupported;
    try {
      await _stt.listen(
        onResult: (r) {
          _words = r.recognizedWords;
          onWords(_words);
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId.replaceAll('-', '_'),
          partialResults: true,
          onDevice: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 6),
        ),
      );
    } on ListenFailedException {
      return SpeechStart.unsupported;
    } on PlatformException {
      return SpeechStart.unsupported;
    } catch (_) {
      return SpeechStart.unsupported;
    }
    return SpeechStart.started;
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
    _onUnsupported = null;
    _words = '';
    try {
      if (_stt.isListening) await _stt.cancel();
    } catch (_) {}
  }
}
