import 'dart:async';
import 'dart:typed_data';

import 'package:datewise_ai/avatar/hosted/avatar_audio_source.dart';
import 'package:datewise_ai/avatar/hosted/avatar_bridge.dart';
import 'package:datewise_ai/avatar/hosted/avatar_session_api.dart';
import 'package:datewise_ai/avatar/hosted/bridge_protocol.dart';

/// A bridge with no WebView: records commands, lets a test emit page events.
class FakeAvatarBridge implements AvatarBridge {
  final sent = <AvatarBridgeCommand>[];
  final _events = StreamController<AvatarBridgeEvent>.broadcast(sync: true);
  bool disposed = false;
  @override
  Stream<AvatarBridgeEvent> get events => _events.stream;
  @override
  Future<void> send(AvatarBridgeCommand c) async => sent.add(c);
  void emit(AvatarBridgeEvent e) => _events.add(e);
  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }

  Iterable<T> sentOf<T extends AvatarBridgeCommand>() => sent.whereType<T>();
}

/// A Worker stand-in with scripted behavior.
class FakeSessionApi implements AvatarSessionApi {
  Object? openError;
  AvatarSession session = const AvatarSession(
    sessionId: 'av_000000000000000000000001',
    vendor: 'simli',
    sessionToken: 'tok',
    maxSeconds: 600,
    idleSeconds: 60,
    heartbeatSeconds: 30,
    sampleRate: 16000,
    usedSeconds: 0,
    totalSeconds: 3600,
  );
  int opens = 0, beats = 0, ends = 0;
  Object? beatError;
  @override
  Future<AvatarSession> open({required String coachId, String? language}) async {
    opens++;
    if (openError != null) throw openError!;
    return session;
  }

  @override
  Future<int?> heartbeat(String sessionId) async {
    beats++;
    if (beatError != null) throw beatError!;
    return 30 * beats;
  }

  @override
  Future<int?> end(String sessionId) async {
    ends++;
    return 12;
  }

  @override
  Duration get timeout => const Duration(seconds: 1);
}

class FakeAudio implements AvatarAudioSource {
  FakeAudio({this.fail = false});
  final bool fail;
  final texts = <String>[];
  @override
  int get sampleRate => 24000;
  @override
  Stream<Uint8List> synthesize(String text, {required String language, required String coachId}) async* {
    texts.add(text);
    if (fail) throw const AvatarAudioUnavailable('test');
    yield Uint8List.fromList([1, 0, 2, 0]);
    yield Uint8List.fromList([3, 0, 4, 0]);
  }
}
