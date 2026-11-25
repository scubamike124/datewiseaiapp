import 'package:flutter/foundation.dart';

import '../models/coach.dart';
import 'lip_sync.dart';

/// Server-rendered Kokoro speech, one sentence at a time (tool/tts/kokoro_sentences.py, timeline.json).
///
/// Kokoro returns audio only: no word or phoneme times. So word times are derived from the measured duration of each
/// sentence, shared between its words by letter count (the same rule the planner uses), and the audio's own loudness
/// (the mouth curve) is passed to the driver as the native path's loudness. The mouth shapes still come from the
/// viseme plan ([VisemeTimeline]), not from openness alone.
@immutable
class KokoroSentence {
  const KokoroSentence({required this.text, required this.start, required this.duration, required this.mouth});

  /// The sentence as sent to the synthesizer (a substring of the utterance text).
  final String text;

  /// Seconds from the start of the utterance.
  final double start;

  /// Seconds of audio for this sentence.
  final double duration;

  /// Mouth openness 0..1, one value per frame of [KokoroTimeline.fps].
  final List<double> mouth;

  factory KokoroSentence.fromJson(Map<String, dynamic> j) {
    final text = j['text'];
    final start = j['start_s'];
    final duration = j['duration_s'];
    final mouth = j['mouth'];
    if (text is! String || start is! num || duration is! num || mouth is! List) {
      throw const FormatException('kokoro sentence: text, start_s, duration_s and mouth are required');
    }
    return KokoroSentence(
      text: text,
      start: start.toDouble(),
      duration: duration.toDouble(),
      mouth: [for (final v in mouth) (v as num).toDouble()],
    );
  }
}

/// A whole rendered utterance.
@immutable
class KokoroTimeline {
  const KokoroTimeline({required this.sentences, this.fps = 10});

  final List<KokoroSentence> sentences;

  /// Frames per second of each sentence's [KokoroSentence.mouth] curve.
  final int fps;

  double get duration => sentences.isEmpty ? 0 : sentences.last.start + sentences.last.duration;

  factory KokoroTimeline.fromJson(Map<String, dynamic> j) {
    final list = j['sentences'];
    if (list is! List) throw const FormatException('kokoro timeline: sentences is required');
    final fps = j['fps'] is num ? (j['fps'] as num).toInt() : 10;
    if (fps <= 0) throw const FormatException('kokoro timeline: fps must be positive');
    return KokoroTimeline(
      sentences: [for (final s in list) KokoroSentence.fromJson(s as Map<String, dynamic>)],
      fps: fps,
    );
  }

  static final _word = RegExp(r"[\p{L}\p{N}][\p{L}\p{N}'’]*", unicode: true);

  /// Word timings over [text]: (charStart, charEnd, start, end), seconds from the start of the utterance.
  ///
  /// Each sentence's measured span is shared between its words by letter count, so a long word takes longer than a
  /// short one. Sentences must appear in [text] in order; a sentence that is not found throws, because the timing
  /// would otherwise be applied to the wrong characters.
  List<(int, int, double, double)> wordTimings(String text) {
    final out = <(int, int, double, double)>[];
    var cursor = 0;
    for (final s in sentences) {
      final at = text.indexOf(s.text, cursor);
      if (at < 0) {
        throw FormatException('kokoro sentence not found in the utterance text: ${s.text}');
      }
      cursor = at + s.text.length;
      final words = _word.allMatches(s.text).toList();
      if (words.isEmpty) continue;
      final letters = [for (final m in words) m.group(0)!.replaceAll(RegExp(r"['’]"), '').length.clamp(1, 1 << 20)];
      final total = letters.fold<int>(0, (a, b) => a + b);
      var acc = 0;
      for (var k = 0; k < words.length; k++) {
        final m = words[k];
        final from = s.start + s.duration * acc / total;
        acc += letters[k];
        final to = s.start + s.duration * acc / total;
        out.add((at + m.start, at + m.end, from, to));
      }
    }
    return out;
  }
}

/// Feeds one rendered utterance to [driver] the way the native audio path does: the plan for [text], audio started,
/// the loudness of each sentence, a marker for every word, then complete. [text] must be the exact text that was
/// rendered, so the character positions line up.
void feedKokoroUtterance(LipSyncDriver driver, KokoroTimeline timeline, String text, CoachLanguage language, {double rate = 0.5}) {
  final words = timeline.wordTimings(text);
  driver.begin(text, language, rate: rate);
  driver.started();
  final hop = 1 / timeline.fps;
  for (final s in timeline.sentences) {
    if (s.mouth.isNotEmpty) driver.addLevels(s.start, hop, s.mouth);
  }
  for (final (cs, _, t, _) in words) {
    driver.addMarker(cs, t);
  }
  driver.audioComplete();
}
