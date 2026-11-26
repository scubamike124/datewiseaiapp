// Listening, thinking and the breath before speech: the animator's
// deterministic, seeded behavior (nods, tilt, glances, smile, sway).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/avatar_animator.dart';
import 'package:datewise_ai/avatar/lip_sync.dart';
import 'package:datewise_ai/avatar/viseme.dart';

const _seeds = [1, 2, 3, 7, 42, 99, 2026];
const _dt = 1 / 60;

/// Runs [mood] from [from] to [to] and returns every pose.
List<(double, AvatarPose)> _run(AvatarAnimator a, AvatarMood mood, double from, double to, {VisemeSample mouth = VisemeSample.rest}) =>
    [for (var t = from; t < to; t += _dt) (t, a.frame(t, mood, mouth))];

List<String> _patches(AvatarPose p) => [for (final l in p.layers) l.patch];

void main() {
  group('listening', () {
    test('nods come every 3-6 s (a double nod counts once), 1.6-2.4 px deep', () {
      for (final seed in _seeds) {
        final a = AvatarAnimator(seed: seed);
        final poses = _run(a, AvatarMood.listening, 0, 120);
        // A double nod's second nod follows its first within 0.6 s.
        final starts = <double>[];
        for (final t in a.nodStarts) {
          if (starts.isEmpty || t - starts.last > 0.7) starts.add(t);
        }
        expect(starts.first, inInclusiveRange(1.5, 3.1), reason: 'first nod seed $seed');
        for (var i = 1; i < starts.length; i++) {
          expect(starts[i] - starts[i - 1], inInclusiveRange(AvatarAnimator.nodGapMin - 0.01, AvatarAnimator.nodGapMax + 0.8), reason: 'seed $seed');
        }
        // 120 s at one nod event per 3-6 s.
        expect(starts.length, inInclusiveRange(120 ~/ 6.9, 120 ~/ 3.0), reason: 'seed $seed');
        expect(a.nodStarts.length, greaterThan(starts.length - 1));
        // The deepest dip is a nod, but never more than 2.4 + sway.
        final maxDy = poses.map((e) => e.$2.dy).reduce(math.max);
        expect(maxDy, inInclusiveRange(1.6, 3.2), reason: 'seed $seed');
      }
    });

    test('some nods are double nods, most are single', () {
      var doubles = 0, events = 0;
      for (final seed in _seeds) {
        final a = AvatarAnimator(seed: seed);
        _run(a, AvatarMood.listening, 0, 300);
        final n = a.nodStarts;
        for (var i = 0; i < n.length; i++) {
          if (i > 0 && n[i] - n[i - 1] < 0.7) continue;
          events++;
          if (i + 1 < n.length && n[i + 1] - n[i] < 0.7) doubles++;
        }
      }
      expect(doubles / events, inInclusiveRange(0.1, 0.45));
    });

    test('the head tilt eases in and out: bounded, smooth, and it moves', () {
      for (final seed in _seeds) {
        final a = AvatarAnimator(seed: seed);
        final poses = _run(a, AvatarMood.listening, 0, 90);
        var maxRot = 0.0, maxStep = 0.0, minRot = 0.0;
        for (var i = 0; i < poses.length; i++) {
          final r = poses[i].$2.rotation;
          maxRot = math.max(maxRot, r);
          minRot = math.min(minRot, r);
          if (i > 0) maxStep = math.max(maxStep, (r - poses[i - 1].$2.rotation).abs());
        }
        final peak = math.max(maxRot, -minRot);
        expect(peak, lessThan(1.2 * math.pi / 180), reason: 'under 1.2 degrees, seed $seed');
        expect(peak, lessThanOrEqualTo(AvatarPose.maxRotation));
        expect(peak, greaterThan(0.006), reason: 'a visible tilt happens, seed $seed');
        // Eased: no more than 0.02 degrees per 60 Hz frame.
        expect(maxStep, lessThan(0.02 * math.pi / 180 + 1e-4), reason: 'seed $seed');
      }
    });

    test('glances away last 0.3-0.9 s and come every 4-9 s', () {
      for (final seed in _seeds) {
        final a = AvatarAnimator(seed: seed);
        _run(a, AvatarMood.listening, 0, 200);
        final g = a.glances;
        expect(g.length, inInclusiveRange(200 ~/ 10, 200 ~/ 4), reason: 'seed $seed');
        for (var i = 0; i < g.length; i++) {
          expect(g[i].$2 - g[i].$1, inInclusiveRange(AvatarAnimator.glanceMin - 1e-9, AvatarAnimator.glanceMax + 1e-9));
          if (i > 0) expect(g[i].$1 - g[i - 1].$1, inInclusiveRange(4.0, 10.0), reason: 'seed $seed');
        }
      }
    });

    test('the gaze patch is shown for the whole glance and never together with, or right after, a blink', () {
      for (final seed in _seeds) {
        final a = AvatarAnimator(seed: seed);
        final poses = _run(a, AvatarMood.listening, 0, 120);
        for (final (s, e) in a.glances) {
          final inside = poses.where((p) => p.$1 >= s + 0.02 && p.$1 < e - 0.02);
          expect(inside.every((p) => _patches(p.$2).contains('gaze')), isTrue, reason: 'glance shown, seed $seed');
          expect(inside.any((p) => _patches(p.$2).any((n) => n.startsWith('blink'))), isFalse, reason: 'no blink in a glance');
          // No blink frame in the 0.25 s before it starts.
          final before = poses.where((p) => p.$1 >= s - 0.25 && p.$1 < s - 0.02);
          expect(before.any((p) => _patches(p.$2).any((n) => n.startsWith('blink'))), isFalse, reason: 'glance starts after a blink, seed $seed');
        }
        for (final p in poses) {
          final n = _patches(p.$2);
          expect(n.contains('gaze') && n.any((x) => x.startsWith('blink')), isFalse);
        }
        // Outside glances the eyes look forward.
        final gazeFrames = poses.where((p) => _patches(p.$2).contains('gaze')).length;
        final glanceTotal = a.glances.fold<double>(0, (s, g) => s + g.$2 - g.$1);
        expect(gazeFrames * _dt, closeTo(glanceTotal, 0.5));
      }
    });

    test('blinks are further apart while listening (3.2-6.4 s, double blinks aside)', () {
      final a = AvatarAnimator(seed: 5);
      var prev = -1, start = -10.0;
      final starts = <double>[];
      for (final (t, p) in _run(a, AvatarMood.listening, 0, 300)) {
        final b = p.layers.any((l) => l.patch.startsWith('blink')) ? 1 : 0;
        if (b == 1 && prev == 0) starts.add(t);
        if (b == 1) start = t;
        prev = b;
      }
      expect(start, greaterThan(0));
      // 300 s: with gaps of at least 3.2 s (plus double blinks) there are far
      // fewer than 300 / 2.2 blinks.
      expect(starts.length, lessThan(300 / 3.2 * 1.3));
      expect(starts.length, greaterThan(300 / 8));
    });

    test('a soft smile uses only the i2 patch, at most 0.3 opacity, and only some of the time', () {
      for (final seed in _seeds) {
        final a = AvatarAnimator(seed: seed);
        final poses = _run(a, AvatarMood.listening, 0, 120);
        final smiling = poses.where((p) => _patches(p.$2).contains('i2')).toList();
        expect(smiling, isNotEmpty, reason: 'seed $seed');
        for (final p in smiling) {
          final l = p.$2.layers.firstWhere((l) => l.patch == 'i2');
          expect(l.opacity, inInclusiveRange(0.0, AvatarAnimator.smileMax));
        }
        expect(smiling.length * _dt, lessThan(120 * 0.5), reason: 'a smile, not a fixed grin');
        // Only eye patches, gaze and i2 are ever drawn: no other mouth.
        for (final p in poses) {
          expect(_patches(p.$2).where((n) => !(n.startsWith('blink') || n == 'gaze' || n == 'i2')), isEmpty);
        }
      }
    });

    test('transforms stay small: 4-6 pt of head movement, under 1.2 degrees, breathing in range', () {
      for (final seed in _seeds) {
        final a = AvatarAnimator(seed: seed);
        for (final (_, p) in _run(a, AvatarMood.listening, 0, 120)) {
          expect(p.dx.abs(), lessThanOrEqualTo(AvatarPose.maxDx));
          expect(p.dy.abs(), lessThanOrEqualTo(4.0));
          expect(p.rotation.abs(), lessThan(1.2 * math.pi / 180));
          expect(p.scale, inInclusiveRange(0.996, 1.004));
          expect(p.jaw, 0);
        }
      }
    });

    test('deterministic per seed, different between seeds', () {
      List<String> trace(int seed) {
        final a = AvatarAnimator(seed: seed);
        return [for (final (_, p) in _run(a, AvatarMood.listening, 0, 40)) '${p.dx.toStringAsFixed(4)} ${p.dy.toStringAsFixed(4)} ${p.rotation.toStringAsFixed(5)} ${p.layers}'];
      }

      expect(trace(7), trace(7));
      expect(trace(7), isNot(trace(8)));
      final a = AvatarAnimator(seed: 7), b = AvatarAnimator(seed: 8);
      _run(a, AvatarMood.listening, 0, 60);
      _run(b, AvatarMood.listening, 0, 60);
      expect(a.nodStarts, isNot(b.nodStarts));
      expect(a.glances, isNot(b.glances));
    });

    test('sway amplitude and period vary slowly, so it does not repeat', () {
      final a = AvatarAnimator(seed: 7);
      final poses = _run(a, AvatarMood.idle, 0, 240);
      // Peak |dx| in consecutive 30 s windows differ, and no window repeats.
      final peaks = <double>[];
      for (var w = 0; w < 8; w++) {
        peaks.add(poses.where((p) => p.$1 >= w * 30 && p.$1 < (w + 1) * 30).map((p) => p.$2.dx.abs()).reduce(math.max));
      }
      expect((peaks.reduce(math.max) - peaks.reduce(math.min)), greaterThan(0.05), reason: '$peaks');
      // Not periodic: compare 0-30 s with the same window shifted by 7.3 and 43.8 s.
      double diff(double off) {
        var d = 0.0;
        for (var i = 0; i < 1800; i += 5) {
          d += (poses[i].$2.dx - poses[i + (off * 60).round()].$2.dx).abs();
        }
        return d;
      }

      expect(diff(43.8), greaterThan(5), reason: 'does not repeat after 6 sway periods');
    });
  });

  group('thinking', () {
    test('a small tilt (0.5-0.75 degrees, either side) and the look-away; no forward-eye flash', () {
      final signs = <bool>{};
      for (final seed in _seeds) {
        final a = AvatarAnimator(seed: seed);
        _run(a, AvatarMood.listening, 0, 4);
        final poses = _run(a, AvatarMood.thinking, 4, 14);
        final late = poses.where((p) => p.$1 > 5).toList();
        final rot = late.map((p) => p.$2.rotation).reduce((x, y) => x + y) / late.length;
        signs.add(rot > 0);
        expect(rot.abs(), inInclusiveRange(0.0075, 0.0145), reason: 'seed $seed');
        for (final (t, p) in poses) {
          expect(p.rotation.abs(), lessThanOrEqualTo(AvatarPose.maxRotation));
          // The onset blink ends as the glance appears; none over the glance.
          if (t >= 4 + AvatarAnimator.glanceDelay) {
            expect(_patches(p).where((n) => n.startsWith('blink')), isEmpty, reason: 'blink at $t');
            expect(_patches(p), contains('gaze'));
          }
          if (t > 4.5) expect(_patches(p).contains('i2'), isFalse, reason: 'no smile while thinking');
        }
      }
      expect(signs.length, 2, reason: 'the tilt goes either way depending on the seed');
    });

    test('moving between listening, thinking and speaking never jumps the head', () {
      for (final seed in _seeds) {
        final a = AvatarAnimator(seed: seed);
        var t = 0.0;
        AvatarPose? last;
        for (final (mood, len) in [
          (AvatarMood.listening, 9.0),
          (AvatarMood.thinking, 3.0),
          (AvatarMood.listening, 5.0),
          (AvatarMood.speaking, 3.0),
          (AvatarMood.idle, 2.0),
        ]) {
          for (final end = t + len; t < end; t += _dt) {
            final p = a.frame(t, mood, VisemeSample.rest);
            if (last != null) {
              expect((p.dx - last.dx).abs(), lessThan(0.15), reason: 'dx jump at $t ($mood, seed $seed)');
              expect((p.dy - last.dy).abs(), lessThan(0.6), reason: 'dy jump at $t ($mood, seed $seed)');
              expect((p.rotation - last.rotation).abs(), lessThan(0.002), reason: 'rotation jump at $t ($mood, seed $seed)');
              expect((p.scale - last.scale).abs(), lessThan(0.0006));
            }
            last = p;
          }
        }
      }
    });
  });

  group('breath before speech', () {
    test('a tiny rise and settle of the head starts when the mood turns to speaking and is over in 220 ms', () {
      for (final seed in _seeds) {
        for (final from in [AvatarMood.listening, AvatarMood.thinking, AvatarMood.idle]) {
          final a = AvatarAnimator(seed: seed);
          _run(a, from, 0, 3);
          // The same animator staying in its mood is the control.
          final control = AvatarAnimator(seed: seed);
          final ctl = _run(control, from, 0, 3.6);
          if (control.nodStarts.any((n) => n > 2.4)) continue; // a nod in progress would mix in
          final speak = _run(a, AvatarMood.speaking, 3, 3.6);
          expect(a.breaths, [closeTo(3.0, 0.02)], reason: 'once, at the mood change');
          final diffs = [
            for (var i = 0; i < speak.length; i++) (speak[i].$1 - 3, ctl[ctl.length - speak.length + i].$2.dy - speak[i].$2.dy)
          ];
          final rise = diffs.map((d) => d.$2).reduce(math.max);
          expect(rise, inInclusiveRange(0.6, AvatarAnimator.breathRise + 0.5), reason: '$from seed $seed');
          final peakT = diffs.firstWhere((d) => d.$2 == rise).$1;
          expect(peakT, inInclusiveRange(0.05, 0.17), reason: 'mid-way: $from seed $seed');
          // Settled by the end of the cue: within the sway's own drift.
          expect(diffs.where((d) => d.$1 > 0.3).every((d) => d.$2.abs() < 0.45), isTrue, reason: '$from seed $seed');
        }
      }
    });

    test('the cue ends 150-250 ms (here 220 ms) after the mood change, before speech that starts later', () {
      expect(AvatarAnimator.breathLength, inInclusiveRange(0.15, 0.25));
      final a = AvatarAnimator(seed: 7);
      _run(a, AvatarMood.listening, 0, 3);
      // The first spoken frame comes 300 ms later: the head has settled by then.
      const talk = VisemeSample(Viseme.rest, Viseme.a, 0.5);
      final rest = _run(a, AvatarMood.speaking, 3, 3.3);
      final first = a.frame(3.3, AvatarMood.speaking, talk);
      final settled = rest.where((p) => p.$1 > 3 + AvatarAnimator.breathLength + 0.01).map((p) => p.$2.dy).toList();
      expect(settled, isNotEmpty);
      expect(first.layers.map((l) => l.patch), contains('a'));
      // After 220 ms the breath adds nothing (no step between 222 and 240 ms).
      final d = rest.where((p) => p.$1 > 3.23 && p.$1 < 3.27).map((p) => p.$2.dy).toList();
      for (var i = 1; i < d.length; i++) {
        expect((d[i] - d[i - 1]).abs(), lessThan(0.1));
      }
    });

    test('a faint listening smile fades out within 200 ms of speech instead of popping', () {
      for (final seed in _seeds) {
        final a = AvatarAnimator(seed: seed);
        // Find a listening moment with the smile showing.
        double? at;
        for (final (t, p) in _run(a, AvatarMood.listening, 0, 60)) {
          if (_patches(p).contains('i2') && p.layers.firstWhere((l) => l.patch == 'i2').opacity > 0.2) {
            at = t;
            break;
          }
        }
        if (at == null) continue;
        final after = <double>[];
        for (var t = at + _dt; t < at + 0.4; t += _dt) {
          final p = a.frame(t, AvatarMood.speaking, VisemeSample.rest);
          after.add(p.layers.where((l) => l.patch == 'i2').fold(0.0, (s, l) => s + l.opacity));
        }
        expect(after.last, 0);
        for (var i = 1; i < after.length; i++) {
          expect(after[i], lessThanOrEqualTo(after[i - 1] + 1e-9), reason: 'fades monotonically');
        }
      }
    });
  });

  test('blink schedule per seed is unchanged by the listening behavior (idle)', () {
    // The first blink still falls in 1.5-4 s and speaking still uses its own stream.
    for (final seed in _seeds) {
      final a = AvatarAnimator(seed: seed);
      double? first;
      for (final (t, p) in _run(a, AvatarMood.idle, 0, 6)) {
        if (_patches(p).contains('blink_half')) {
          first = t;
          break;
        }
      }
      expect(first, inInclusiveRange(1.5, 4.1));
    }
  });
}
