// DeviceSpeechService around a fake recognizer: cancel() and a failed start()
// always cancel the recognizer, even when it reports it is not listening (a
// session that is still starting, or failed half-way, can hold the microphone).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:datewise_ai/services/speech_service.dart';

/// A fake SpeechToText: answers only what DeviceSpeechService uses.
class FakeStt implements SpeechToText {
  FakeStt({this.listenError});

  /// Thrown by listen() when set.
  final Object? listenError;
  int cancelCalls = 0;
  int listenCalls = 0;

  @override
  dynamic noSuchMethod(Invocation i) {
    switch (i.memberName) {
      case #isListening:
        return false; // as the plugin reports while a session is starting
      case #hasPermission:
        return Future<bool>.value(true);
      case #initialize:
        return Future<bool>.value(true);
      case #locales:
        return Future<List<LocaleName>>.value([LocaleName('en_US', 'English')]);
      case #listen:
        listenCalls++;
        final e = listenError;
        return e == null ? Future<void>.value() : Future<void>.error(e);
      case #cancel:
        cancelCalls++;
        return Future<void>.value();
      case #stop:
        return Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

void main() {
  Future<SpeechStart> start(DeviceSpeechService s) => s.start(localeId: 'en-US', onWords: (_) {});

  test('cancel() cancels the recognizer even when it reports not listening', () async {
    final stt = FakeStt();
    final speech = DeviceSpeechService.withRecognizer(stt);
    expect(await start(speech), SpeechStart.started);
    await speech.cancel();
    expect(stt.cancelCalls, 1);
    // Idle: still harmless to call.
    await speech.cancel();
    expect(stt.cancelCalls, 2);
  });

  for (final (name, error) in [
    ('ListenFailedException', ListenFailedException('busy')),
    ('PlatformException', PlatformException(code: 'listenFailed')),
    ('any other error', StateError('boom')),
  ]) {
    test('a start() that fails with $name cancels the recognizer and reports unsupported', () async {
      final stt = FakeStt(listenError: error);
      final speech = DeviceSpeechService.withRecognizer(stt);
      expect(await start(speech), SpeechStart.unsupported);
      expect(stt.listenCalls, 1);
      expect(stt.cancelCalls, 1);
    });
  }
}
