import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../avatar/coach_clips.dart';
import '../l10n/l10n.dart';

/// Plays one approved coach clip with always-visible controls.
///
/// Changing [clip] stops and releases the previous clip before the new one loads, so two coaches'
/// voices never overlap. [paused] pauses playback, for example when the user leaves the tab. The clip
/// is never started by itself: the user taps play. [onPlaybackChanged] reports every change to
/// playing or stopped, including the end of the clip and a pause from [paused].
class CoachClipPlayer extends StatefulWidget {
  const CoachClipPlayer({super.key, required this.clip, this.paused = false, this.onPlaybackChanged});

  final CoachClip clip;
  final bool paused;
  final ValueChanged<bool>? onPlaybackChanged;

  @override
  State<CoachClipPlayer> createState() => _CoachClipPlayerState();
}

class _CoachClipPlayerState extends State<CoachClipPlayer> {
  VideoPlayerController? _controller;
  int _generation = 0;
  bool _failed = false;
  bool _lastReportedPlaying = false;

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
      previous.removeListener(_onValueChanged);
      await previous.pause();
      await previous.dispose();
    }
    _reportPlaying(false);
    if (!mounted || generation != _generation) return;

    final next = VideoPlayerController.asset(clip.asset);
    _controller = next;
    next.addListener(_onValueChanged);
    setState(() {});
    try {
      await next.initialize();
      await next.setLooping(false);
      if (!mounted || generation != _generation) return;
      setState(() {});
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    }
  }

  /// Keeps the parent informed. Called from the controller's listener, so it runs outside the build.
  void _onValueChanged() {
    final c = _controller;
    if (c == null) return;
    _reportPlaying(c.value.isPlaying);
  }

  void _reportPlaying(bool playing) {
    if (playing == _lastReportedPlaying) return;
    _lastReportedPlaying = playing;
    final cb = widget.onPlaybackChanged;
    if (cb == null) return;
    // Pausing from didUpdateWidget happens during the build phase; report after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(playing);
    });
  }

  @override
  void dispose() {
    _generation++;
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_onValueChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _togglePlay(VideoPlayerController c) {
    if (c.value.isPlaying) {
      c.pause();
    } else {
      if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
      c.play();
    }
  }

  /// The coach's own portrait while a clip loads, so Ethan never shows Ava's face.
  String get _posterAsset => 'assets/coaches/${widget.clip.coachId}-hero.jpg';

  String _labelFor(AppLocalizations l) => switch (widget.clip.labelKey) {
        'opening' => l.coachClipOpening,
        _ => l.coachClipReference,
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = _controller;
    final scheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Semantics(
      container: true,
      label: _labelFor(l),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Portrait 4:5, but never taller than 42% of the screen, so the grid stays on screen on small phones.
          final height = (constraints.maxWidth * 1.25).clamp(0.0, screenHeight * 0.42).toDouble();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: height,
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
                        : c == null
                            ? Image.asset(_posterAsset, fit: BoxFit.cover, excludeFromSemantics: true)
                            : ValueListenableBuilder<VideoPlayerValue>(
                                valueListenable: c,
                                builder: (context, value, _) {
                                  if (!value.isInitialized) {
                                    return Image.asset(_posterAsset, fit: BoxFit.cover, excludeFromSemantics: true);
                                  }
                                  return FittedBox(
                                    fit: BoxFit.cover,
                                    clipBehavior: Clip.hardEdge,
                                    child: SizedBox(
                                      width: value.size.width,
                                      height: value.size.height,
                                      child: VideoPlayer(c),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Controls stay on screen: they are never hidden behind the video or auto-faded.
              Row(
                children: [
                  if (c == null || _failed)
                    const SizedBox(width: 48, height: 48)
                  else
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: c,
                      builder: (context, value, _) {
                        final playing = value.isPlaying;
                        final ready = value.isInitialized;
                        return IconButton(
                          key: const ValueKey('coach-clip-toggle'),
                          tooltip: playing ? l.coachClipPause : l.coachClipPlay,
                          icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                          iconSize: 40,
                          color: scheme.primary,
                          onPressed: ready ? () => _togglePlay(c) : null,
                        );
                      },
                    ),
                  Expanded(
                    child: (c == null || _failed)
                        ? const SizedBox.shrink()
                        : VideoProgressIndicator(
                            c,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            colors: VideoProgressColors(playedColor: scheme.primary),
                          ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
