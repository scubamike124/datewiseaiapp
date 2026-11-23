// Talking avatar: spelling-to-mouth-shape rules (EN/ES), the timeline, and
// the driver that follows the synthesizer's word events.

import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/lip_sync.dart';
import 'package:datewise_ai/avatar/viseme.dart';
import 'package:datewise_ai/models/coach.dart';

List<Viseme> en(String w) => VisemeMapper.english.word(w).map((s) => s.viseme).toList();
List<Viseme> es(String w) => VisemeMapper.spanish.word(w).map((s) => s.viseme).toList();

void main() {
  const V = Viseme.values;
  group('Spanish spelling to mouth shapes', () {
    test('vowels and lip consonants', () {
      expect(es('mamá'), [Viseme.mbp, Viseme.a, Viseme.mbp, Viseme.a]);
      expect(es('oso'), [Viseme.o, Viseme.cons, Viseme.o]);
      expect(es('luna'), [Viseme.l, Viseme.u, Viseme.cons, Viseme.a]);
    });
    test('b and v are the same sound (lips together); f is lip-to-teeth', () {
      expect(es('vida').first, Viseme.mbp);
      expect(es('bien').first, Viseme.mbp);
      expect(es('foto').first, Viseme.fv);
    });
    test('silent h and the u of que/gui; ll, rr and ch are one sound', () {
      expect(es('hola'), [Viseme.o, Viseme.l, Viseme.a]);
      expect(es('que'), [Viseme.cons, Viseme.e]);
      expect(es('guitarra'), [Viseme.cons, Viseme.i, Viseme.cons, Viseme.a, Viseme.cons, Viseme.a]);
      expect(es('calle'), [Viseme.cons, Viseme.a, Viseme.cons, Viseme.e]);
      expect(es('chico'), [Viseme.cons, Viseme.i, Viseme.cons, Viseme.o]);
    });
    test('accents fold, y alone is the vowel i, soft d between vowels', () {
      expect(es('Sofía'), [Viseme.cons, Viseme.o, Viseme.fv, Viseme.i, Viseme.a]);
      expect(es('y'), [Viseme.i]);
      expect(es('nada'), [Viseme.cons, Viseme.a, Viseme.th, Viseme.a]);
      expect(es('límites'), [Viseme.l, Viseme.i, Viseme.mbp, Viseme.i, Viseme.cons, Viseme.e, Viseme.cons]);
    });
  });

  group('English spelling to mouth shapes', () {
    test('digraphs: th, sh, ph, oo, ee', () {
      expect(en('the'), [Viseme.th, Viseme.e]);
      expect(en('think').first, Viseme.th);
      expect(en('photo').first, Viseme.fv);
      expect(en('mood'), [Viseme.mbp, Viseme.u, Viseme.cons]);
      expect(en('feel'), [Viseme.fv, Viseme.i, Viseme.l]);
    });
    test('silent final e, collapsed doubles, common irregular words', () {
      expect(en('make'), [Viseme.mbp, Viseme.a, Viseme.cons]);
      expect(en('happy'), [Viseme.cons, Viseme.a, Viseme.mbp, Viseme.i]);
      expect(en('you'), [Viseme.i, Viseme.u]);
      expect(en("I'm"), [Viseme.a, Viseme.i, Viseme.mbp]);
      expect(en('I’m'), [Viseme.a, Viseme.i, Viseme.mbp], reason: 'curly apostrophe');
    });
    test('punctuation is ignored and every word yields at least one shape', () {
      for (final w in ['Hi,', 'date.', 'okay!', 'x', 'rhythm', 'strengths']) {
        expect(VisemeMapper.english.word(w), isNotEmpty, reason: w);
      }
      expect(en('date.'), en('date'));
    });
  });

  test('every mouth shape but rest has a patch name; openness is ordered sensibly', () {
    for (final v in V) {
      expect(v.asset == null, v == Viseme.rest);
    }
    expect(Viseme.mbp.openness, lessThan(Viseme.i.openness));
    expect(Viseme.a.openness, greaterThan(Viseme.o.openness));
    expect(VisemeMapper.of(CoachLanguage.es), same(VisemeMapper.spanish));
    expect(VisemeMapper.of(CoachLanguage.en), same(VisemeMapper.english));
  });

  group('timeline', () {
    test('cues are contiguous, start at 0 and end at rest', () {
      final tl = VisemeTimeline.plan('Hola, soy Sofía. ¿Cómo estás?', CoachLanguage.es);
      expect(tl.words.map((w) => w.text), ['Hola', 'soy', 'Sofía', 'Cómo', 'estás']);
      expect(tl.cues.first.start, 0);
      for (var i = 1; i < tl.cues.length; i++) {
        expect(tl.cues[i].start, closeTo(tl.cues[i - 1].end, 1e-9));
      }
      expect(tl.cues.last.viseme, Viseme.rest);
    });

    test('pauses at punctuation become rest; the speech rate scales lengths', () {
      final tl = VisemeTimeline.plan('Hi. Ready?', CoachLanguage.en);
      final gap = tl.words[1].start - tl.words[0].end;
      expect(gap, greaterThan(0.3));
      expect(tl.sample(tl.words[0].end + gap / 2).viseme, Viseme.rest);
      final slow = VisemeTimeline.plan('Confidence is a skill', CoachLanguage.en, rate: 0.4);
      final fast = VisemeTimeline.plan('Confidence is a skill', CoachLanguage.en, rate: 0.6);
      expect(slow.duration, greaterThan(fast.duration));
    });

    test('sample crossfades into each shape over 60 ms', () {
      final tl = VisemeTimeline.fromTimedWords('mamá', CoachLanguage.es, [(0, 4, 0.0, 0.8)]);
      final c = tl.cues;
      expect(c.map((x) => x.viseme), [Viseme.mbp, Viseme.a, Viseme.mbp, Viseme.a, Viseme.rest]);
      final s = tl.sample(c[1].start + 0.03);
      expect((s.from, s.to), (Viseme.mbp, Viseme.a));
      expect(s.mix, closeTo(0.5, 0.01));
      expect(tl.sample(c[1].start + 0.07).mix, 1);
      expect(tl.sample(-1).viseme, Viseme.rest);
      expect(tl.sample(5).viseme, Viseme.rest);
    });

    test('measured word times are kept exactly', () {
      const text = 'Be clear about it';
      final tl = VisemeTimeline.fromTimedWords(text, CoachLanguage.en, [(0, 2, 0.1, 0.3), (3, 8, 0.35, 0.8), (9, 14, 0.9, 1.3), (15, 17, 1.35, 1.5)]);
      expect(tl.words.map((w) => w.start), [0.1, 0.35, 0.9, 1.35]);
      expect(tl.sample(0.12).to, Viseme.mbp);
      expect(tl.sample(0.05).viseme, Viseme.rest);
    });
  });

  group('driver', () {
    late Duration now;
    late LipSyncDriver d;
    setUp(() {
      now = Duration.zero;
      d = LipSyncDriver(clock: () => now);
    });

    test('silent until started, rest after end, and notifies on both', () {
      var n = 0;
      d.addListener(() => n++);
      d.begin('Hola, soy Diego.', CoachLanguage.es, rate: 0.46);
      expect(d.active, isFalse);
      expect(d.sample().viseme, Viseme.rest);
      d.started();
      expect(d.active, isTrue);
      now = const Duration(milliseconds: 100);
      expect(d.sample().viseme, isNot(Viseme.rest));
      d.end();
      expect(d.sample().viseme, Viseme.rest);
      expect(n, 2);
    });

    test('free-runs on the plan without word events', () {
      d.begin('Hello there', CoachLanguage.en);
      d.started();
      final tl = d.timeline!;
      now = Duration(microseconds: (tl.words[1].start * 1e6).round() + 20000);
      expect(d.planTime(), closeTo(tl.words[1].start + 0.02, 1e-6));
    });

    test('each word event re-anchors the plan to that word', () {
      const text = 'Keep it simple and suggest coffee';
      d.begin(text, CoachLanguage.en);
      d.started();
      final tl = d.timeline!;
      // The synthesizer is slower than planned: word 3 starts at 1.5 s.
      now = const Duration(milliseconds: 1500);
      d.word(text.indexOf('and'), text.indexOf('and') + 3);
      expect(d.planTime(), closeTo(tl.words[3].start, 1e-6));
      now = const Duration(milliseconds: 1550);
      expect(d.planTime(), closeTo(tl.words[3].start + 0.05, 0.03));
    });

    test('waits at the end of a word for the next event instead of running ahead', () {
      const text = 'Slow words here';
      d.begin(text, CoachLanguage.en);
      d.started();
      d.word(0, 4);
      final tl = d.timeline!;
      now = const Duration(seconds: 5);
      expect(d.planTime(), lessThanOrEqualTo(tl.words[0].end + 0.081));
      d.word(5, 10);
      expect(d.planTime(), closeTo(tl.words[1].start, 1e-6));
    });

    test('adapts its speed to the measured pace', () {
      const text = 'one two three four five six seven eight';
      d.begin(text, CoachLanguage.en);
      d.started();
      final tl = d.timeline!;
      // Speech runs at half the planned speed.
      for (var k = 0; k < 6; k++) {
        now = Duration(microseconds: (tl.words[k].start * 2 * 1e6).round());
        final w = tl.words[k];
        d.word(w.charStart, w.charEnd);
      }
      final t0 = d.planTime()!;
      now += const Duration(milliseconds: 100);
      expect(d.planTime()! - t0, lessThan(0.08), reason: 'slowed down towards 0.5x');
    });
  });
}
