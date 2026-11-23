import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'lip_sync.dart';

/// What the coach is doing on the voice stage.
enum AvatarMood {
  /// Waiting: blinks and breathes.
  idle,

  /// The user is talking: attentive, with small nods.
  listening,

  /// The reply is being written: eyes up and aside, lips closed.
  thinking,

  /// Reading the reply aloud: lip-synced mouth, blinks.
  speaking,
}

/// One patch to draw over the portrait, with its opacity.
@immutable
class AvatarLayer {
  const AvatarLayer(this.patch, this.opacity);
  final String patch;
  final double opacity;
  @override
  bool operator ==(Object other) => other is AvatarLayer && other.patch == patch && other.opacity == opacity;
  @override
  int get hashCode => Object.hash(patch, opacity);
  @override
  String toString() => '$patch@${opacity.toStringAsFixed(2)}';
}

/// Everything the painter needs for one frame.
@immutable
class AvatarPose {
  const AvatarPose({required this.layers, this.scale = 1, this.dx = 0, this.dy = 0, this.rotation = 0});
  static const still = AvatarPose(layers: []);

  /// Patches in paint order (head expressions, then eyes, then mouth).
  final List<AvatarLayer> layers;

  /// Micro-motion (breathing and sway), in logical pixels and radians.
  final double scale;
  final double dx;
  final double dy;
  final double rotation;
}

/// Turns time, mood and the lip-sync sample into an [AvatarPose].
///
/// Pure and deterministic for a given [seed], so it is unit-tested and the
/// offline demo renderer (tool/avatar/render_demo.py) mirrors it.
class AvatarAnimator {
  AvatarAnimator({int seed = 7}) : _rng = math.Random(seed);

  final math.Random _rng;
  double _nextBlink = 2.2;
  double _blinkStart = -10;
  AvatarMood _mood = AvatarMood.idle;
  double _moodSince = 0;
  double _exprWeight = 0;
  String? _expr;
  double _lastT = 0;

  /// A blink: 0.07 s closing, 0.05 s shut, 0.1 s opening.
  static const double blinkLength = 0.22;
  static const double nodPeriod = 3.4;
  static const double nodLength = 0.9;
  static const double exprFade = 0.25;

  /// Eyelid closure (0 open .. 1 shut) [s] seconds into a blink.
  static double blinkClosure(double s) {
    if (s < 0 || s >= blinkLength) return 0;
    if (s < 0.07) return s / 0.07;
    if (s < 0.12) return 1;
    return 1 - (s - 0.12) / 0.10;
  }

  /// Head-patch for the listening nod [s] seconds into the nod.
  static (String?, double) nodFrame(double s) {
    if (s < 0 || s >= nodLength) return (null, 0);
    // Down (nod_1 then nod_2) and back up, as a smooth bump.
    final p = math.sin(math.pi * s / nodLength); // 0..1..0
    if (p < 0.5) return ('nod_1', p * 2);
    return ('nod_2', (p - 0.5) * 2);
  }

  AvatarPose frame(double t, AvatarMood mood, VisemeSample mouth, {Set<String>? available}) {
    final dt = (t - _lastT).clamp(0.0, 0.1);
    _lastT = t;
    if (mood != _mood) {
      _mood = mood;
      _moodSince = t;
    }
    bool has(String n) => available == null || available.contains(n);
    final layers = <AvatarLayer>[];

    // Head expression (thinking frame; listening nods drawn below).
    final wantExpr = mood == AvatarMood.thinking && has('think') ? 'think' : null;
    if (wantExpr != null) {
      _expr = wantExpr;
      _exprWeight = math.min(1, _exprWeight + dt / exprFade);
    } else {
      _exprWeight = math.max(0, _exprWeight - dt / exprFade);
    }
    if (_exprWeight > 0 && _expr != null) layers.add(AvatarLayer(_expr!, _exprWeight));

    var headBusy = _exprWeight > 0;
    if (mood == AvatarMood.listening && !headBusy) {
      final s = (t - _moodSince - 0.4) % nodPeriod;
      if (t - _moodSince > 0.4) {
        final (n, w) = nodFrame(s);
        if (n != null && has(n) && has('nod_1')) {
          // nod_2 is drawn over a full nod_1, so the bump is continuous.
          if (n == 'nod_2') layers.add(const AvatarLayer('nod_1', 1));
          layers.add(AvatarLayer(n, w));
          headBusy = true;
        }
      }
    }

    // Blinks, when the head patch is not covering the eyes.
    if (t >= _nextBlink) {
      _blinkStart = t;
      // Every 2.5-6 s; a little more often while listening.
      final base = mood == AvatarMood.listening ? 2.2 : 2.8;
      _nextBlink = t + base + _rng.nextDouble() * 3.2;
    }
    final c = blinkClosure(t - _blinkStart);
    if (c > 0 && !headBusy) {
      if (has('blink_half')) layers.add(AvatarLayer('blink_half', math.min(1, c * 2)));
      if (c > 0.5 && has('blink_closed')) layers.add(AvatarLayer('blink_closed', (c - 0.5) * 2));
    }

    // Mouth.
    if (mood == AvatarMood.speaking && !headBusy) {
      final from = mouth.from.asset, to = mouth.to.asset;
      if (from != null && has(from) && mouth.mix < 1) layers.add(AvatarLayer(from, to == null ? 1 - mouth.mix : 1));
      if (to != null && has(to) && mouth.mix > 0) layers.add(AvatarLayer(to, mouth.mix));
    }

    // Breathing and a slow sway; a little livelier while speaking.
    final live = mood == AvatarMood.speaking ? 1.0 : 0.7;
    final open = mood == AvatarMood.speaking ? (mouth.viseme.openness) : 0.0;
    return AvatarPose(
      layers: layers,
      scale: 1.015 + 0.004 * math.sin(2 * math.pi * t / 4.2),
      dx: 1.4 * live * math.sin(2 * math.pi * t / 7.3),
      dy: 0.9 * live * math.sin(2 * math.pi * t / 5.1 + 1) + 0.5 * open,
      rotation: 0.004 * live * math.sin(2 * math.pi * t / 6.1),
    );
  }
}
