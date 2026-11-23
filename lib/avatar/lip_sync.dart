import 'package:flutter/foundation.dart';

import '../models/coach.dart';
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
  const VisemeCue(this.viseme, this.start, this.end);
  final Viseme viseme;
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

  /// Crossfade between two open mouth shapes, seconds. Short, so teeth
  /// never ghost through lips; shapes with closed lips ([Viseme.closed])
  /// switch without a crossfade at all.
  static const double blend = 0.03;

  /// How far the mouth runs ahead of the word timing, seconds. Lips form a
  /// sound slightly before it is heard; the offline measurement showed the
  /// mouth trailing the audio by 66-99 ms without it. Tunable.
  static const double lead = 0.08;

  /// Longest time one mouth shape is held while speaking, seconds; longer
  /// stretches alternate between the full and half opening.
  static const double maxHold = 0.25;

  /// Openness jump above which a transition goes through a middle shape.
  static const double bridgeJump = 0.4;

  /// Length of that middle shape, seconds.
  static const double bridgeLength = 0.035;

  static double lettersPerSecond(double rate) => lettersPerSecondAtHalfRate * (rate.clamp(0.1, 1.0) / 0.5);

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
    return _bridge(_capHolds(cues));
  }

  /// No shape is held longer than [maxHold] while speaking: long vowels and
  /// consonants alternate between their full and half opening (a held "a"
  /// still moves, as real jaws do). Rest (a real pause) is left alone.
  static List<VisemeCue> _capHolds(List<VisemeCue> cues) {
    final out = <VisemeCue>[];
    for (final c in cues) {
      if (c.viseme == Viseme.rest || c.duration <= maxHold) {
        out.add(c);
        continue;
      }
      final n = (c.duration / 0.16).ceil();
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
      if (prev != null &&
          (prev.viseme.openness - c.viseme.openness).abs() > bridgeJump &&
          c.duration > bridgeLength * 2) {
        final mid = middle(prev.viseme, c.viseme);
        out.add(VisemeCue(mid, c.start, c.start + bridgeLength));
        out.add(VisemeCue(c.viseme, c.start + bridgeLength, c.end));
      } else {
        out.add(c);
      }
    }
    return out;
  }

  /// The shape between [a] and [b]: half-open, rounded if either is rounded.
  @visibleForTesting
  static Viseme middle(Viseme a, Viseme b) {
    final target = (a.openness + b.openness) / 2;
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
    if (prev.closed || cue.viseme.closed || prev == Viseme.rest || cue.viseme == Viseme.rest) {
      return VisemeSample(prev, cue.viseme, 1);
    }
    final b = blend < cue.duration * 0.5 ? blend : cue.duration * 0.5;
    final mix = b <= 0 ? 1.0 : ((t - cue.start) / b).clamp(0.0, 1.0);
    return VisemeSample(prev, cue.viseme, mix);
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
  }

  /// Audio started.
  void started() {
    if (_timeline == null) return;
    _anchorPlan = 0;
    _anchorNow = _now;
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
    if (t > tl.duration + 1.0) {
      // The completion callback never came (interrupted audio session):
      // stop instead of freezing on a half-open mouth.
      end();
      return null;
    }
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

  /// The mouth shape for this display frame, [VisemeTimeline.lead] ahead
  /// of the word timing.
  VisemeSample sample() {
    final t = planTime();
    if (t == null) return VisemeSample.rest;
    return _timeline!.sample(t + VisemeTimeline.lead);
  }
}

/// Implemented by a voice service that can time the avatar's mouth.
abstract interface class LipSyncSource {
  LipSyncDriver get lipSync;
}
