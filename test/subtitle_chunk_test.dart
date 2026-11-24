import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/widgets/subtitle_chunk.dart';

void main() {
  const reply = 'Great question. Start with something specific from their profile instead of a generic hello, '
      'because it shows you actually looked, and keep it to one question.\n\nTry this: ask about one photo! Done?';

  test('a short sentence is one subtitle', () {
    expect(subtitleAt(reply, 0), 'Great question.');
    expect(firstSubtitle(reply), 'Great question.');
  });

  test('the subtitle follows the character being spoken, one sentence at a time', () {
    expect(subtitleAt(reply, reply.indexOf('Try this')), 'Try this: ask about one photo!');
    expect(subtitleAt(reply, reply.indexOf('Done')), 'Done?');
    expect(subtitleAt(reply, reply.length + 50), 'Done?', reason: 'past the end: the last one');
  });

  test('a long sentence is cut at its commas into pieces that fit, and the piece with the word is shown', () {
    final spans = subtitleSpans(reply, maxChars: 60);
    for (final s in spans) {
      expect(s.end - s.start, lessThanOrEqualTo(60));
    }
    final at = reply.indexOf('actually');
    final shown = subtitleAt(reply, at, maxChars: 60);
    expect(shown, contains('actually'));
    expect(shown.length, lessThanOrEqualTo(60));
  });

  test('every character of the reply is in exactly one subtitle or is whitespace between them', () {
    for (final max in [24, 40, 96]) {
      final spans = subtitleSpans(reply, maxChars: max);
      var prevEnd = 0;
      final covered = StringBuffer();
      for (final s in spans) {
        expect(s.start, greaterThanOrEqualTo(prevEnd), reason: 'no overlap');
        expect(reply.substring(prevEnd, s.start).trim(), isEmpty, reason: 'only whitespace is skipped');
        covered.write(reply.substring(s.start, s.end));
        prevEnd = s.end;
      }
      expect(reply.substring(prevEnd).trim(), isEmpty);
      expect(covered.toString().replaceAll(RegExp(r'\s+'), ''), reply.replaceAll(RegExp(r'\s+'), ''));
    }
  });

  test('a word longer than the limit and empty text do not break it', () {
    expect(subtitleAt('', 0), '');
    expect(subtitleAt('   \n ', 3), '');
    final longWord = 'a' * 300;
    for (final s in subtitleSpans(longWord, maxChars: 50)) {
      expect(s.end - s.start, lessThanOrEqualTo(50));
    }
  });

  test('Spanish punctuation and newlines end a sentence', () {
    const es = '¿Qué sabes de esa persona? Cuéntame más.\nTu paso de hoy: envía un mensaje.';
    expect(subtitleAt(es, 0), '¿Qué sabes de esa persona?');
    expect(subtitleAt(es, es.indexOf('Tu paso')), 'Tu paso de hoy: envía un mensaje.');
  });
}
