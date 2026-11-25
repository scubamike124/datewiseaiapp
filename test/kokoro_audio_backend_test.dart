import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:datewise_ai/avatar/kokoro_audio_backend.dart';
import 'package:datewise_ai/avatar/speech_audio.dart';

class _FakePlayer implements KokoroClipPlayer {
  final _playing = StreamController<bool>.broadcast();
  Uri? loaded;
  int plays = 0;
  int stops = 0;

  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Future<void> load(Uri audioUrl) async => loaded = audioUrl;
  @override
  Future<void> play() async => plays++;
  @override
  Future<void> stop() async => stops++;
  void emit(bool v) => _playing.add(v);
}

Map<String, Object?> _timeline() => {
      'fps': 10,
      'sentences': [
        {'text': 'Hi.', 'start_s': 0.0, 'duration_s': 0.5, 'mouth': [0.0, 0.8, 0.2, 0.0, 0.0]},
        {'text': 'Now.', 'start_s': 0.5, 'duration_s': 0.4, 'mouth': [0.1, 0.9, 0.0, 0.0]},
      ],
    };

http.Client _client({int status = 200, String? body}) => MockClient((request) async {
      expect(request.url.path, '/v1/speech');
      return http.Response(body ?? jsonEncode({'timeline': _timeline(), 'audio_url': '/clips/a.wav'}), status,
          headers: {'content-type': 'application/json'});
    });

Future<List<SpeechAudioEvent>> _collect(Stream<SpeechAudioEvent> events, Future<void> Function() body) async {
  final got = <SpeechAudioEvent>[];
  final sub = events.listen(got.add);
  await body();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await sub.cancel();
  return got;
}

void main() {
  final base = Uri.parse('https://speech.example.test');

  test('a reply sends measured loudness first, then synthesized, then started when the clip plays, then done', () async {
    final player = _FakePlayer();
    final backend = KokoroSpeechAudioBackend(baseUrl: base, player: player, client: _client());
    final events = await _collect(backend.events, () async {
      await backend.speak(text: 'Hi. Now.', language: 'en', rate: 0.5, pitch: 1, voice: 'af_bella');
      player.emit(true);
      player.emit(false);
    });
    expect(player.loaded, base.resolve('/clips/a.wav'));
    expect(player.plays, 1);
    expect(events[0], isA<SpeechAudioLevels>());
    expect((events[0] as SpeechAudioLevels).t0, 0.0);
    expect(events[1], isA<SpeechAudioLevels>());
    expect((events[1] as SpeechAudioLevels).t0, 0.5);
    expect(events[2], isA<SpeechAudioSynthesized>());
    expect(events[3], isA<SpeechAudioStarted>());
    expect(events[4], isA<SpeechAudioDone>());
    expect((events[4] as SpeechAudioDone).interrupted, isFalse);
    expect(events.whereType<SpeechAudioMarker>(), isEmpty, reason: 'estimated word times are never sent');
  });

  test('a bad status from the speech service is an error event, nothing is played', () async {
    final player = _FakePlayer();
    final backend = KokoroSpeechAudioBackend(baseUrl: base, player: player, client: _client(status: 500));
    final events = await _collect(backend.events, () => backend.speak(text: 'Hi.', language: 'en', rate: 0.5, pitch: 1));
    expect(events.single, isA<SpeechAudioError>());
    expect(player.plays, 0);
  });

  test('a reply that is not a timeline is refused as an error, nothing is played', () async {
    final player = _FakePlayer();
    final backend = KokoroSpeechAudioBackend(
        baseUrl: base, player: player, client: _client(body: jsonEncode({'timeline': 'nope', 'audio_url': '/a.wav'})));
    final events = await _collect(backend.events, () => backend.speak(text: 'Hi.', language: 'en', rate: 0.5, pitch: 1));
    expect(events.single, isA<SpeechAudioError>());
    expect(player.plays, 0);
  });

  test('stop ends the reply as interrupted', () async {
    final player = _FakePlayer();
    final backend = KokoroSpeechAudioBackend(baseUrl: base, player: player, client: _client());
    final events = await _collect(backend.events, () async {
      await backend.speak(text: 'Hi. Now.', language: 'en', rate: 0.5, pitch: 1);
      player.emit(true);
      await backend.stop();
    });
    expect(player.stops, 1);
    final done = events.whereType<SpeechAudioDone>().single;
    expect(done.interrupted, isTrue);
  });
  test('audio from another host is refused: the app never loads media the speech service did not name', () async {
    final player = _FakePlayer();
    final body = jsonEncode({'timeline': _timeline(), 'audio_url': 'https://attacker.example.test/x.wav'});
    final backend = KokoroSpeechAudioBackend(baseUrl: base, player: player, client: _client(body: body));
    final events = await _collect(backend.events, () => backend.speak(text: 'Hi. Now.', language: 'en', rate: 0.5, pitch: 1, voice: 'af_bella'));
    expect(player.loaded, isNull);
    expect(events.last, isA<SpeechAudioError>());
  });

  test('stopping before the reply arrives still reports the reply as interrupted', () async {
    final player = _FakePlayer();
    final backend = KokoroSpeechAudioBackend(baseUrl: base, player: player, client: _client());
    final events = await _collect(backend.events, () async {
      final pending = backend.speak(text: 'Hi. Now.', language: 'en', rate: 0.5, pitch: 1, voice: 'af_bella');
      await backend.stop();
      await pending;
    });
    expect(events.whereType<SpeechAudioDone>().map((e) => e.interrupted), contains(true));
    expect(player.plays, 0, reason: 'a stopped reply must not start playing');
  });
  test('dispose stops the player, a pending reply never plays, and nothing is emitted afterwards', () async {
    final player = _FakePlayer();
    final backend = KokoroSpeechAudioBackend(baseUrl: base, player: player, client: _client());
    final got = <SpeechAudioEvent>[];
    final sub = backend.events.listen(got.add);
    final pending = backend.speak(text: 'Hi. Now.', language: 'en', rate: 0.5, pitch: 1, voice: 'af_bella');
    await backend.dispose();
    await pending;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();
    expect(player.stops, greaterThanOrEqualTo(1), reason: 'dispose must stop the player');
    expect(player.plays, 0, reason: 'a reply pending at dispose must not start playing');
    expect(got.whereType<SpeechAudioStarted>(), isEmpty);
    expect(got.whereType<SpeechAudioDone>(), isEmpty);
  });
}
