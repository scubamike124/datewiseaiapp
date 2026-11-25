import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'kokoro_speech.dart';
import 'speech_audio.dart';

/// Plays one rendered clip. The app uses a video_player implementation; tests use a fake, so the event order is checked
/// without a device.
abstract class KokoroClipPlayer {
  /// Loads the clip at [audioUrl]. Throws if it cannot be loaded.
  Future<void> load(Uri audioUrl);

  /// Starts playback of the loaded clip.
  Future<void> play();

  /// Stops playback and releases the clip.
  Future<void> stop();

  /// Emits true when playback starts and false when it ends (finished or stopped).
  Stream<bool> get playing;
}

/// The speech-audio path for server-rendered Kokoro speech (tool/tts/kokoro_sentences.py).
///
/// It satisfies the same [SpeechAudioBackend] contract as the native path, so [DeviceVoiceService] and [LipSyncDriver] are
/// unchanged. Order of events for one reply: the measured loudness of every sentence (it arrives before playback), the
/// synthesized marker, then [SpeechAudioStarted] when the clip starts playing and [SpeechAudioDone] when it ends. Only
/// measured loudness is sent: word timings are estimates and are not sent (see kokoro_speech.dart).
///
/// Server contract (to be served by the rendering service; not built yet): POST `{baseUrl}/v1/speech` with JSON
/// `{"text": ..., "voice": ..., "lang": ..., "speed": ...}` returns JSON `{"timeline": <timeline.json>, "audio_url": <url>}`.
class KokoroSpeechAudioBackend implements SpeechAudioBackend {
  KokoroSpeechAudioBackend({required this.baseUrl, required KokoroClipPlayer player, http.Client? client})
      : _player = player,
        _client = client ?? http.Client();

  final Uri baseUrl;
  final KokoroClipPlayer _player;
  final http.Client _client;
  final _events = StreamController<SpeechAudioEvent>.broadcast();
  StreamSubscription<bool>? _playingSub;
  int _generation = 0;
  /// True from speak() until its reply ends, fails or is stopped; a stop before playback still reports interrupted.
  bool _busy = false;

  @override
  Stream<SpeechAudioEvent> get events => _events.stream;

  /// Renders [text] and plays it. A later [speak] or [stop] ends this one (its events are not sent).
  @override
  Future<void> speak({required String text, String? voice, required String language, required double rate, required double pitch}) async {
    final gen = ++_generation;
    _busy = true;
    await _playingSub?.cancel();
    _playingSub = null;
    final String lang = language.toLowerCase().startsWith('es') ? 'es' : 'en-us';
    try {
      final response = await _client.post(
        baseUrl.resolve('/v1/speech'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'text': text, 'voice': voice, 'lang': lang, 'speed': _speedFor(rate)}),
      );
      if (gen != _generation) return;
      if (response.statusCode != 200) {
        _busy = false;
        _events.add(SpeechAudioError('speech service answered ${response.statusCode}'));
        return;
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['timeline'] is! Map<String, dynamic> || body['audio_url'] is! String) {
        _busy = false;
        _events.add(const SpeechAudioError('speech service reply is not a timeline and audio url'));
        return;
      }
      final timeline = KokoroTimeline.fromJson(body['timeline'] as Map<String, dynamic>);
      final hop = 1 / timeline.fps;
      for (final s in timeline.sentences) {
        if (s.mouth.isNotEmpty) _events.add(SpeechAudioLevels(s.start, hop, s.mouth));
      }
      _events.add(const SpeechAudioSynthesized());
      // The audio must come from the same origin as the speech service, over the same scheme. A reply that points
      // elsewhere is refused, so the app never loads media from a host the server did not name.
      final audio = baseUrl.resolve(body['audio_url'] as String);
      if (audio.scheme != baseUrl.scheme || audio.host != baseUrl.host || audio.port != baseUrl.port) {
        _busy = false;
        _events.add(const SpeechAudioError('speech service audio must come from the speech service itself'));
        return;
      }
      await _player.load(audio);
      if (gen != _generation) return;
      var started = false;
      _playingSub = _player.playing.listen((isPlaying) {
        if (gen != _generation) return;
        if (isPlaying && !started) {
          started = true;
          _events.add(const SpeechAudioStarted());
        } else if (!isPlaying && started) {
          _busy = false;
          _events.add(const SpeechAudioDone());
          _playingSub?.cancel();
          _playingSub = null;
        }
      });
      await _player.play();
    } on FormatException catch (e) {
      if (gen == _generation) {
        _busy = false;
        _events.add(SpeechAudioError('speech service reply was not valid: ${e.message}'));
      }
    } catch (e) {
      if (gen == _generation) {
        _busy = false;
        _events.add(SpeechAudioError('speech could not be played (${e.runtimeType})'));
      }
    }
  }

  /// Stops the current reply. Listeners get a [SpeechAudioDone] marked interrupted.
  @override
  Future<void> stop() async {
    final wasSpeaking = _busy;
    _busy = false;
    _generation++;
    await _playingSub?.cancel();
    _playingSub = null;
    await _player.stop();
    if (wasSpeaking) _events.add(const SpeechAudioDone(interrupted: true));
  }

  /// flutter_tts rate 0.5 is the app's normal pace; the Kokoro speed is 0.95 at that pace (SPEECH_PACING.md).
  static double _speedFor(double rate) => (0.95 * (rate / 0.5)).clamp(0.6, 1.3).toDouble();

  Future<void> dispose() async {
    _generation++;
    _busy = false;
    await _playingSub?.cancel();
    await _player.stop();
    await _events.close();
    _client.close();
  }
}
