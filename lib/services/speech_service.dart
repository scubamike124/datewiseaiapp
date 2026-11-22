import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Hold-to-talk speech recognition, on the device (speech_to_text, BSD-3).
abstract class SpeechService {
  /// False on web, in tests, or when the user denied microphone or speech
  /// permission: the chat then shows text input only.
  bool get available;

  /// Asks for permission the first time and reports whether listening works.
  Future<bool> ensureReady();

  /// Starts listening in [localeId]; [onWords] gets the running transcript.
  Future<void> start({required String localeId, required void Function(String words) onWords});

  /// Stops listening and returns the final transcript.
  Future<String> stop();
}

class NoSpeechService implements SpeechService {
  @override
  bool get available => false;
  @override
  Future<bool> ensureReady() async => false;
  @override
  Future<void> start({required String localeId, required void Function(String words) onWords}) async {}
  @override
  Future<String> stop() async => '';
}

class DeviceSpeechService implements SpeechService {
  DeviceSpeechService._();

  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  bool _denied = false;
  String _words = '';

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
  Future<bool> ensureReady() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize();
    } catch (_) {
      _ready = false;
    }
    _denied = !_ready;
    return _ready;
  }

  @override
  Future<void> start({required String localeId, required void Function(String words) onWords}) async {
    if (!await ensureReady()) return;
    _words = '';
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
  }

  @override
  Future<String> stop() async {
    if (_stt.isListening) {
      await _stt.stop();
      // Give the recogniser a moment to deliver its final result.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    return _words.trim();
  }
}
