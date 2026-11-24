import 'dart:convert';
import 'dart:typed_data';

/// The vendor-agnostic Dart <-> JavaScript bridge protocol (version 1).
///
/// The WebView page (assets/avatar_pilot/index.html + bridge.js) exposes
/// `window.dwAvatar.receive(jsonString)` for Dart -> JS commands and posts JSON
/// strings to the `DWAvatar` JavaScript channel for JS -> Dart events. Every
/// message is a JSON object `{"v":1,"type":...}`. Unknown types and malformed
/// messages are ignored on both sides, so a vendor adapter can add events
/// without breaking the app.
///
/// Dart -> JS commands
///   start      {vendor, sessionToken, audio:{encoding,sampleRate,channels}, idleSeconds, maxSeconds}
///   speak      {id, audio: base64 PCM16 little-endian mono, sampleRate, last: bool} (the page resamples to the vendor's rate)
///              or {id, text}  (vendor text-to-speech; pilot debug only)
///   interrupt  {}   drop audio not yet spoken
///   stop       {}   close the vendor session and release media
///
/// JS -> Dart events
///   ready      {}                          page loaded, adapters registered
///   state      {state: connecting|listening|thinking|speaking|idle}
///   firstFrame {ms}                        time from `start` to the first video frame
///   network    {quality: good|poor, rttMs?}
///   mic        {state: granted|denied|prompt|unknown}   page-side microphone permission (the face never asks)
///   error      {code, message}             code: sdk_missing | session_refused | permission_denied |
///                                          webview | media | connect_timeout | unknown
///   ended      {reason}                    reason: stop | max | idle | remote | error
const int kBridgeVersion = 1;

enum AvatarActivity { idle, listening, thinking, speaking }

sealed class AvatarBridgeCommand {
  const AvatarBridgeCommand();
  Map<String, Object?> toJson();
  String encode() => jsonEncode({'v': kBridgeVersion, ...toJson()});
}

class StartCommand extends AvatarBridgeCommand {
  const StartCommand({
    required this.vendor,
    required this.sessionToken,
    required this.sampleRate,
    required this.idleSeconds,
    required this.maxSeconds,
  });
  final String vendor;
  final String sessionToken;
  final int sampleRate;
  final int idleSeconds;
  final int maxSeconds;
  @override
  Map<String, Object?> toJson() => {
        'type': 'start',
        'vendor': vendor,
        'sessionToken': sessionToken,
        'audio': {'encoding': 'pcm_s16le', 'sampleRate': sampleRate, 'channels': 1},
        'idleSeconds': idleSeconds,
        'maxSeconds': maxSeconds,
      };
}

class SpeakCommand extends AvatarBridgeCommand {
  SpeakCommand.audio({required this.id, required Uint8List pcm16, required int this.sampleRate, this.last = false})
      : audioBase64 = base64Encode(pcm16),
        text = null;
  const SpeakCommand.text({required this.id, required String this.text})
      : audioBase64 = null,
        sampleRate = null,
        last = true;
  final String id;
  final String? audioBase64;
  final String? text;
  final int? sampleRate; // rate of the PCM in [audioBase64]; the page resamples to the vendor's rate
  final bool last;
  @override
  Map<String, Object?> toJson() => {
        'type': 'speak',
        'id': id,
        if (audioBase64 != null) 'audio': audioBase64,
        if (sampleRate != null) 'sampleRate': sampleRate,
        if (text != null) 'text': text,
        'last': last,
      };
}

class InterruptCommand extends AvatarBridgeCommand {
  const InterruptCommand();
  @override
  Map<String, Object?> toJson() => {'type': 'interrupt'};
}

class StopCommand extends AvatarBridgeCommand {
  const StopCommand();
  @override
  Map<String, Object?> toJson() => {'type': 'stop'};
}

sealed class AvatarBridgeEvent {
  const AvatarBridgeEvent();
}

class ReadyEvent extends AvatarBridgeEvent {
  const ReadyEvent();
}

class StateEvent extends AvatarBridgeEvent {
  const StateEvent(this.activity);
  final AvatarActivity activity;
}

class FirstFrameEvent extends AvatarBridgeEvent {
  const FirstFrameEvent(this.ms);
  final int ms;
}

class NetworkEvent extends AvatarBridgeEvent {
  const NetworkEvent({required this.poor, this.rttMs});
  final bool poor;
  final int? rttMs;
}

class MicEvent extends AvatarBridgeEvent {
  const MicEvent(this.state);
  final String state;
}

class ErrorEvent extends AvatarBridgeEvent {
  const ErrorEvent(this.code, [this.message = '']);
  final String code;
  final String message;
}

class EndedEvent extends AvatarBridgeEvent {
  const EndedEvent(this.reason);
  final String reason;
}

/// Parses one JS -> Dart message; null for anything malformed, of another
/// version or of an unknown type (ignored, never an exception).
AvatarBridgeEvent? decodeBridgeEvent(String raw) {
  if (raw.length > 8192) return null;
  try {
    final m = jsonDecode(raw);
    if (m is! Map || m['v'] != kBridgeVersion) return null;
    switch (m['type']) {
      case 'ready':
        return const ReadyEvent();
      case 'state':
        final a = AvatarActivity.values.where((e) => e.name == m['state']);
        return a.isEmpty ? null : StateEvent(a.first);
      case 'firstFrame':
        final ms = m['ms'];
        return ms is num && ms >= 0 ? FirstFrameEvent(ms.round()) : null;
      case 'network':
        final rtt = m['rttMs'];
        return NetworkEvent(poor: m['quality'] == 'poor', rttMs: rtt is num ? rtt.round() : null);
      case 'mic':
        return MicEvent('${m['state']}'.substring(0, ('${m['state']}'.length).clamp(0, 16)));
      case 'error':
        return ErrorEvent('${m['code'] ?? 'unknown'}', '${m['message'] ?? ''}');
      case 'ended':
        return EndedEvent('${m['reason'] ?? 'unknown'}');
    }
  } catch (_) {
    /* malformed: ignored */
  }
  return null;
}
