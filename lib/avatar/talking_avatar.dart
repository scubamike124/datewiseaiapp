import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models/coach.dart';
import '../widgets/dw.dart';
import 'avatar_animator.dart';
import 'avatar_frames.dart';
import 'lip_sync.dart';

/// The coach as an animated portrait: lip-synced mouth while speaking,
/// blinks, breathing, listening nods and a thinking look.
///
/// Every frame is drawn on the device from photo patches generated offline
/// from the approved portrait (lib/avatar/avatar_frames.dart); nothing is
/// streamed and no third party is involved. When Reduce Motion is on, the
/// frames are missing, or they no longer match the portrait, it shows the
/// still portrait instead ([stillLabel]).
class TalkingAvatar extends StatefulWidget {
  const TalkingAvatar({
    super.key,
    required this.coach,
    required this.mood,
    required this.label,
    required this.stillLabel,
    this.lipSync,
    this.bundle,
  });

  final Coach coach;
  final AvatarMood mood;

  /// Accessibility label while animated (e.g. "Ava, animated AI coach, speaking").
  final String label;

  /// Accessibility label of the still-portrait fallback.
  final String stillLabel;

  /// Mouth timing while speaking (from the voice service).
  final LipSyncDriver? lipSync;
  final AssetBundle? bundle;

  @override
  State<TalkingAvatar> createState() => TalkingAvatarState();
}

@visibleForTesting
class TalkingAvatarState extends State<TalkingAvatar> with SingleTickerProviderStateMixin {
  AvatarFrames? _frames;
  String? _held; // coach id whose frames this widget holds
  late final Ticker _ticker = createTicker(_tick);
  AvatarAnimator _animator = AvatarAnimator();
  final _pose = ValueNotifier<AvatarPose>(AvatarPose.still);
  Set<String> _available = const {};
  bool _still = false;
  double _timeBase = 0;
  double _lastPose = -1;

  /// Frame times measured in debug/profile (painter work per frame, µs).
  @visibleForTesting
  static final List<int> paintMicros = [];

  /// Pose updates while not speaking are limited to this rate (Hz): blinks,
  /// breathing and nods look the same at 30 fps and cost half the work.
  static const double idleFps = 30;

  @visibleForTesting
  AvatarFrames? get frames => _frames;

  @visibleForTesting
  ValueListenable<AvatarPose> get pose => _pose;

  @override
  void didUpdateWidget(TalkingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coach.id != widget.coach.id) {
      _release();
      _animator = AvatarAnimator();
      _timeBase = 0;
      _syncFrames();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = reduceMotion(context);
    _syncFrames();
  }

  /// Decodes the frames only when they will be shown (not under Reduce
  /// Motion), and frees them when Reduce Motion turns on.
  void _syncFrames() {
    if (_still) {
      _release();
    } else if (_held == null) {
      _load();
    }
    _syncTicker();
  }

  Future<void> _load() async {
    final coach = widget.coach;
    _held = coach.id;
    final f = await AvatarFrames.acquire(coach, bundle: widget.bundle);
    // Released meanwhile (disposed, coach changed, Reduce Motion on): the
    // hold was already given back.
    if (!mounted || _held != coach.id) return;
    setState(() {
      _frames = f;
      _available = f?.images.keys.toSet() ?? const {};
    });
    _syncTicker();
  }

  void _release() {
    final id = _held;
    _held = null;
    if (id != null) AvatarFrames.release(id);
    // Only called from didChangeDependencies / didUpdateWidget, which are
    // followed by a build anyway.
    _frames = null;
  }

  void _syncTicker() {
    final run = _frames != null && !_still;
    if (run && !_ticker.isActive) {
      // Continue the animation clock where it stopped, so blink timers and
      // gestures keep going after a pause (e.g. a Reduce Motion round trip).
      _timeBase = _animator.lastTime;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final t = _timeBase + elapsed.inMicroseconds / 1e6;
    final speaking = widget.mood == AvatarMood.speaking;
    if (!speaking && t - _lastPose < 1 / idleFps) return;
    _lastPose = t;
    final mouth = speaking ? (widget.lipSync?.sample() ?? VisemeSample.rest) : VisemeSample.rest;
    _pose.value = _animator.frame(t, widget.mood, mouth, available: _available);
  }

  @override
  void dispose() {
    _ticker.dispose();
    final id = _held;
    if (id != null) AvatarFrames.release(id);
    _pose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = _frames;
    if (frames == null || _still) {
      return CoachImage(coach: widget.coach, semanticLabel: widget.stillLabel);
    }
    return Semantics(
      label: widget.label,
      image: true,
      liveRegion: false,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey('talking-avatar-paint'),
            painter: AvatarPainter(frames, _pose, widget.coach.heroFocus),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// Paints the portrait cover-fitted at [focus], then the pose's patches.
class AvatarPainter extends CustomPainter {
  AvatarPainter(this.frames, this.pose, this.focus) : super(repaint: pose);

  final AvatarFrames frames;
  final ValueListenable<AvatarPose> pose;
  final Alignment focus;

  static final _paint = Paint()..filterQuality = FilterQuality.medium;

  @override
  void paint(Canvas canvas, Size size) {
    final sw = kReleaseMode ? null : (Stopwatch()..start());
    if (frames.isDisposed) return;
    final p = pose.value;
    final base = frames.base;
    final src = Size(base.width.toDouble(), base.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, src, size);
    final srcRect = focus.inscribe(fitted.source, Offset.zero & src);
    final dstRect = Offset.zero & size;
    final sx = dstRect.width / srcRect.width, sy = dstRect.height / srcRect.height;

    canvas.save();
    canvas.clipRect(dstRect);
    // Micro-motion about the center.
    final c = dstRect.center;
    canvas.translate(c.dx + p.dx, c.dy + p.dy);
    canvas.rotate(p.rotation);
    canvas.scale(p.scale);
    canvas.translate(-c.dx, -c.dy);

    canvas.drawImageRect(base, srcRect, dstRect, _paint);
    for (final layer in p.layers) {
      final hit = frames.patch(layer.patch);
      if (hit == null || layer.opacity <= 0) continue;
      final (img, patch) = hit;
      final r = patch.rect;
      final dst = Rect.fromLTWH((r.left - srcRect.left) * sx, (r.top - srcRect.top) * sy, r.width * sx, r.height * sy);
      if (!dst.overlaps(dstRect)) continue;
      final paint = Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, layer.opacity.clamp(0.0, 1.0));
      canvas.drawImageRect(img, Offset.zero & Size(img.width.toDouble(), img.height.toDouble()), dst, paint);
    }
    canvas.restore();
    if (sw != null) {
      final list = TalkingAvatarState.paintMicros;
      list.add(sw.elapsedMicroseconds);
      if (list.length > 600) list.removeRange(0, list.length - 600);
    }
  }

  @override
  bool shouldRepaint(AvatarPainter old) => old.frames != frames || old.focus != focus;
}

/// Size in pixels that [ui.Image] patches take in memory (for diagnostics).
int avatarMemoryBytes(AvatarFrames f) =>
    f.base.width * f.base.height * 4 + f.images.values.fold(0, (a, ui.Image i) => a + i.width * i.height * 4);
