import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'lip_sync.dart';
import 'viseme.dart';

/// What the coach is doing on the voice stage.
enum AvatarMood {
  /// Waiting: blinks and breathes.
  idle,

  /// The user is talking: attentive: slow breathing, small backchannel
  /// nods, an easing head tilt, brief glances away and a soft smile.
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
  ///
  /// Blinks and speaking gestures draw from one seeded generator; the
  /// listening and thinking behavior (nods, tilt, glances, smile, sway
  /// phases) from a second one derived from the same seed, so adding it did
  /// not change the blink schedule of any seed.
  AvatarAnimator({required int seed})
      : _rng = math.Random(seed),
        _style = math.Random(seed ^ 0x5eed1157) {
    // The first blink comes at a random moment, not at a fixed time.
    _nextBlink = 1.5 + _rng.nextDouble() * 2.5;
    for (var i = 0; i < _phase.length; i++) {
      _phase[i] = _style.nextDouble() * 2 * math.pi;
    }
  }

  final math.Random _rng;
  final math.Random _style;
  final List<double> _phase = List.filled(9, 0);
  double _nextBlink = 2.2;
  double _blinkStart = -10;
  AvatarMood _mood = AvatarMood.idle;
  double _moodSince = 0;
  double _lastT = 0;
  bool _started = false;

  // The thinking glance is held until this time into speaking.
  double _gazeUntil = -10;

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

  // Smoothed state, so a change of mood never jumps the head.
  double _live = 0.7; // sway amplitude: 0.7 away from speech, 1 while speaking
  double _tilt = 0; // eased head tilt (radians)
  double _tiltTarget = 0;
  double _nextTilt = 0;
  double _smile = 0; // soft-smile opacity
  double _smileStart = -10, _smileLength = 0, _nextSmile = 0;

  // Listening: a queued second nod, and the glance away.
  double _secondNodAt = -10, _secondNodDepth = 0;
  double _glanceStart = -10, _glanceEnd = -10, _nextGlance = 0;
  bool _wasGlance = false;

  // Thinking tilt for this episode (signed, radians).
  double _thinkTilt = 0.011;

  // The breath before speech.
  double _breathStart = -10;

  final List<double> _nodStarts = [];
  final List<(double, double)> _glances = [];
  final List<double> _breaths = [];

  /// Start times of the listening nods (a double nod logs both), for tests.
  @visibleForTesting
  List<double> get nodStarts => List.unmodifiable(_nodStarts);

  /// (start, end) of each listening glance away, for tests.
  @visibleForTesting
  List<(double, double)> get glances => List.unmodifiable(_glances);

  /// Start times of the breath cue before speech, for tests.
  @visibleForTesting
  List<double> get breaths => List.unmodifiable(_breaths);

  /// A blink: half-closed 40 ms, shut 60 ms, half-open 50 ms (150 ms).
  static const double blinkLength = 0.15;

  /// Chance that a blink is followed by a second one.
  static const double doubleBlinkChance = 0.2;

  /// Listening nod: about 450 ms down and back, every 3-6 s.
  static const double nodLength = 0.45;

  /// Listening nods come this far apart (s): a double nod counts as one.
  static const double nodGapMin = 3.0, nodGapMax = 6.0;

  /// A listening nod is this deep (px), about 1.6-2.4.
  static const double nodDepthMin = 1.6, nodDepthMax = 2.4;

  /// Chance that a listening nod is a double nod.
  static const double doubleNodChance = 0.25;

  /// Largest listening head tilt (radians, about 0.57 degrees).
  static const double listenTiltMax = 0.010;

  /// A listening glance away lasts 0.3-0.9 s and comes every 4-9 s.
  static const double glanceMin = 0.3, glanceMax = 0.9;
  static const double glanceGapMin = 4.0, glanceGapMax = 9.0;

  /// The soft smile: i2 at no more than this opacity, for 1.5-3 s.
  static const double smileMax = 0.3;

  /// The breath cue: a tiny rise and settle of the head this long, starting
  /// when the mood turns to speaking (so it is over 150-250 ms before the
  /// first spoken frame whenever speech starts that much later).
  static const double breathLength = 0.22;
  static const double breathRise = 1.2;

  /// Thinking glance appears this long after thinking starts.
  static const double glanceDelay = 0.15;

  /// The thinking glance stays this long into speaking, so the eyes do not
  /// snap forward on the same frame the mouth starts moving.
  static const double gazeHold = 0.12;

  /// A think starts with a blink unless the last one began this recently.
  static const double onsetBlinkGap = 1.2;

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

  double _range(double a, double b) => a + _style.nextDouble() * (b - a);

  /// Two sines of different periods, normalized to [-1, 1].
  double _wave(double t, double p1, double p2, int i) =>
      0.65 * math.sin(2 * math.pi * t / p1 + _phase[i]) + 0.35 * math.sin(2 * math.pi * t / p2 + _phase[i + 1]);

  /// Moves [v] toward [target] with time constant [tau] (frame-rate independent).
  static double _ease(double v, double target, double tau, double dt) => v + (target - v) * (1 - math.exp(-dt / tau));

  void _enter(double t, AvatarMood mood) {
    // Leaving a thinking glance for speech: hold the glance a moment.
    final glancing = _mood == AvatarMood.thinking && t - _moodSince >= glanceDelay;
    _gazeUntil = glancing && mood == AvatarMood.speaking ? t + gazeHold : -10;
    final from = _mood;
    _mood = mood;
    _moodSince = t;
    _nextNod = t + 0.5;
    if (mood == AvatarMood.thinking) {
      _gesture(t, 0.6, 1.5, 0);
      // The eyes leave through a blink, as people's do on a large gaze shift.
      // The blink (150 ms) is over just as the glance frame appears
      // ([glanceDelay]), so no forward-eye frame plays over the glance. Without
      // it, a blink falling due while thinking waits for the whole think: on a
      // slow reply that was 4-6 s without a blink.
      if (t - _blinkStart >= onsetBlinkGap) {
        _blinkStart = t;
        _secondOfDouble = false;
        _nextBlink = t + 2.8 + _style.nextDouble() * 3.2;
      }
      _thinkTilt = (_style.nextBool() ? 1 : -1) * _range(0.010, 0.013);
    }
    if (mood == AvatarMood.listening) {
      // The first nod waits for something to nod at.
      _nextNod = t + _range(1.5, 3.0);
      _nextGlance = t + _range(2.5, glanceGapMax);
      _nextTilt = t + _range(0.8, 2.5);
      _nextSmile = t + _range(3.0, 8.0);
      _secondNodAt = -10;
    }
    if (mood == AvatarMood.speaking && from != AvatarMood.speaking) {
      _breathStart = t;
      _breaths.add(t);
    }
    if (mood != AvatarMood.listening) {
      _glanceEnd = math.min(_glanceEnd, t);
      _secondNodAt = -10;
    }
  }

  AvatarPose frame(double t, AvatarMood mood, VisemeSample mouth, {Set<String>? available, double jaw = 0}) {
    final dt = _started ? (t - _lastT).clamp(0.0, 0.25).toDouble() : 0.0;
    _lastT = t;
    if (!_started) {
      _started = true;
      _live = mood == AvatarMood.speaking ? 1.0 : 0.7;
    }
    if (mood != _mood) _enter(t, mood);
    bool has(String n) => available == null || available.contains(n);
    final layers = <AvatarLayer>[];
    final listening = mood == AvatarMood.listening;

    // Head gestures.
    if (listening && t >= _nextNod) {
      final depth = _range(nodDepthMin, nodDepthMax);
      _gesture(t, nodLength, depth, 0);
      _nodStarts.add(t);
      if (_style.nextDouble() < doubleNodChance) {
        _secondNodAt = t + nodLength + 0.1;
        _secondNodDepth = depth * 0.7;
      }
      _nextNod = t + _range(nodGapMin, nodGapMax);
    } else if (listening && _secondNodAt > 0 && t >= _secondNodAt) {
      _gesture(t, nodLength * 0.85, _secondNodDepth, 0);
      _nodStarts.add(t);
      _secondNodAt = -10;
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
    final depth = _gestureDepth * g;

    // Head tilt: eased toward its target, so mood changes never jump it.
    if (listening && t >= _nextTilt) {
      // Mostly a slight tilt toward the speaker that later eases back.
      final back = _tiltTarget.abs() > 0.002 || _style.nextDouble() < 0.25;
      _tiltTarget = back ? 0 : (_style.nextBool() ? 1 : -1) * _range(0.5, 1.0) * listenTiltMax;
      _nextTilt = t + (back ? _range(2.0, 5.0) : _range(4.0, 9.0));
    }
    final thinkingTilt = mood == AvatarMood.thinking && t - _moodSince >= 0.1;
    final target = thinkingTilt ? _thinkTilt : (listening ? _tiltTarget : 0.0);
    final tau = thinkingTilt ? 0.2 : (listening ? 1.1 : 0.4);
    _tilt = _ease(_tilt, target, tau, dt);

    _live = _ease(_live, mood == AvatarMood.speaking ? 1.0 : 0.7, 0.3, dt);

    // Glance away while listening: 0.3-0.9 s every 4-9 s, never over a blink
    // and never within 300 ms after one; a blink that falls due waits for it.
    final inBlink = t - _blinkStart < blinkLength + 0.3;
    if (listening && t >= _nextGlance && t >= _glanceEnd && !inBlink && t + 0.1 < _nextBlink) {
      final len = _range(glanceMin, glanceMax);
      _glanceStart = t;
      _glanceEnd = t + len;
      _glances.add((t, t + len));
      _nextGlance = t + _range(glanceGapMin, glanceGapMax);
    }
    final glanceAway = listening && t >= _glanceStart && t < _glanceEnd;
    if (_wasGlance && !glanceAway && _style.nextBool()) {
      // Half the glances end with a blink: the eyes return through it.
      _nextBlink = math.min(_nextBlink, t);
    }
    _wasGlance = glanceAway;

    // The thinking glance: while thinking, and briefly into speaking.
    final gazing = mood == AvatarMood.thinking || t < _gazeUntil || glanceAway;

    // Blinks (switched, not faded), with an occasional double blink. None
    // start during the glance (the blink frames look forward, so a blink
    // would flash the forward eyes mid-glance); a blink that falls due then
    // waits and plays as the glance ends, so the eyes return through it.
    if (t >= _nextBlink && !gazing) {
      _blinkStart = t;
      // Attentive listeners blink a little less.
      final base = listening ? 3.2 : 2.8;
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
    } else if (gazing && (mood != AvatarMood.thinking || t - _moodSince >= glanceDelay) && has('gaze')) {
      layers.add(const AvatarLayer('gaze', 1));
    }

    // A soft smile now and then while listening (a faint i2 over the rest
    // mouth), eased in and out; it fades over 200 ms when speech starts.
    if (listening && t >= _nextSmile && _smileLength == 0) {
      _smileStart = t;
      _smileLength = _range(1.5, 3.0);
    }
    var smile = 0.0;
    if (listening && _smileLength > 0) {
      final s = (t - _smileStart) / _smileLength;
      if (s >= 1) {
        _smileLength = 0;
        _nextSmile = t + _range(6.0, 14.0);
      } else {
        smile = smileMax * math.pow(math.sin(math.pi * s), 2).toDouble();
      }
    }
    if (!listening) {
      _smileLength = 0;
      smile = _smile * math.exp(-dt / 0.08);
    }
    _smile = smile;
    if (smile > 0.01 && has('i2')) layers.add(AvatarLayer('i2', smile));

    // Mouth: lip-synced while speaking; lips closed while thinking.
    if (mood == AvatarMood.speaking) {
      final from = mouth.from.asset, to = mouth.to.asset;
      if (from != null && has(from) && mouth.mix < 1) layers.add(AvatarLayer(from, to == null ? 1 - mouth.mix : 1));
      if (to != null && has(to) && mouth.mix > 0) layers.add(AvatarLayer(to, mouth.mix));
    } else if (mood == AvatarMood.thinking && t - _moodSince >= glanceDelay && has('mbp')) {
      layers.add(const AvatarLayer('mbp', 1));
    }

    // The breath before speech: a tiny rise of the head, then it settles.
    final breath = -breathRise * bump(t - _breathStart, breathLength);

    // Breathing (period drifts between about 3.8 and 5.5 s) and a slow
    // sway whose amplitude and period wander, so it never looks looped.
    final breathPhase = t / 4.6 + 0.25 * math.sin(2 * math.pi * t / 41 + _phase[8]);
    final mod1 = 0.85 + 0.15 * math.sin(2 * math.pi * t / 29 + _phase[6]);
    final mod2 = 0.85 + 0.15 * math.sin(2 * math.pi * t / 23 + _phase[7]);
    return AvatarPose(
      layers: layers,
      // Breathing; the painter adds the zoom that hides the frame edges.
      scale: 1 + 0.0035 * math.sin(2 * math.pi * breathPhase),
      dx: 1.2 * _live * mod1 * _wave(t, 7.3, 12.1, 0),
      dy: 0.8 * _live * mod2 * _wave(t, 5.1, 8.9, 2) + depth + breath,
      rotation: 0.003 * _live * mod1 * _wave(t, 6.1, 10.3, 4) + _gestureTilt * g + _tilt,
      jaw: mood == AvatarMood.speaking ? jaw.clamp(0.0, 1.0) : 0,
    );
  }

  /// The last time passed to [frame] (to continue after a pause).
  double get lastTime => _lastT;
}
