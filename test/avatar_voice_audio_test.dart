// DeviceVoiceService with a fake flutter_tts channel and a fake native
// audio path: the speak() generation token, the audio path feeding the
// avatar's jaw, and the automatic fallback to flutter_tts.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:datewise_ai/avatar/speech_audio.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/services/voice_service.dart';

class FakeAudio implements SpeechAudioBackend {
  final controller = StreamController<SpeechAudioEvent>.broadcast(sync: true);
  final spoken = <Map<String, Object?>>[];
  Object? throwOnSpeak;
  int stops = 0;

  @override
  Stream<SpeechAudioEvent> get events => controller.stream;

  @override
  Future<void> speak({required String text, String? voice, required String language, required double rate, required double pitch}) async {
    if (throwOnSpeak != null) throw throwOnSpeak!;
    spoken.add({'text': text, 'voice': voice, 'language': language, 'rate': rate, 'pitch': pitch});
  }

  @override
  Future<void> stop() async => stops++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  late List<String> calls;
  Completer<void>? holdStop;

  setUp(() {
    calls = [];
    holdStop = null;
    DeviceVoiceService.useAudioPath = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'stop' && holdStop != null) await holdStop!.future;
      return 1;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  final voices = [
    {'name': 'Ava', 'locale': 'en-US', 'gender': 'female', 'quality': 'enhanced', 'identifier': 'com.apple.voice.enhanced.en-US.Ava'},
  ];

  test('speak() generation token: a stop that lands between awaits is not undone', () async {
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices);
    holdStop = Completer<void>();
    final speaking = s.speak('Hello there, this is Ava.', Coaches.ava);
    await Future<void>.delayed(Duration.zero);
    final stopping = s.stop();
    holdStop!.complete();
    await speaking;
    await stopping;
    expect(calls.where((c) => c == 'speak'), isEmpty, reason: 'the stopped utterance must not start');
    // A later speak goes through.
    await s.speak('Second try.', Coaches.ava);
    expect(calls.where((c) => c == 'speak'), hasLength(1));
  });

  test('audio path: native speech with the chosen voice; levels drive the jaw; done ends it', () async {
    final audio = FakeAudio();
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices, audio: audio);
    await s.speak('Hi, I am Ava.', Coaches.ava);
    expect(audio.spoken.single['voice'], 'com.apple.voice.enhanced.en-US.Ava');
    expect(audio.spoken.single['rate'], CoachVoiceProfile.ava.rate);
    expect(calls.where((c) => c == 'speak'), isEmpty, reason: 'flutter_tts not used');
    audio.controller.add(const SpeechAudioLevels(0, 0.01, [0.0, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]));
    audio.controller.add(const SpeechAudioStarted());
    expect(s.speaking.value, isTrue);
    expect(s.lipSync.hasAudio, isTrue);
    expect(s.lipSync.active, isTrue);
    audio.controller.add(const SpeechAudioDone());
    expect(s.speaking.value, isFalse);
    expect(s.lipSync.active, isFalse);
    await s.dispose();
  });

  test('audio path error before playback: falls back to flutter_tts for this and later replies', () async {
    final audio = FakeAudio();
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices, audio: audio);
    await s.speak('Hi, I am Ava.', Coaches.ava);
    audio.controller.add(const SpeechAudioError('engine failed'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c == 'speak'), hasLength(1), reason: 'same reply through flutter_tts');
    await s.speak('Next reply.', Coaches.ava);
    expect(audio.spoken, hasLength(1), reason: 'the native path stays off after a failure');
    expect(calls.where((c) => c == 'speak'), hasLength(2));
    await s.dispose();
  });

  test('no native channel (MissingPluginException): flutter_tts right away', () async {
    final audio = FakeAudio()..throwOnSpeak = MissingPluginException();
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices, audio: audio);
    await s.speak('Hi.', Coaches.ava);
    expect(calls.where((c) => c == 'speak'), hasLength(1));
    await s.dispose();
  });

  test('the runtime option turns the audio path off', () async {
    DeviceVoiceService.useAudioPath = false;
    final audio = FakeAudio();
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices, audio: audio);
    await s.speak('Hi.', Coaches.ava);
    expect(audio.spoken, isEmpty);
    expect(calls.where((c) => c == 'speak'), hasLength(1));
    await s.dispose();
  });

  test('events of a stopped utterance are ignored', () async {
    final audio = FakeAudio();
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices, audio: audio);
    await s.speak('Hi, I am Ava.', Coaches.ava);
    await s.stop();
    audio.controller.add(const SpeechAudioStarted());
    expect(s.speaking.value, isFalse);
    expect(audio.stops, greaterThan(0));
    await s.dispose();
  });

  test('no "start" within the timeout (a silent failure): the reply is spoken through flutter_tts', () async {
    DeviceVoiceService.audioStartTimeout = const Duration(milliseconds: 50);
    addTearDown(() => DeviceVoiceService.audioStartTimeout = const Duration(seconds: 3));
    final audio = FakeAudio();
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices, audio: audio);
    await s.speak('Hi, I am Ava.', Coaches.ava);
    expect(calls.where((c) => c == 'speak'), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(calls.where((c) => c == 'speak'), hasLength(1), reason: 'watchdog fell back');
    expect(audio.stops, greaterThan(0), reason: 'the native attempt is stopped');
    // A late "start" from the abandoned attempt changes nothing.
    audio.controller.add(const SpeechAudioStarted());
    expect(s.speaking.value, isFalse);
    expect(s.lipSync.hasAudio, isFalse);
    // One timeout does not turn the native path off (a cold voice can be slow)...
    await s.speak('Second reply.', Coaches.ava);
    expect(audio.spoken, hasLength(2));
    // ...but a second one in a row does.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await s.speak('Third reply.', Coaches.ava);
    expect(audio.spoken, hasLength(2), reason: 'off after two consecutive timeouts');
    await s.dispose();
  });

  test('a timeout followed by a successful start resets the count', () async {
    DeviceVoiceService.audioStartTimeout = const Duration(milliseconds: 50);
    addTearDown(() => DeviceVoiceService.audioStartTimeout = const Duration(seconds: 3));
    final audio = FakeAudio();
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices, audio: audio);
    await s.speak('One.', Coaches.ava);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await s.speak('Two.', Coaches.ava);
    audio.controller.add(const SpeechAudioStarted());
    audio.controller.add(const SpeechAudioDone());
    await s.speak('Three.', Coaches.ava);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await s.speak('Four.', Coaches.ava);
    expect(audio.spoken, hasLength(4), reason: 'never two timeouts in a row');
    await s.dispose();
  });

  test('dispose cancels a pending watchdog', () async {
    DeviceVoiceService.audioStartTimeout = const Duration(milliseconds: 50);
    addTearDown(() => DeviceVoiceService.audioStartTimeout = const Duration(seconds: 3));
    final audio = FakeAudio();
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices, audio: audio);
    await s.speak('Hi.', Coaches.ava);
    await s.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(calls.where((c) => c == 'speak'), isEmpty, reason: 'no fallback after dispose');
  });

  test('the watchdog does not fire once playback started', () async {
    DeviceVoiceService.audioStartTimeout = const Duration(milliseconds: 50);
    addTearDown(() => DeviceVoiceService.audioStartTimeout = const Duration(seconds: 3));
    final audio = FakeAudio();
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices, audio: audio);
    await s.speak('Hi, I am Ava.', Coaches.ava);
    audio.controller.add(const SpeechAudioStarted(latency: 0.2));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(calls.where((c) => c == 'speak'), isEmpty);
    expect(s.speaking.value, isTrue);
    await s.dispose();
  });

  test('native "no audio rendered" (error, started=false) falls back to flutter_tts', () async {
    final audio = FakeAudio();
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices, audio: audio);
    await s.speak('Hi.', Coaches.ava);
    audio.controller.add(SpeechAudioEvent.parse({'e': 'error', 'message': 'no audio rendered', 'started': false})!);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c == 'speak'), hasLength(1));
    await s.dispose();
  });

  test('an interruption mid-utterance ends it: speaking cleared, no replay', () async {
    final audio = FakeAudio();
    final s = DeviceVoiceService.forTesting(FlutterTts(), voices, audio: audio);
    await s.speak('Hi, I am Ava.', Coaches.ava);
    audio.controller.add(const SpeechAudioStarted());
    expect(s.speaking.value, isTrue);
    audio.controller.add(SpeechAudioEvent.parse({'e': 'done', 'interrupted': 'interruption'})!);
    expect(s.speaking.value, isFalse);
    expect(s.lipSync.active, isFalse);
    // Interrupted before anything was heard: also "done": no replay, and the
    // native path stays on for the next reply.
    await s.speak('Second.', Coaches.ava);
    audio.controller.add(SpeechAudioEvent.parse({'e': 'done', 'interrupted': 'route'})!);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c == 'speak'), isEmpty);
    expect(s.speaking.value, isFalse);
    await s.speak('Third.', Coaches.ava);
    expect(audio.spoken, hasLength(3));
    await s.dispose();
  });

  test('the native path is off unless the build turns it on (DW_AVATAR_AUDIO_PATH)', () {
    expect(const bool.fromEnvironment('DW_AVATAR_AUDIO_PATH'), isFalse);
  });
}
