import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../services/ai_config.dart';
import '../../services/coach_usage.dart';

/// The reply's audio could not be produced; the hosted session is closed and
/// the stage uses the frame avatar with the system voice.
class AvatarAudioUnavailable implements Exception {
  const AvatarAudioUnavailable([this.why = '']);
  final String why;
}

/// Pipeline step 2: the coach's reply TEXT (always written by the chat AI, and
/// still shown in the chat) becomes speech audio that is fed to the vendor's
/// audio-in. The vendor never writes or changes what the coach says.
abstract class AvatarAudioSource {
  /// PCM16 little-endian mono chunks of [text] at [sampleRate] Hz.
  Stream<Uint8List> synthesize(String text, {required String language, required String coachId});
  int get sampleRate;
}

/// Neural voice from the Worker (voice plan: POST /tts, Workers AI Aura-2, WAV
/// linear16 at 24 kHz). That endpoint is built on the voice branch
/// (docs/research/voice-decision-2026-11-24/INTEGRATION_PLAN.md), not here: until it
/// exists the Worker answers 404 and this source throws [AvatarAudioUnavailable],
/// which makes the stage fall back. Same StoreKit header as chat.
class WorkerTtsAudioSource implements AvatarAudioSource {
  WorkerTtsAudioSource({String? baseUrl, http.Client Function()? clientFactory, String? Function()? entitlement})
      : _base = (baseUrl ?? AIConfig.coachBackendUrl).replaceAll(RegExp(r'/+$'), ''),
        _clientFactory = clientFactory ?? http.Client.new,
        _entitlement = entitlement ?? (() => EntitlementToken.current);
  final String _base;
  final http.Client Function() _clientFactory;
  final String? Function() _entitlement;

  @override
  int get sampleRate => 24000;

  @override
  Stream<Uint8List> synthesize(String text, {required String language, required String coachId}) async* {
    final jws = _entitlement();
    if (jws == null) throw const AvatarAudioUnavailable('no entitlement');
    final client = _clientFactory();
    try {
      final res = await client
          .post(Uri.parse('$_base/tts'),
              headers: {'Content-Type': 'application/json', 'X-DateWise-Entitlement': jws},
              body: jsonEncode({'coachId': coachId, 'text': text, 'language': language}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw AvatarAudioUnavailable('tts ${res.statusCode}');
      final wav = res.bodyBytes;
      // 44-byte canonical WAV header (linear16); anything shorter is not audio.
      if (wav.length <= 44) throw const AvatarAudioUnavailable('empty');
      const chunk = 9600; // 200 ms at 24 kHz
      for (var i = 44; i < wav.length; i += chunk) {
        yield Uint8List.sublistView(wav, i, math.min(i + chunk, wav.length) & ~1);
      }
    } on AvatarAudioUnavailable {
      rethrow;
    } catch (_) {
      throw const AvatarAudioUnavailable('network');
    } finally {
      client.close();
    }
  }
}

/// Pilot debug only: a speech-like tone burst (syllable-rate amplitude
/// modulation), so the pipeline (connection, latency, interruption, minute
/// counting) can be exercised before the neural voice exists. It says nothing
/// useful: lip-sync quality needs real speech from [WorkerTtsAudioSource].
class ToneAudioSource implements AvatarAudioSource {
  ToneAudioSource({this.seconds = 3});
  final double seconds;
  @override
  int get sampleRate => 24000;

  @override
  Stream<Uint8List> synthesize(String text, {required String language, required String coachId}) async* {
    final n = (seconds * sampleRate).round();
    final data = ByteData(n * 2);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final syllable = math.max(0.0, math.sin(2 * math.pi * 4 * t)); // ~4 syllables/s
      final v = math.sin(2 * math.pi * 180 * t) * 0.5 + math.sin(2 * math.pi * 540 * t) * 0.2;
      data.setInt16(i * 2, (v * syllable * 12000).round(), Endian.little);
    }
    final all = data.buffer.asUint8List();
    const chunk = 9600;
    for (var i = 0; i < all.length; i += chunk) {
      yield Uint8List.sublistView(all, i, math.min(i + chunk, all.length));
    }
  }
}
