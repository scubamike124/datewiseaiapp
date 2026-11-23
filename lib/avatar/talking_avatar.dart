import 'dart:math' as math;
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
  late AvatarAnimator _animator = _newAnimator();
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

  /// Seeded per coach and per session: the coaches never blink in unison,
  /// and the schedule differs every time.
  AvatarAnimator _newAnimator() =>
      AvatarAnimator(seed: widget.coach.id.hashCode ^ DateTime.now().microsecondsSinceEpoch);

  @visibleForTesting
  ValueListenable<AvatarPose> get pose => _pose;

  AvatarManifest? _manifest;

  void _loadManifest() {
    final id = widget.coach.id;
    AvatarManifest.load(widget.coach, bundle: widget.bundle).then((m) {
      if (mounted && widget.coach.id == id && m != null) setState(() => _manifest = m);
    });
  }

  @override
  void initState() {
    super.initState();
    _loadManifest();
  }

  @override
  void didUpdateWidget(TalkingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coach.id != widget.coach.id) {
      _manifest = null;
      _loadManifest();
      _release();
      _animator = _newAnimator();
      _timeBase = 0;
      _lastPose = -1;
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
    if (_frames?.isDisposed ?? false) {
      // Freed by another holder: show the still portrait.
      _ticker.stop();
      setState(() {});
      return;
    }
    final t = _timeBase + elapsed.inMicroseconds / 1e6;
    final speaking = widget.mood == AvatarMood.speaking;
    if (!speaking && t - _lastPose < 1 / idleFps) return;
    _lastPose = t;
    final lip = widget.lipSync;
    final mouth = speaking ? (lip?.sample() ?? VisemeSample.rest) : VisemeSample.rest;
    final jaw = speaking ? (lip?.jaw() ?? 0.0) : 0.0;
    _pose.value = _animator.frame(t, widget.mood, mouth, available: _available, jaw: jaw);
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
    // Disposed by another holder (e.g. a second stage switched coach): the
    // still portrait rather than an empty stage.
    if (frames == null || _still || frames.isDisposed) {
      // The still portrait (Reduce Motion, loading) is placed like the
      // animated one: mouth at [AvatarPainter.mouthAt] of the height.
      final m = _manifest;
      if (m?.mouth == null) return CoachImage(coach: widget.coach, semanticLabel: widget.stillLabel);
      return LayoutBuilder(builder: (context, box) {
        final img = Size(m!.width.toDouble(), m.height.toDouble());
        final fit = applyBoxFit(BoxFit.cover, img, box.biggest).source;
        double align(double slack, double offset) => slack <= 0 ? 0 : (2 * offset / slack - 1).clamp(-1.0, 1.0);
        final y = align(img.height - fit.height, m.mouth!.dy - AvatarPainter.mouthAt * fit.height);
        final x = align(img.width - fit.width, m.mouth!.dx - fit.width / 2);
        return CoachImage(coach: widget.coach, semanticLabel: widget.stillLabel, alignment: Alignment(x, y));
      });
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

  /// Largest jaw drop, as a fraction of the mouth width.
  static const double jawDrop = 0.12;

  /// Where the mouth sits on the stage (fraction of its height): high
  /// enough to stay clear of the caption fade at the bottom.
  static const double mouthAt = 0.55;

  /// The part of the portrait ([image] size) shown in a [box]: cover-fitted
  /// and placed so the [mouth] (portrait pixels) lands at [mouthAt] of the
  /// height and centered across. If the portrait has too little room below
  /// or above the mouth for that, it is zoomed in just enough. Without a
  /// mouth position, [focus] places it as before.
  static Rect sourceRect(Size image, Size box, Offset? mouth, Alignment focus) {
    final fitted = applyBoxFit(BoxFit.cover, image, box).source;
    if (mouth == null || box.isEmpty || mouth.dy <= 0 || mouth.dy >= image.height) {
      return focus.inscribe(fitted, Offset.zero & image);
    }
    var h = fitted.height;
    h = math.min(h, (image.height - mouth.dy) / (1 - mouthAt));
    h = math.min(h, mouth.dy / mouthAt);
    // A mouth at the very edge (a bad manifest) would leave no crop to draw.
    if (!(h >= 1)) return focus.inscribe(fitted, Offset.zero & image);
    final w = h * box.width / box.height;
    final top = (mouth.dy - mouthAt * h).clamp(0.0, math.max(0.0, image.height - h)).toDouble();
    final left = (mouth.dx - w / 2).clamp(0.0, math.max(0.0, image.width - w)).toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }

  /// The zoom that keeps the portrait covering a [size] box whatever the
  /// head motion ([AvatarPose.maxDx], [AvatarPose.maxDy],
  /// [AvatarPose.maxRotation]) and breathing do; computed for each stage
  /// size (the short large-text stage and the wide iPad stage differ).
  static double coverZoom(Size size) {
    if (size.isEmpty) return 1;
    const th = AvatarPose.maxRotation;
    final c = math.cos(th), s = math.sin(th);
    const dx = AvatarPose.maxDx, dy = AvatarPose.maxDy;
    final zx = (size.width * c + size.height * s + 2 * (dx * c + dy * s)) / size.width;
    final zy = (size.width * s + size.height * c + 2 * (dx * s + dy * c)) / size.height;
    return math.max(zx, zy) / 0.996; // breathing dips to 0.996
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sw = kReleaseMode ? null : (Stopwatch()..start());
    if (frames.isDisposed) return;
    final p = pose.value;
    final base = frames.base;
    final src = Size(base.width.toDouble(), base.height.toDouble());
    final srcRect = sourceRect(src, size, frames.manifest.mouth, focus);
    final dstRect = Offset.zero & size;
    final sx = dstRect.width / srcRect.width, sy = dstRect.height / srcRect.height;
    Rect toDst(Rect r) => Rect.fromLTWH((r.left - srcRect.left) * sx, (r.top - srcRect.top) * sy, r.width * sx, r.height * sy);

    canvas.save();
    canvas.clipRect(dstRect);
    // Head motion about the center, zoomed just enough to hide the edges.
    final c = dstRect.center;
    canvas.translate(c.dx + p.dx, c.dy + p.dy);
    canvas.rotate(p.rotation);
    canvas.scale(p.scale * coverZoom(size));
    canvas.translate(-c.dx, -c.dy);

    canvas.drawImageRect(base, srcRect, dstRect, _paint);
    var mouthDrawn = false;
    for (final layer in p.layers) {
      final hit = frames.patch(layer.patch);
      if (hit == null || layer.opacity <= 0) continue;
      final (img, patch) = hit;
      final dst = toDst(patch.rect);
      if (!dst.overlaps(dstRect)) continue;
      if (patch.region == AvatarRegion.mouth && p.jaw > 0.01) {
        _drawJaw(canvas, img, Offset.zero & Size(img.width.toDouble(), img.height.toDouble()), patch.rect, dst, p.jaw, layer.opacity);
        mouthDrawn = true;
        continue;
      }
      if (patch.region == AvatarRegion.mouth) mouthDrawn = true;
      final paint = Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, layer.opacity.clamp(0.0, 1.0));
      canvas.drawImageRect(img, Offset.zero & Size(img.width.toDouble(), img.height.toDouble()), dst, paint);
    }
    // The portrait's own mouth (rest) still drops its jaw while audible.
    if (!mouthDrawn && p.jaw > 0.01) {
      final region = frames.patch('mbp')?.$2.rect;
      if (region != null) _drawJaw(canvas, base, region, region, toDst(region), p.jaw, 1);
    }
    canvas.restore();
    if (sw != null) {
      final list = TalkingAvatarState.paintMicros;
      list.add(sw.elapsedMicroseconds);
      if (list.length > 600) list.removeRange(0, list.length - 600);
    }
  }

  /// Draws [src] of [img] (whose portrait-space rect is [portraitRect]) into
  /// [dst] as a mesh whose lower lip and chin are pulled down by [jaw]. The
  /// displacement is zero on the patch border, so it joins the portrait
  /// without a seam.
  void _drawJaw(Canvas canvas, ui.Image img, Rect src, Rect portraitRect, Rect dst, double jaw, double opacity) {
    final m = frames.manifest;
    final mouthY = m.mouth?.dy ?? (portraitRect.top + portraitRect.height * 0.35);
    final mw = m.mouthWidth ?? portraitRect.width * 0.45;
    final lineV = ((mouthY - portraitRect.top) / portraitRect.height).clamp(0.1, 0.7);
    final peakV = ((mouthY + 0.45 * mw - portraitRect.top) / portraitRect.height).clamp(lineV + 0.08, 0.88);
    final dropPx = jaw * jawDrop * mw * (dst.height / portraitRect.height);
    const nx = 8, ny = 12;
    double wy(double v) {
      double smooth(double x) => x * x * (3 - 2 * x);
      if (v <= lineV) return 0;
      if (v <= peakV) return smooth((v - lineV) / (peakV - lineV));
      return smooth((1 - v) / (1 - peakV));
    }

    final pos = <Offset>[], tex = <Offset>[];
    Offset at(int i, int j) {
      final u = i / nx, v = j / ny;
      final d = dropPx * math.sin(math.pi * u) * wy(v);
      return Offset(dst.left + u * dst.width, dst.top + v * dst.height + d);
    }

    Offset uv(int i, int j) => Offset(src.left + i / nx * src.width, src.top + j / ny * src.height);
    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        for (final (a, b) in const [(0, 0), (1, 0), (1, 1), (0, 0), (1, 1), (0, 1)]) {
          pos.add(at(i + a, j + b));
          tex.add(uv(i + a, j + b));
        }
      }
    }
    final paint = Paint()
      ..shader = frames.shaderFor(img)
      ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
    canvas.drawVertices(ui.Vertices(ui.VertexMode.triangles, pos, textureCoordinates: tex), BlendMode.srcOver, paint);
  }

  @override
  bool shouldRepaint(AvatarPainter old) => old.frames != frames || old.focus != focus;
}

/// Size in pixels that [ui.Image] patches take in memory (for diagnostics).
int avatarMemoryBytes(AvatarFrames f) =>
    f.base.width * f.base.height * 4 + f.images.values.fold(0, (a, ui.Image i) => a + i.width * i.height * 4);
