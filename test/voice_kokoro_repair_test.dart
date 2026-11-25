// The Kokoro speech path through DeviceVoiceService: the voice name sent per coach, the start timeout, the https check,
// dispose, and the speed mapping. A fake flutter_tts channel and a fake clip player; no device or server.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:datewise_ai/avatar/kokoro_audio_backend.dart';
import 'package:datewise_ai/avatar/speech_audio.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/services/voice_service.dart';

class _FakePlayer implements KokoroClipPlayer {
  final _playing = StreamController<bool>.broadcast();
  int plays = 0;
  int stops = 0;

  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Future<void> load(Uri audioUrl) async {}
  @override
  Future<void> play() async => plays++;
  @override
  Future<void> stop() async => stops++;
  void emit(bool v) => _playing.add(v);
}

final _base = Uri.parse('https://speech.example.test');
final _timeline = {
  'fps': 10,
  'sentences': [
    {'text': 'Hi.', 'start_s': 0.0, 'duration_s': 0.5, 'mouth': [0.0, 0.8]},
  ],
};

/// Records each request body and answers with a valid reply after [delay].
http.Client _renderer(List<Map<String, dynamic>> bodies, {Duration delay = Duration.zero}) => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      await Future<void>.delayed(delay);
      return http.Response(jsonEncode({'timeline': _timeline, 'audio_url': '/clips/a.wav'}), 200,
          headers: {'content-type': 'application/json'});
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  late List<String> calls;

  setUp(() {
    calls = [];
    DeviceVoiceService.useAudioPath = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return 1;
    });
  });

  tearDown(() {
    DeviceVoiceService.useAudioPath = false;
    DeviceVoiceService.kokoroStartTimeout = const Duration(seconds: 20);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  final deviceVoices = [
    {'name': 'Ava', 'locale': 'en-US', 'gender': 'female', 'quality': 'enhanced', 'identifier': 'com.apple.voice.enhanced.en-US.Ava'},
    {'name': 'Paulina', 'locale': 'es-MX', 'gender': 'female', 'quality': 'enhanced', 'identifier': 'com.apple.voice.enhanced.es-MX.Paulina'},
  ];

  test('the Kokoro request carries the coach Kokoro voice, chosen through DeviceVoiceService', () async {
    final bodies = <Map<String, dynamic>>[];
    final player = _FakePlayer();
    final backend = KokoroSpeechAudioBackend(baseUrl: _base, player: player, client: _renderer(bodies));
    final s = DeviceVoiceService.forTesting(FlutterTts(), deviceVoices, audio: backend);

    const en = 'Hi, I am glad you asked.';
    const es = 'Hola, me alegra mucho que me hayas escrito hoy.';
    await s.speak(en, Coaches.ava);
    expect(bodies.last['voice'], 'af_bella');
    expect(bodies.last['lang'], 'en-us');
    await s.speak(en, Coaches.ethan);
    expect(bodies.last['voice'], 'am_michael');
    await s.speak(es, Coaches.sofia);
    expect(bodies.last['voice'], 'ef_dora');
    expect(bodies.last['lang'], 'es');
    await s.speak(es, Coaches.diego);
    expect(bodies.last['voice'], 'em_alex');
    // Ava answering in Spanish uses the Spanish Kokoro voice of her gender, matching the language of the text.
    await s.speak(es, Coaches.ava);
    expect(bodies.last['voice'], 'ef_dora');
    expect(calls.where((c) => c == 'speak'), isEmpty, reason: 'the Kokoro path is used, not flutter_tts');
    await s.stop();
  });

  test('the Kokoro request carries the speed for the coach rate', () async {
    final bodies = <Map<String, dynamic>>[];
    final backend = KokoroSpeechAudioBackend(baseUrl: _base, player: _FakePlayer(), client: _renderer(bodies));
    final s = DeviceVoiceService.forTesting(FlutterTts(), deviceVoices, audio: backend);
    await s.speak('Hi, I am glad you asked.', Coaches.ethan);
    expect(bodies.last['speed'], closeTo(KokoroSpeechAudioBackend.speedFor(CoachVoiceProfile.ethan.rate), 1e-9));
    await s.stop();
  });

  test('a render slower than the old 3 s timeout that still plays does not fall back to flutter_tts', () async {
    expect(DeviceVoiceService.kokoroStartTimeout, greaterThan(DeviceVoiceService.audioStartTimeout));
    final bodies = <Map<String, dynamic>>[];
    final player = _FakePlayer();
    final backend = KokoroSpeechAudioBackend(
        baseUrl: _base, player: player, client: _renderer(bodies, delay: const Duration(milliseconds: 3500)));
    final s = DeviceVoiceService.forTesting(FlutterTts(), deviceVoices, audio: backend);
    await s.speak('Hi, I am glad you asked.', Coaches.ava);
    expect(calls.where((c) => c == 'speak'), isEmpty, reason: 'the slow render must not start the flutter_tts fallback');
    expect(player.plays, 1, reason: 'the clip plays after the slow render');
    player.emit(true);
    await Future<void>.delayed(Duration.zero);
    expect(s.speaking.value, isTrue);
    await s.stop();
  });

  test('a render that never answers falls back after the Kokoro timeout', () async {
    DeviceVoiceService.kokoroStartTimeout = const Duration(milliseconds: 100);
    final never = Completer<http.Response>();
    final client = MockClient((_) => never.future);
    final backend = KokoroSpeechAudioBackend(baseUrl: _base, player: _FakePlayer(), client: client);
    final s = DeviceVoiceService.forTesting(FlutterTts(), deviceVoices, audio: backend);
    unawaited(s.speak('Hi, I am glad you asked.', Coaches.ava));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(calls.where((c) => c == 'speak'), hasLength(1), reason: 'same reply through flutter_tts');
    await s.stop();
    // Completes the hung request so no pending work is left behind.
    never.complete(http.Response('{}', 500));
    await Future<void>.delayed(Duration.zero);
  });

  test('dispose stops the Kokoro backend: the player stops and its event stream closes', () async {
    final player = _FakePlayer();
    final backend = KokoroSpeechAudioBackend(baseUrl: _base, player: player, client: _renderer([]));
    final s = DeviceVoiceService.forTesting(FlutterTts(), deviceVoices, audio: backend);
    var closed = false;
    backend.events.listen(null, onDone: () => closed = true);
    await s.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(player.stops, greaterThanOrEqualTo(1));
    expect(closed, isTrue, reason: 'DeviceVoiceService.dispose must call KokoroSpeechAudioBackend.dispose');
  });

  group('DW_KOKORO_SPEECH_URL', () {
    test('a valid https URL selects the Kokoro backend', () {
      expect(DeviceVoiceService.audioBackendFor('https://speech.example.test'), isA<KokoroSpeechAudioBackend>());
    });

    test('a non-https, malformed or empty URL falls back to the native channel, it does not disable voice', () {
      for (final raw in ['http://speech.example.test', 'not a url', 'https://', 'ftp://speech.example.test', '']) {
        expect(DeviceVoiceService.audioBackendFor(raw), isA<ChannelSpeechAudioBackend>(), reason: raw);
      }
      expect(DeviceVoiceService.kokoroBaseUrl('http://speech.example.test'), isNull);
    });
  });

  group('speed mapping', () {
    test('rate 0.5 is the Kokoro speed 0.95 (the assumed pace)', () {
      expect(KokoroSpeechAudioBackend.speedFor(0.5), closeTo(0.95, 1e-9));
    });

    test('every coach rate maps to 0.83-0.87 and a faster coach rate gives a higher speed', () {
      final coaches = [Coaches.ava, Coaches.ethan, Coaches.sofia, Coaches.diego];
      final rates = [for (final c in coaches) CoachVoiceProfile.of(c).rate];
      for (final r in rates) {
        expect(r, inInclusiveRange(0.44, 0.455), reason: 'coach rate');
        expect(KokoroSpeechAudioBackend.speedFor(r), inInclusiveRange(0.83, 0.87));
      }
      expect(KokoroSpeechAudioBackend.speedFor(0.44), lessThan(KokoroSpeechAudioBackend.speedFor(0.455)));
    });
  });
}
