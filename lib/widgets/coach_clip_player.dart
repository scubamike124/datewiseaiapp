import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../avatar/coach_clips.dart';
import '../l10n/l10n.dart';

/// Plays one approved coach clip with always-visible controls.
///
/// Changing [clip] stops and releases the previous clip before the new one starts, so two coaches'
/// voices never overlap. Setting [paused] pauses playback, for example when the user leaves the tab.
/// Playback never starts on its own when a clip is first shown; the user taps play.
class CoachClipPlayer extends StatefulWidget {
  const CoachClipPlayer({super.key, required this.clip, this.paused = false});

  final CoachClip clip;
  final bool paused;

  @override
  State<CoachClipPlayer> createState() => _CoachClipPlayerState();
}

class _CoachClipPlayerState extends State<CoachClipPlayer> {
  VideoPlayerController? _controller;
  int _generation = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open(widget.clip);
  }

  @override
  void didUpdateWidget(CoachClipPlayer old) {
    super.didUpdateWidget(old);
    if (old.clip.asset != widget.clip.asset) {
      _open(widget.clip);
    } else if (widget.paused && !old.paused) {
      _controller?.pause();
    }
  }

  /// Stops the current clip (audio included), releases it, then loads [clip] without playing it.
  Future<void> _open(CoachClip clip) async {
    final generation = ++_generation;
    final previous = _controller;
    _controller = null;
    _failed = false;
    if (previous != null) {
      await previous.pause();
      await previous.dispose();
    }
    if (!mounted || generation != _generation) return;

    final next = VideoPlayerController.asset(clip.asset);
    _controller = next;
    setState(() {});
    try {
      await next.initialize();
      await next.setLooping(false);
      if (!mounted || generation != _generation) {
        await next.dispose();
        return;
      }
      setState(() {});
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay(VideoPlayerController c) {
    if (c.value.isPlaying) {
      c.pause();
    } else {
      if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
      c.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final playing = ready && c.value.isPlaying;
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: '${widget.clip.coachId} ${widget.clip.labelKey}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: ready ? c.value.aspectRatio : 4 / 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: const Color(0xFF201E22),
                child: _failed
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(l.coachClipUnavailable, textAlign: TextAlign.center),
                        ),
                      )
                    : ready
                        ? VideoPlayer(c)
                        : Image.asset(CoachClips.posterAsset, fit: BoxFit.cover, excludeFromSemantics: true),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Controls stay on screen: they are never hidden behind the video or auto-faded.
          Row(
            children: [
              IconButton(
                key: const ValueKey('coach-clip-toggle'),
                tooltip: playing ? l.coachClipPause : l.coachClipPlay,
                icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                iconSize: 40,
                color: scheme.primary,
                onPressed: ready ? () => _togglePlay(c) : null,
              ),
              Expanded(
                child: ready
                    ? VideoProgressIndicator(
                        c,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        colors: VideoProgressColors(playedColor: scheme.primary),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
