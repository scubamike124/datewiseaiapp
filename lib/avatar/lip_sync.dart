import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/coach.dart';
import 'speech_audio.dart';
import 'speech_pace.dart';
import 'viseme.dart';

/// A word of the utterance: its character range in the spoken text and its
/// planned start and length (seconds from the start of speech).
@immutable
class PlannedWord {
  const PlannedWord(this.text, this.charStart, this.charEnd, this.start, this.duration, this.segments);
  final String text;
  final int charStart;
  final int charEnd;
  final double start;
  final double duration;
  final List<VisemeSegment> segments;
  double get end => start + duration;
}

/// One mouth shape on the timeline (seconds).
@immutable
class VisemeCue {
  const VisemeCue(this.viseme, this.start, this.end, {this.bridge = false});
  final Viseme viseme;

  /// A short transitional shape between closed lips and an open mouth.
  final bool bridge;
  final double start;
  final double end;
  double get duration => end - start;
  @override
  String toString() => '${viseme.name}[${start.toStringAsFixed(3)}-${end.toStringAsFixed(3)}]';
}

/// What the mouth shows at one instant: a crossfade from [from] to [to].
@immutable
class VisemeSample {
  const VisemeSample(this.from, this.to, this.mix);
  static const rest = VisemeSample(Viseme.rest, Viseme.rest, 1);
  final Viseme from;
  final Viseme to;

  /// 0 = all [from], 1 = all [to].
  final double mix;

  /// The dominant shape.
  Viseme get viseme => mix >= 0.5 ? to : from;
  @override
  String toString() => '${from.name}->${to.name}@${mix.toStringAsFixed(2)}';
}

/// The planned mouth-shape timeline of one utterance.
///
/// Word lengths are estimated from the letters and the coach's speech rate,
/// with pauses at punctuation. While speaking, [LipSyncDriver] re-anchors the
/// plan to the word-start events that iOS reports, so the estimate only has
/// to be right *within* a word.
class VisemeTimeline {
  VisemeTimeline._(this.text, this.words, this.cues);

  final String text;
  final List<PlannedWord> words;
  final List<VisemeCue> cues;

  double get duration => cues.isEmpty ? 0 : cues.last.end;

  static final _word = RegExp(r"[\p{L}\p{N}][\p{L}\p{N}'’]*", unicode: true);

  /// Letters spoken per second at flutter_tts rate 0.5 (iOS default rate,
  /// about 165 words a minute). Scaled linearly with the rate.
  static const double lettersPerSecondAtHalfRate = 13.5;

  /// Crossfade between mouth shapes, seconds. Zero: every change is a hard
  /// switch between two whole photos (a crossfade shows teeth through lips
  /// for a frame), and large changes go through a middle shape instead.
  static const double blend = 0.0;

  /// How far the mouth runs ahead of the word timing, seconds. Lips form a
  /// sound slightly before it is heard; the offline measurement showed the
  /// mouth trailing the audio by 66-99 ms without it. Tunable.
  static const double lead = 0.08;

  /// Longest time one mouth shape is held while speaking, seconds; longer
  /// stretches alternate between the full and half opening.
  static const double maxHold = 0.45;

  /// Openness jump above which a transition goes through a middle shape.
  static const double bridgeJump = 0.4;

  /// Length of that middle shape, seconds (= [minShape]).
  static const double bridgeLength = 0.06;

  /// Shortest time any mouth shape stays on screen, seconds (measured in
  /// time, not frames): shorter ones are merged into a neighbour.
  static const double minShape = 0.12;

  /// Most shape changes allowed in any one second of the plan (natural
  /// speech is about 4-6; the old plan reached 14-15).
  static const int maxChangesPerSecond = 8;

  /// The plan is thinned to this before the middle shapes (bridges) and
  /// alternating holds add their own changes.
  static const int plannedChangesPerSecond = 5;

  /// Consonant shapes dropped from the plan: the mouth keeps the vowel
  /// openings, lip closures (m b p), lip-teeth (f v) and the rounded sh.
  static const Set<Viseme> minorShapes = {Viseme.cons, Viseme.l, Viseme.th};

  /// Two open shapes closer than this in openness (same rounding) are one.
  static const double nearOpenness = 0.2;

  /// A middle shape is only inserted if the shape after it still lasts this
  /// long; otherwise the change is a plain switch.
  static const double minAfterBridge = minShape;

  static double lettersPerSecond(double rate) => SpeechPace.lettersPerSecond(rate);

  /// Plans [text] in [language] at flutter_tts speech [rate].
  factory VisemeTimeline.plan(String text, CoachLanguage language, {double rate = 0.5}) {
    final mapper = VisemeMapper.of(language);
    final lps = lettersPerSecond(rate);
    final words = <PlannedWord>[];
    var t = 0.0;
    var last = 0;
    final matches = _word.allMatches(text).toList();
    for (var k = 0; k < matches.length; k++) {
      final m = matches[k];
      t += _pauseBetween(text.substring(last, m.start), words.isEmpty);
      final w = m.group(0)!;
      final segs = mapper.word(w, next: _nextWord(text, matches, k));
      final letters = w.replaceAll(RegExp(r"['’]"), '').length;
      // Short words still take a syllable's time.
      final dur = (letters / lps).clamp(0.12, 2.0);
      words.add(PlannedWord(w, m.start, m.end, t, dur, segs));
      t += dur;
      last = m.end;
    }
    return VisemeTimeline._(text, words, _cues(words));
  }

  /// Builds a timeline from measured word timings (tests, the demo renderer,
  /// and the iOS 16 marker path): (text, charStart, charEnd, start, end).
  factory VisemeTimeline.fromTimedWords(
      String text, CoachLanguage language, List<(int, int, double, double)> timed) {
    final mapper = VisemeMapper.of(language);
    final words = <PlannedWord>[];
    for (var k = 0; k < timed.length; k++) {
      final (cs, ce, s, e) = timed[k];
      // The next word only matters when no pause separates them.
      String? next;
      if (k + 1 < timed.length && !RegExp(r'[.,;:!?…—–]').hasMatch(text.substring(ce, timed[k + 1].$1))) {
        next = text.substring(timed[k + 1].$1, timed[k + 1].$2);
      }
      words.add(PlannedWord(text.substring(cs, ce), cs, ce, s, e - s, mapper.word(text.substring(cs, ce), next: next)));
    }
    return VisemeTimeline._(text, words, _cues(words));
  }

  static String? _nextWord(String text, List<RegExpMatch> m, int k) {
    if (k + 1 >= m.length) return null;
    if (RegExp(r'[.,;:!?…—–\n]').hasMatch(text.substring(m[k].end, m[k + 1].start))) return null;
    return m[k + 1].group(0);
  }

  static double _pauseBetween(String gap, bool first) {
    if (first) return 0;
    if (RegExp(r'[.!?…]').hasMatch(gap)) return 0.42;
    if (RegExp(r'[,;:—–]').hasMatch(gap)) return 0.2;
    if (gap.contains('\n')) return 0.3;
    return 0.035;
  }

  static List<VisemeCue> _cues(List<PlannedWord> words) {
    final cues = <VisemeCue>[];
    for (var k = 0; k < words.length; k++) {
      final w = words[k];
      if (cues.isNotEmpty && w.start - cues.last.end > 0.12) {
        cues.add(VisemeCue(Viseme.rest, cues.last.end, w.start));
      } else if (cues.isNotEmpty && w.start > cues.last.end) {
        // A short gap between words: hold the last shape (no flicker).
        final last = cues.removeLast();
        cues.add(VisemeCue(last.viseme, last.start, w.start));
      } else if (cues.isEmpty && w.start > 0) {
        cues.add(VisemeCue(Viseme.rest, 0, w.start));
      }
      final total = w.segments.fold<double>(0, (a, s) => a + s.weight);
      if (total == 0) {
        cues.add(VisemeCue(Viseme.cons, w.start, w.end));
        continue;
      }
      var t = w.start;
      for (final s in w.segments) {
        final d = w.duration * s.weight / total;
        cues.add(VisemeCue(s.viseme, t, t + d));
        t += d;
      }
    }
    if (cues.isNotEmpty) cues.add(VisemeCue(Viseme.rest, cues.last.end, cues.last.end + 0.2));
    final simple = _capHolds(_limitRate(_mergeShort(_stretchClosures(_simplify(cues))), plannedChangesPerSecond));
    return _capHolds(_collapse(_limitRate(_mergeShort(_bridge(simple)))));
  }


  /// Fewer, clearer shapes: minor consonants are absorbed by the neighbouring
  /// vowel, equal or near-identical neighbours become one, keeping lip
  /// closures and clear vowel openings.
  static List<VisemeCue> _simplify(List<VisemeCue> cues) {
    var out = List<VisemeCue>.of(cues);
    // 1. absorb minor consonants into the closer-in-openness neighbour.
    for (var k = 0; k < out.length; k++) {
      final c = out[k];
      if (!minorShapes.contains(c.viseme)) continue;
      final prev = k > 0 && out[k - 1].viseme != Viseme.rest ? out[k - 1] : null;
      final next = k + 1 < out.length && out[k + 1].viseme != Viseme.rest ? out[k + 1] : null;
      if (prev == null && next == null) continue;
      double gap(VisemeCue? n) => n == null ? 1e9 : (n.viseme.openness - c.viseme.openness).abs();
      if (gap(prev) <= gap(next)) {
        out[k - 1] = VisemeCue(prev!.viseme, prev.start, c.end);
      } else {
        out[k + 1] = VisemeCue(next!.viseme, c.start, next.end);
      }
      out.removeAt(k);
      k--;
    }
    // 2. merge equal and near-identical neighbours (not closures, not rest).
    bool near(Viseme a, Viseme b) =>
        a == b ||
        (a != Viseme.rest &&
            b != Viseme.rest &&
            !a.closed &&
            !b.closed &&
            a.rounded == b.rounded &&
            (a.openness - b.openness).abs() < nearOpenness);
    var changed = true;
    while (changed) {
      changed = false;
      for (var k = 1; k < out.length; k++) {
        final a = out[k - 1], b = out[k];
        if (!near(a.viseme, b.viseme)) continue;
        final keep = a.viseme == b.viseme || a.duration >= b.duration ? a.viseme : b.viseme;
        out[k - 1] = VisemeCue(keep, a.start, b.end);
        out.removeAt(k);
        changed = true;
        break;
      }
    }
    return out;
  }

  /// Merges the shortest minor cue in any window with more than
  /// [maxChangesPerSecond] shape changes into a neighbour (never one that
  /// would put closed lips next to an open mouth without a middle step).
  static List<VisemeCue> _limitRate(List<VisemeCue> cues, [int limit = maxChangesPerSecond]) {
    final out = List<VisemeCue>.of(cues);
    for (var guard = 0; guard < 2000; guard++) {
      final starts = [for (var i = 1; i < out.length; i++) if (out[i].viseme != out[i - 1].viseme) (i, out[i].start)];
      int? worstFrom;
      for (var a = 0; a < starts.length && worstFrom == null; a++) {
        var n = 0;
        for (var b = a; b < starts.length && starts[b].$2 < starts[a].$2 + 1.0; b++) {
          n++;
        }
        if (n > limit) worstFrom = a;
      }
      if (worstFrom == null) break;
      final lo = starts[worstFrom].$2;
      int? best;
      for (var i = 1; i < out.length - 1; i++) {
        final c = out[i];
        if (c.start < lo - 1e-9 || c.start >= lo + 1.0) continue;
        if (c.viseme == Viseme.rest || c.viseme == Viseme.mbp) continue;
        final prev = out[i - 1], next = out[i + 1];
        if (prev.viseme == Viseme.rest && next.viseme == Viseme.rest) continue;
        if (needsBridge(prev.viseme, next.viseme)) continue;
        // Never grow a neighbour past the longest allowed hold.
        final room = (prev.viseme != Viseme.rest && prev.duration + c.duration <= maxHold) ||
            (next.viseme != Viseme.rest && next.duration + c.duration <= maxHold);
        if (!room) continue;
        if (best == null || c.duration < out[best].duration) best = i;
      }
      if (best == null) break;
      final c = out[best];
      final prev = out[best - 1], next = out[best + 1];
      double gap(VisemeCue n) =>
          n.viseme == Viseme.rest || n.duration + c.duration > maxHold ? 1e9 : (n.viseme.openness - c.viseme.openness).abs();
      if (gap(prev) <= gap(next)) {
        out[best - 1] = VisemeCue(prev.viseme, prev.start, c.end, bridge: prev.bridge);
      } else {
        out[best + 1] = VisemeCue(next.viseme, c.start, next.end, bridge: next.bridge);
      }
      out.removeAt(best);
      // Equal neighbours after the merge become one.
      for (var k = out.length - 1; k > 0; k--) {
        if (out[k].viseme == out[k - 1].viseme) {
          out[k - 1] = VisemeCue(out[k].viseme, out[k - 1].start, out[k].end, bridge: out[k - 1].bridge && out[k].bridge);
          out.removeAt(k);
        }
      }
    }
    return out;
  }

  /// Lip closures (m, b, p) are never dropped: one shorter than [minShape]
  /// takes the missing time from the cue after it (or before it).
  static List<VisemeCue> _stretchClosures(List<VisemeCue> cues) {
    final out = List<VisemeCue>.of(cues);
    for (var k = 0; k < out.length; k++) {
      final c = out[k];
      if (c.viseme != Viseme.mbp || c.duration >= minShape) continue;
      final need = minShape - c.duration;
      if (k + 1 < out.length && out[k + 1].viseme != Viseme.rest && out[k + 1].duration > need) {
        final n = out[k + 1];
        out[k] = VisemeCue(c.viseme, c.start, c.end + need);
        out[k + 1] = VisemeCue(n.viseme, n.start + need, n.end);
      } else if (k > 0 && out[k - 1].viseme != Viseme.rest && out[k - 1].duration > need) {
        final p = out[k - 1];
        out[k] = VisemeCue(c.viseme, c.start - need, c.end);
        out[k - 1] = VisemeCue(p.viseme, p.start, p.end - need);
      }
    }
    return out;
  }

  /// Equal neighbours become one cue (a bridge only merges with a bridge).
  static List<VisemeCue> _collapse(List<VisemeCue> cues) {
    final out = <VisemeCue>[];
    for (final c in cues) {
      if (out.isNotEmpty && out.last.viseme == c.viseme) {
        out[out.length - 1] = VisemeCue(c.viseme, out.last.start, c.end, bridge: out.last.bridge && c.bridge);
      } else {
        out.add(c);
      }
    }
    return out;
  }

  /// Merges every mouth shape shorter than [minShape] into the neighbour
  /// closest in openness (not into a pause), so nothing flashes.
  static List<VisemeCue> _mergeShort(List<VisemeCue> cues) {
    final out = List<VisemeCue>.of(cues);
    var changed = true;
    while (changed) {
      changed = false;
      for (var k = 0; k < out.length; k++) {
        final c = out[k];
        if (c.viseme == Viseme.rest || c.bridge || c.viseme == Viseme.mbp || c.duration >= minShape - 1e-9) continue;
        final prev = k > 0 && out[k - 1].viseme != Viseme.rest ? out[k - 1] : null;
        final next = k + 1 < out.length && out[k + 1].viseme != Viseme.rest ? out[k + 1] : null;
        if (prev == null && next == null) continue;
        double gap(VisemeCue? n) => n == null ? 1e9 : (n.viseme.openness - c.viseme.openness).abs();
        if (gap(prev) <= gap(next)) {
          out[k - 1] = VisemeCue(prev!.viseme, prev.start, c.end);
        } else {
          out[k + 1] = VisemeCue(next!.viseme, c.start, next.end);
        }
        out.removeAt(k);
        changed = true;
        break;
      }
    }
    return out;
  }

  /// No shape is held longer than [maxHold] while speaking: long vowels and
  /// consonants alternate between their full and half opening (a held "a"
  /// still moves, as real jaws do). Rest (a real pause) is left alone.
  static List<VisemeCue> _capHolds(List<VisemeCue> cues) {
    final out = <VisemeCue>[];
    for (final c in cues) {
      if (c.viseme == Viseme.rest || c.duration <= maxHold + 1e-6) {
        out.add(c);
        continue;
      }
      final n = (c.duration / 0.25).ceil();
      final d = c.duration / n;
      final alt = c.viseme.isVowel
          ? (c.viseme.half == c.viseme ? c.viseme.full : c.viseme.half)
          : (c.viseme.closed ? Viseme.u2 : Viseme.e2);
      for (var k = 0; k < n; k++) {
        out.add(VisemeCue(k.isEven ? c.viseme : alt, c.start + k * d, c.start + (k + 1) * d));
      }
    }
    return out;
  }

  /// A big jump in openness (closed lips to a wide "a") goes through a short
  /// middle shape, as a real mouth does, instead of a crossfade that would
  /// show teeth through the lips.
  static List<VisemeCue> _bridge(List<VisemeCue> cues) {
    final out = <VisemeCue>[];
    for (var k = 0; k < cues.length; k++) {
      final c = cues[k];
      final prev = out.isEmpty ? null : out.last;
      if (prev != null && needsBridge(prev.viseme, c.viseme)) {
        // Always, however short the cue (the steps take at most 2/3 of it):
        // closed lips first part to the smallest opening, then to a middle
        // opening if the jump is still large.
        final steps = <Viseme>[];
        var cur = prev.viseme;
        while (steps.length < 2 && needsBridge(cur, c.viseme)) {
          final mid = (cur.closed || c.viseme.closed) ? smallestOpen(cur, c.viseme) : middle(cur, c.viseme);
          if (mid == cur || mid == c.viseme) break;
          steps.add(mid);
          cur = mid;
        }
        const len = bridgeLength;
        // Out of a pause the mouth forms the shape slightly early: the
        // middle steps take the end of the rest instead of the shape.
        var stealFromRest = false;
        if (prev.viseme == Viseme.rest) {
          final room = ((prev.duration - 0.02) / len).floor();
          if (room > 0) {
            while (steps.length > room) {
              steps.removeLast();
            }
            stealFromRest = true;
          }
        }
        while (!stealFromRest && steps.isNotEmpty && c.duration - steps.length * len < minAfterBridge) {
          steps.removeLast();
        }
        var t = c.start;
        if (stealFromRest && steps.isNotEmpty) {
          t = c.start - steps.length * len;
          out[out.length - 1] = VisemeCue(Viseme.rest, prev.start, t);
        }
        for (final m in steps) {
          out.add(VisemeCue(m, t, t + len, bridge: true));
          t += len;
        }
        out.add(VisemeCue(c.viseme, t, c.end));
      } else {
        out.add(c);
      }
    }
    return out;
  }

  /// Closed lips next to an open (or teeth-showing) mouth, or a large jump in
  /// openness: such a change goes through a middle shape.
  static bool needsBridge(Viseme a, Viseme b) {
    if (a == b) return false;
    if (a.closed != b.closed) {
      // The just-parted shapes (i2, sh) are the step itself; the smiling
      // rest shows teeth, so it is bridged too.
      final open = a.closed ? b : a;
      return open == Viseme.rest || open.openness > 0.3;
    }
    return (a.openness - b.openness).abs() > bridgeJump;
  }

  /// The first opening step from closed lips: just parted (rounded if
  /// either side is rounded).
  @visibleForTesting
  static Viseme smallestOpen(Viseme a, Viseme b) => (a.rounded || b.rounded) ? Viseme.sh : Viseme.i2;

  /// The shape between [a] and [b]: half-open, rounded if either is rounded.
  @visibleForTesting
  static Viseme middle(Viseme a, Viseme b) {
    final target = (a.openness + b.openness) / 2;
    // Never a closed shape (the bridge is the half-open step between).
    final pool = (a.rounded || b.rounded)
        ? const [Viseme.u, Viseme.o2, Viseme.sh]
        : const [Viseme.i2, Viseme.e2, Viseme.cons, Viseme.a2, Viseme.e];
    var best = pool.first;
    for (final v in pool) {
      if ((v.openness - target).abs() < (best.openness - target).abs()) best = v;
    }
    return best;
  }

  int _cueIndex(double t) {
    var lo = 0, hi = cues.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cues[mid].start <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The mouth at time [t] (seconds on this timeline): a [blend]-second
  /// crossfade into each new open shape, a hard switch when either shape
  /// has closed lips (no teeth showing through the lips).
  VisemeSample sample(double t) {
    if (cues.isEmpty || t < 0 || t >= duration) return VisemeSample.rest;
    final k = _cueIndex(t);
    final cue = cues[k];
    final prev = k > 0 ? cues[k - 1].viseme : Viseme.rest;
    if (blend <= 0 || prev.closed || cue.viseme.closed || prev == Viseme.rest || cue.viseme == Viseme.rest) {
      return VisemeSample(prev, cue.viseme, 1);
    }
    final b = blend < cue.duration * 0.5 ? blend : cue.duration * 0.5;
    final mix = b <= 0 ? 1.0 : ((t - cue.start) / b).clamp(0.0, 1.0);
    return VisemeSample(prev, cue.viseme, mix);
  }

  /// Synthetic jaw opening at time [t] when no audio loudness is known:
  /// within each vowel a bump from 0 up to the vowel's openness and back;
  /// consonants keep a slight opening; rest is closed.
  double jawAt(double t) {
    if (cues.isEmpty || t < 0 || t >= duration) return 0;
    final c = cues[_cueIndex(t)];
    if (c.viseme == Viseme.rest) return 0;
    if (!c.viseme.isVowel) return 0.15 * c.viseme.openness;
    final phase = ((t - c.start) / c.duration).clamp(0.0, 1.0);
    return c.viseme.openness * (0.35 + 0.65 * math.sin(math.pi * phase));
  }

  /// Index of the word starting at [charStart] (or containing it), else -1.
  int wordAtChar(int charStart) {
    for (var k = 0; k < words.length; k++) {
      if (words[k].charEnd > charStart) return k;
    }
    return -1;
  }
}

/// Drives the mouth while a coach speaks.
///
/// [VoiceService] calls [begin] with the exact text it hands to the speech
/// synthesizer, [started] when audio starts, [word] for every word-start event
/// (flutter_tts `setProgressHandler`, from AVSpeechSynthesizer's
/// `willSpeakRangeOfSpeechString`), and [end] when it stops. The avatar polls
/// [sample] once per display frame.
///
/// Without word events (a voice or platform that does not send them) the
/// plan runs on its own clock. With events, each one moves the plan so that
/// word starts *now*, and the measured pace corrects the speed of the rest.
class LipSyncDriver extends ChangeNotifier {
  LipSyncDriver({Duration Function()? clock}) : _clock = clock ?? _stopwatchClock();

  static Duration Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  final Duration Function() _clock;
  VisemeTimeline? _timeline;
  bool _active = false;
  bool _sawWord = false;

  // Mapping: plan time = _anchorPlan + (now - _anchorNow) * _speed.
  double _anchorPlan = 0;
  double _anchorNow = 0;
  double _speed = 1;
  int _anchorWord = -1;

  // Audio path (lib/avatar/speech_audio.dart): loudness and audio timing.
  AudioAlignment? _audio;
  double _startNow = 0;

  /// True between [started] and [end].
  bool get active => _active;
  VisemeTimeline? get timeline => _timeline;

  double get _now => _clock().inMicroseconds / 1e6;

  /// The utterance about to be spoken.
  void begin(String text, CoachLanguage language, {double rate = 0.5}) {
    _timeline = VisemeTimeline.plan(text, language, rate: rate);
    _sawWord = false;
    _anchorWord = -1;
    _speed = 1;
    _audio = AudioAlignment(_timeline!);
  }

  /// Loudness of the audio being played (from the native audio path),
  /// [hop] seconds per value from audio time [t0]. Audio time 0 is [started].
  void addLevels(double t0, double hop, List<double> values) => _audio?.addLevels(t0, hop, values);

  /// A word marker from the native audio path (iOS 17): the word at
  /// [charStart] starts at audio time [t].
  void addMarker(int charStart, double t) => _audio?.addMarker(charStart, t);

  /// All of the utterance's loudness has arrived.
  void audioComplete() => _audio?.complete();

  /// True once loudness from the real audio is available.
  bool get hasAudio => _audio?.hasLevels ?? false;

  double get _audioTime => _now - _startNow;

  /// Audio started. [latency]: how much later than now it is heard (the
  /// native path reports the output route's latency).
  void started({double latency = 0}) {
    if (_timeline == null) return;
    _anchorPlan = 0;
    _anchorNow = _now + latency;
    _startNow = _anchorNow;
    if (!_active) {
      _active = true;
      notifyListeners();
    }
  }

  /// The synthesizer is about to say the word at [charStart]..[charEnd].
  void word(int charStart, int charEnd) {
    final tl = _timeline;
    if (tl == null) return;
    if (!_active) started();
    final k = tl.wordAtChar(charStart);
    if (k < 0) return;
    final now = _now;
    final planned = tl.words[k].start;
    if (_anchorWord >= 0 && k > _anchorWord) {
      // Measured pace between the two events vs. the plan, smoothed.
      final plannedGap = planned - tl.words[_anchorWord].start;
      final actualGap = now - _anchorNow;
      if (plannedGap > 0.05 && actualGap > 0.05) {
        final measured = (plannedGap / actualGap).clamp(0.5, 2.0);
        _speed = _speed * 0.6 + measured * 0.4;
      }
    }
    _sawWord = true;
    _anchorWord = k;
    _anchorPlan = planned;
    _anchorNow = now;
  }

  /// Speech finished or was stopped.
  void end() {
    if (_active) {
      _active = false;
      notifyListeners();
    }
  }

  /// Current plan time (seconds), or null when not speaking.
  double? planTime() {
    final tl = _timeline;
    if (!_active || tl == null) return null;
    var t = _anchorPlan + (_now - _anchorNow) * _speed;
    // The completion callback never came (interrupted audio session): stop
    // instead of freezing on a half-open mouth. Until a word event or the
    // real audio confirms the pace, the plan is only an estimate, so allow
    // up to twice its length before giving up.
    final confirmed = _sawWord || hasAudio;
    final limit = confirmed ? tl.duration + 1.0 : tl.duration * 2 + 2.0;
    if (t > limit) {
      end();
      return null;
    }
    final audioPlan = _audio?.planTime(_audioTime);
    if (audioPlan != null) return audioPlan;
    if (_sawWord && _anchorWord >= 0) {
      // Never run more than a little past the current word's end before
      // the next word event arrives: hold a closing mouth instead.
      final w = tl.words[_anchorWord];
      final next = _anchorWord + 1 < tl.words.length ? tl.words[_anchorWord + 1].start : tl.duration;
      final limit = (w.end + 0.08) < next ? w.end + 0.08 : next;
      if (t > limit && _anchorWord + 1 < tl.words.length) t = limit;
    }
    return t;
  }

  Viseme _shown = Viseme.rest;
  double _shownSince = -1e9;

  /// The shape for this display frame, held for at least
  /// [VisemeTimeline.minShape] (by time) before it may change.
  VisemeSample sample() {
    final want = _sample();
    final now = _now;
    if (want.to == _shown) return want;
    if (now - _shownSince < VisemeTimeline.minShape && _active) {
      return VisemeSample(_shown, _shown, 1);
    }
    _shown = want.to;
    _shownSince = now;
    return want;
  }

  /// The mouth shape for this display frame, [VisemeTimeline.lead] ahead
  /// of the word timing. With the real audio, the loudness picks the vowel's
  /// opening (full when loud, half when soft), and the mouth never shows
  /// rest while the audio is audible.
  VisemeSample _sample() {
    final t = planTime();
    if (t == null) return VisemeSample.rest;
    final a = _audio;
    if (a == null || !a.hasLevels) return _timeline!.sample(t + VisemeTimeline.lead);
    final s = _timeline!.sample(t + audioLead);
    final at = _audioTime + audioLead;
    final lvl = a.level(at);
    // Lip closures sit on the dips of the loudness (closed lips silence the
    // voice); a planned closure that missed its dip shows parted lips.
    if (a.inClosure(at)) return const VisemeSample(Viseme.mbp, Viseme.mbp, 1);
    Viseme pick(Viseme v) {
      if (v == Viseme.mbp) return Viseme.i2;
      // Never the still resting face while the audio is audible.
      if (v == Viseme.rest) return lvl > audibleLevel ? Viseme.cons : v;
      if (!v.isVowel) return v;
      return lvl > loudLevel ? v.full : v.half;
    }
    return VisemeSample(pick(s.from), pick(s.to), s.mix);
  }

  /// Loudness (fraction of the utterance's peak) above which a vowel gets
  /// its full opening.
  static const double loudLevel = 0.45;

  /// Loudness above which the audio counts as audible.
  static const double audibleLevel = 0.15;

  /// Lead of the mouth over the audio when it follows the real audio,
  /// seconds. Smaller than [VisemeTimeline.lead] (which compensates the
  /// estimated word timing): the offline simulation put the mouth 56 ms
  /// ahead of the loudness with the 80 ms lead.
  static const double audioLead = 0.03;

  /// How far the jaw drops for this display frame, 0..1: the loudness of the
  /// audio when the native audio path provides it, else a per-syllable
  /// envelope from the plan (rises and falls within every vowel), so the
  /// mouth always visibly moves while speaking.
  double jaw() {
    final t = planTime();
    final tl = _timeline;
    if (t == null || tl == null) return 0;
    final a = _audio;
    if (a != null && a.hasLevels) {
      final at = _audioTime + audioLead;
      if (a.inClosure(at)) return 0;
      final lvl = a.level(at);
      return ((lvl - 0.08) / 0.75).clamp(0.0, 1.0);
    }
    return tl.jawAt(t + VisemeTimeline.lead);
  }
}

/// Implemented by a voice service that can time the avatar's mouth.
abstract interface class LipSyncSource {
  LipSyncDriver get lipSync;
}
