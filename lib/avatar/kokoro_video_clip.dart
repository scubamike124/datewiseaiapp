import 'dart:async';

import 'package:video_player/video_player.dart';

import 'kokoro_audio_backend.dart';

/// Plays a Kokoro clip with video_player (already a dependency; audio-only files play through it). Emits true when playback
/// starts and false when it ends, so [KokoroSpeechAudioBackend] sends started and done at the audio's own times.
class VideoPlayerClipPlayer implements KokoroClipPlayer {
  VideoPlayerController? _controller;
  final _playing = StreamController<bool>.broadcast();
  bool _last = false;

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Future<void> load(Uri audioUrl) async {
    await _controller?.dispose();
    final options = VideoPlayerOptions(mixWithOthers: false);
    final c = audioUrl.scheme == 'asset'
        ? VideoPlayerController.asset(audioUrl.path.replaceFirst(RegExp(r'^/'), ''), videoPlayerOptions: options)
        : VideoPlayerController.networkUrl(audioUrl, videoPlayerOptions: options);
    _controller = c;
    await c.initialize();
    c.addListener(_onValue);
  }

  void _onValue() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    final now = v.isPlaying;
    final ended = v.position >= v.duration && v.duration > Duration.zero && !now;
    if (now != _last) {
      _last = now;
      if (!_playing.isClosed) _playing.add(now);
    } else if (ended && _last) {
      _last = false;
      if (!_playing.isClosed) _playing.add(false);
    }
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> stop() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_onValue);
      await c.dispose();
    }
    if (_last) {
      _last = false;
      if (!_playing.isClosed) _playing.add(false);
    }
  }
}
