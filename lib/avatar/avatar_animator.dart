import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'lip_sync.dart';
import 'viseme.dart';

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
  const AvatarPose({required this.layers, this.scale = 1, this.dx = 0, this.dy = 0, this.rotation = 0, this.jaw = 0});
  static const still = AvatarPose(layers: []);

  /// Patches in paint order (head expressions, then eyes, then mouth).
  final List<AvatarLayer> layers;

  /// Micro-motion (breathing and sway), in logical pixels and radians.
  final double scale;
  final double dx;
  final double dy;
  final double rotation;

  /// Jaw drop, 0..1: the painter stretches the lower lip and chin of the
  /// mouth region down by up to [AvatarPainter.jawDrop] of the mouth width.
  final double jaw;

  /// Largest |dx|, |dy| (logical px) and |rotation| (radians) the animator
  /// produces; the painter zooms just enough to keep the frame edges hidden.
  static const double maxDx = 1.2, maxDy = 3.8, maxRotation = 0.016;
}

/// Turns time, mood and the lip-sync sample into an [AvatarPose].
///
/// Pure and deterministic for a given [seed], so it is unit-tested and the
/// offline demo renderer (tool/avatar/render_demo_test.dart) uses it as is.
///
/// Patches are switched, never crossfaded, for the eyes (a half-faded blink
/// shows the iris through the lids). Head motion is a small whole-image
/// transform (a few pixels, under a degree), so nothing is warped.
class AvatarAnimator {
  /// [seed] decides the blink and nod schedule. The app seeds it per coach
  /// and session, so the coaches never blink in unison or repeat a pattern.
  AvatarAnimator({required int seed}) : _rng = math.Random(seed) {
    // The first blink comes at a random moment, not at a fixed time.
    _nextBlink = 1.5 + _rng.nextDouble() * 2.5;
  }

  final math.Random _rng;
  double _nextBlink = 2.2;
  double _blinkStart = -10;
  AvatarMood _mood = AvatarMood.idle;
  double _moodSince = 0;
  double _lastT = 0;

  // Head gestures: start time, length, depth (px down), tilt (radians).
  double _gestureStart = -10;
  double _gestureLength = 0.4;
  double _gestureDepth = 0;
  double _gestureTilt = 0;
  double _nextNod = 0;
  double _restSince = 0;
  bool _wasRest = true;
  double _lastEmphasis = -10;
  bool _secondOfDouble = false;

  /// A blink: half-closed 40 ms, shut 60 ms, half-open 50 ms (150 ms).
  static const double blinkLength = 0.15;

  /// Chance that a blink is followed by a second one.
  static const double doubleBlinkChance = 0.2;

  /// Listening nod: 400 ms down and back, every 2.6-3.6 s.
  static const double nodLength = 0.4;

  /// Thinking glance appears this long after thinking starts.
  static const double glanceDelay = 0.15;

  /// Eye patch for [s] seconds into a blink: null, `blink_half` or `blink_closed`.
  static String? blinkFrame(double s) {
    if (s < 0 || s >= blinkLength) return null;
    if (s < 0.04) return 'blink_half';
    if (s < 0.10) return 'blink_closed';
    return 'blink_half';
  }

  /// Head offset of a gesture [s] seconds in: a smooth down-and-back bump.
  static double bump(double s, double length) => (s < 0 || s >= length) ? 0 : math.sin(math.pi * s / length);

  void _gesture(double t, double length, double depth, double tilt) {
    _gestureStart = t;
    _gestureLength = length;
    _gestureDepth = depth;
    _gestureTilt = tilt;
  }

  AvatarPose frame(double t, AvatarMood mood, VisemeSample mouth, {Set<String>? available, double jaw = 0}) {
    _lastT = t;
    if (mood != _mood) {
      _mood = mood;
      _moodSince = t;
      _nextNod = t + 0.5;
      if (mood == AvatarMood.thinking) _gesture(t, 0.6, 1.5, 0);
    }
    bool has(String n) => available == null || available.contains(n);
    final layers = <AvatarLayer>[];

    // Head gestures.
    if (mood == AvatarMood.listening && t >= _nextNod) {
      _gesture(t, nodLength, 3.0, 0.009);
      _nextNod = t + 2.6 + _rng.nextDouble();
    }
    if (mood == AvatarMood.speaking) {
      final rest = mouth.viseme == Viseme.rest;
      if (rest && !_wasRest) _restSince = t;
      // A phrase starts after a pause: a small nod with a slight tilt.
      if (!rest && _wasRest && t - _restSince > 0.25) {
        _gesture(t, 0.45, 2.5, (_rng.nextBool() ? 1 : -1) * 0.011);
      } else if (!rest && mouth.to == Viseme.a && t - _lastEmphasis > 0.9 && t - _gestureStart > 0.6) {
        // Emphasis on a stressed open vowel: a slightly deeper nod with a
        // small tilt (about 0.3 degrees). With closed, relaxed lips at rest
        // the open vowels read more clearly when the head moves with them.
        _gesture(t, 0.34, 2.8, (_rng.nextBool() ? 1 : -1) * 0.005);
        _lastEmphasis = t;
      } else if (!rest && (mouth.to == Viseme.e || mouth.to == Viseme.o) && t - _gestureStart > 0.7) {
        // A small tilt on other stressed vowels (about 0.4 degrees).
        _gesture(t, 0.35, 1.0, (_rng.nextBool() ? 1 : -1) * 0.007);
      }
      _wasRest = rest;
    } else {
      _wasRest = true;
    }
    final g = bump(t - _gestureStart, _gestureLength);
    final holdTilt = mood == AvatarMood.thinking && t - _moodSince >= 0.3 ? 0.012 : 0.0;

    // Blinks (switched, not faded), with an occasional double blink.
    if (t >= _nextBlink) {
      _blinkStart = t;
      final base = mood == AvatarMood.listening ? 2.2 : 2.8;
      // A double blink at most: the second blink of a pair never starts
      // another one.
      if (!_secondOfDouble && _rng.nextDouble() < doubleBlinkChance) {
        _nextBlink = t + blinkLength + 0.12;
        _secondOfDouble = true;
      } else {
        _nextBlink = t + base + _rng.nextDouble() * 3.2;
        _secondOfDouble = false;
      }
    }
    final blink = blinkFrame(t - _blinkStart);
    if (blink != null && has(blink)) {
      layers.add(AvatarLayer(blink, 1));
    } else if (mood == AvatarMood.thinking && t - _moodSince >= glanceDelay && has('gaze')) {
      layers.add(const AvatarLayer('gaze', 1));
    }

    // Mouth: lip-synced while speaking; lips closed while thinking.
    if (mood == AvatarMood.speaking) {
      final from = mouth.from.asset, to = mouth.to.asset;
      if (from != null && has(from) && mouth.mix < 1) layers.add(AvatarLayer(from, to == null ? 1 - mouth.mix : 1));
      if (to != null && has(to) && mouth.mix > 0) layers.add(AvatarLayer(to, mouth.mix));
    } else if (mood == AvatarMood.thinking && t - _moodSince >= glanceDelay && has('mbp')) {
      layers.add(const AvatarLayer('mbp', 1));
    }

    // Breathing and a slow sway, plus the gesture.
    final live = mood == AvatarMood.speaking ? 1.0 : 0.7;
    return AvatarPose(
      layers: layers,
      // Breathing; the painter adds the zoom that hides the frame edges.
      scale: 1 + 0.004 * math.sin(2 * math.pi * t / 4.2),
      dx: 1.2 * live * math.sin(2 * math.pi * t / 7.3),
      dy: 0.8 * live * math.sin(2 * math.pi * t / 5.1 + 1) + _gestureDepth * g,
      rotation: 0.003 * live * math.sin(2 * math.pi * t / 6.1) + _gestureTilt * g + holdTilt,
      jaw: mood == AvatarMood.speaking ? jaw.clamp(0.0, 1.0) : 0,
    );
  }

  /// The last time passed to [frame] (to continue after a pause).
  double get lastTime => _lastT;
}
