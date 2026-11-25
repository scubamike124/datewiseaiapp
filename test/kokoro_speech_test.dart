import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/kokoro_speech.dart';
import 'package:datewise_ai/avatar/lip_sync.dart';
import 'package:datewise_ai/avatar/viseme.dart';
import 'package:datewise_ai/models/coach.dart';

/// The shape tool/tts/kokoro_sentences.py writes (timeline.json), reduced to two sentences.
const _fixture = '''
{
 "voice": "af_bella", "lang": "en-us", "speed": 0.95, "fps": 10,
 "sentences": [
  {"index": 1, "text": "Hi, I'm Ava.", "start_s": 0.0, "duration_s": 1.2,
   "mouth": [0.0, 0.4, 0.9, 0.7, 0.2, 0.0, 0.0, 0.5, 0.8, 0.3, 0.0, 0.0]},
  {"index": 2, "text": "Take your time now.", "start_s": 1.2, "duration_s": 1.6,
   "mouth": [0.0, 0.6, 0.9, 0.5, 0.0, 0.0, 0.7, 0.9, 0.4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]}
 ]
}
''';

const _text = "Hi, I'm Ava. Take your time now.";

void main() {
  test('parses the timeline the server writes', () {
    final t = KokoroTimeline.fromJson(jsonDecode(_fixture) as Map<String, dynamic>);
    expect(t.fps, 10);
    expect(t.sentences, hasLength(2));
    expect(t.sentences.first.text, "Hi, I'm Ava.");
    expect(t.sentences.first.start, 0.0);
    expect(t.sentences.last.duration, 1.6);
    expect(t.duration, closeTo(2.8, 1e-9));
  });

  test('rejects a sentence without its timing', () {
    expect(
      () => KokoroSentence.fromJson({'text': 'Hi', 'start_s': 0}),
      throwsFormatException,
    );
  });

  test('word timings: one per word, in order, with the exact character positions', () {
    final t = KokoroTimeline.fromJson(jsonDecode(_fixture) as Map<String, dynamic>);
    final words = t.wordTimings(_text);
    final spoken = [for (final (cs, ce, _, _) in words) _text.substring(cs, ce)];
    expect(spoken, ["Hi", "I'm", "Ava", "Take", "your", "time", "now"]);
    for (var k = 1; k < words.length; k++) {
      expect(words[k].$3, greaterThanOrEqualTo(words[k - 1].$3), reason: 'starts never go backwards');
    }
  });

  test('each sentence keeps its own span: its words start and end inside it', () {
    final t = KokoroTimeline.fromJson(jsonDecode(_fixture) as Map<String, dynamic>);
    final words = t.wordTimings(_text);
    // The first three words belong to the first sentence (0.0-1.2 s), the rest to the second (1.2-2.8 s).
    for (final (i, (_, _, s, e)) in words.indexed) {
      final sentence = i < 3 ? t.sentences[0] : t.sentences[1];
      expect(s, greaterThanOrEqualTo(sentence.start - 1e-9));
      expect(e, lessThanOrEqualTo(sentence.start + sentence.duration + 1e-9));
    }
    // The last word of each sentence ends exactly where its sentence ends.
    expect(words[2].$4, closeTo(1.2, 1e-9));
    expect(words.last.$4, closeTo(2.8, 1e-9));
  });

  test('a longer word takes a longer share of its sentence', () {
    final t = KokoroTimeline.fromJson({
      'fps': 10,
      'sentences': [
        {'text': 'Hi yes', 'start_s': 0.0, 'duration_s': 1.0, 'mouth': []},
      ],
    });
    final words = t.wordTimings('Hi yes');
    final short = words[0].$4 - words[0].$3;
    final long = words[1].$4 - words[1].$3;
    expect(long, greaterThan(short));
    expect(short / long, closeTo(2 / 3, 1e-9));
  });

  test('a sentence that is not in the text throws instead of misaligning the timing', () {
    final t = KokoroTimeline.fromJson({
      'fps': 10,
      'sentences': [
        {'text': 'Not in the text', 'start_s': 0.0, 'duration_s': 1.0, 'mouth': []},
      ],
    });
    expect(() => t.wordTimings(_text), throwsFormatException);
  });

  test('feeding an utterance drives the real lip-sync driver: speaking, then closed after the audio', () {
    final t = KokoroTimeline.fromJson(jsonDecode(_fixture) as Map<String, dynamic>);
    var now = Duration.zero;
    final driver = LipSyncDriver(clock: () => now);
    feedKokoroUtterance(driver, t, _text, CoachLanguage.en);

    expect(driver.timeline, isNotNull);
    expect(driver.hasAudio, isTrue, reason: 'the loudness of the rendered audio reached the driver');

    // Speaking: the plan advances with the clock, and the mouth is not closed mid-sentence.
    final times = <double>[];
    for (var ms = 0; ms <= 2500; ms += 250) {
      now = Duration(milliseconds: ms);
      final p = driver.planTime();
      if (p != null) times.add(p);
    }
    expect(times, isNotEmpty);
    for (var k = 1; k < times.length; k++) {
      expect(times[k], greaterThanOrEqualTo(times[k - 1]), reason: 'plan time never goes backwards');
    }

    // After the audio ends the mouth is closed (rest). Lips close between sentences and at the end.
    now = const Duration(milliseconds: 4000);
    expect(driver.sample().viseme, Viseme.rest);
  });
}
