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
    test('vowels, lip consonants and the stressed syllable (full vs half opening)', () {
      expect(es('mamá'), [Viseme.mbp, Viseme.a2, Viseme.mbp, Viseme.a], reason: 'written accent');
      expect(es('oso'), [Viseme.o, Viseme.cons, Viseme.o2], reason: 'ends in a vowel: second-last');
      expect(es('luna'), [Viseme.l, Viseme.u, Viseme.cons, Viseme.a2]);
      expect(es('verdad'), [Viseme.mbp, Viseme.e2, Viseme.cons, Viseme.a, Viseme.th], reason: 'ends in d: last');
    });
    test('b and v are the same sound (lips together); f is lip-to-teeth', () {
      expect(es('vida').first, Viseme.mbp);
      expect(es('bien').first, Viseme.mbp);
      expect(es('foto').first, Viseme.fv);
    });
    test('n before b, v, p, m closes the lips, inside a word and across words', () {
      expect(es('envía'), [Viseme.e2, Viseme.mbp, Viseme.i, Viseme.a]);
      expect(es('gran'), [Viseme.cons, Viseme.a, Viseme.cons]);
      expect(VisemeMapper.spanish.word('gran', next: 'paso').map((s) => s.viseme).last, Viseme.mbp);
      expect(VisemeMapper.spanish.word('un', next: 'beso').map((s) => s.viseme).last, Viseme.mbp);
      expect(VisemeMapper.spanish.word('un', next: 'café').map((s) => s.viseme).last, Viseme.cons);
    });
    test('silent h and the u of que/gui; ll, rr are one sound; ch pushes the lips forward', () {
      expect(es('hola'), [Viseme.o, Viseme.l, Viseme.a2]);
      expect(es('que'), [Viseme.cons, Viseme.e2], reason: 'unstressed function word');
      expect(es('guitarra'), [Viseme.cons, Viseme.i2, Viseme.cons, Viseme.a, Viseme.cons, Viseme.a2]);
      expect(es('calle'), [Viseme.cons, Viseme.a, Viseme.cons, Viseme.e2]);
      expect(es('chico'), [Viseme.sh, Viseme.i, Viseme.cons, Viseme.o2]);
    });
    test('accents fold, y alone is the vowel i, soft d between vowels', () {
      expect(es('Sofía'), [Viseme.cons, Viseme.o2, Viseme.fv, Viseme.i, Viseme.a]);
      expect(es('y'), [Viseme.i2]);
      expect(es('nada'), [Viseme.cons, Viseme.a, Viseme.th, Viseme.a2]);
      expect(es('límites'), [Viseme.l, Viseme.i, Viseme.mbp, Viseme.i2, Viseme.cons, Viseme.e2, Viseme.cons]);
    });
  });

  group('English spelling to mouth shapes', () {
    test('digraphs: th, sh, ch, ph, oo, ee', () {
      expect(en('the'), [Viseme.th, Viseme.e2]);
      expect(en('think').first, Viseme.th);
      expect(en('photo').first, Viseme.fv);
      expect(en('shop').first, Viseme.sh);
      expect(en('mood'), [Viseme.mbp, Viseme.u, Viseme.cons]);
      expect(en('feel'), [Viseme.fv, Viseme.i, Viseme.l]);
    });
    test('first-syllable stress, -tion stress, unstressed function words', () {
      expect(en('make'), [Viseme.mbp, Viseme.a, Viseme.cons]);
      expect(en('happy'), [Viseme.cons, Viseme.a, Viseme.mbp, Viseme.i2]);
      expect(en('nation'), [Viseme.cons, Viseme.a, Viseme.sh, Viseme.e2, Viseme.cons]);
      expect(en('you'), [Viseme.i2, Viseme.u2]);
      expect(en("I'm"), [Viseme.a2, Viseme.i2, Viseme.mbp]);
      expect(en('I’m'), en("I'm"), reason: 'curly apostrophe');
    });
    test('punctuation is ignored and every word yields at least one shape', () {
      for (final w in ['Hi,', 'date.', 'okay!', 'x', 'rhythm', 'strengths']) {
        expect(VisemeMapper.english.word(w), isNotEmpty, reason: w);
      }
      expect(en('date.'), en('date'));
    });
  });

  test('16 mouth shapes plus rest; half and full variants pair up; openness is ordered', () {
    expect(V.where((v) => v.asset != null), hasLength(16));
    for (final v in V) {
      expect(v.asset == null, v == Viseme.rest);
      if (v.isVowel) {
        expect(v.full.half, v.half);
        expect(v.half.openness, lessThanOrEqualTo(v.full.openness));
      }
    }
    expect(Viseme.mbp.openness, lessThan(Viseme.i2.openness));
    expect(Viseme.a.openness, greaterThan(Viseme.o.openness));
    expect(VisemeMapper.of(CoachLanguage.es), same(VisemeMapper.spanish));
    expect(VisemeMapper.of(CoachLanguage.en), same(VisemeMapper.english));
  });

  group('timeline', () {
    const texts = {
      CoachLanguage.en: "Hi, I'm Ava. Your profile already shows warmth. Change one thing: lead with a specific story.",
      CoachLanguage.es: 'Hola, soy Sofía. Diste un gran paso al escribirle. Esta noche, envía un mensaje honesto.',
    };

    for (final e in texts.entries) {
      test('${e.key.name}: contiguous cues, no shape held over 250 ms while speaking, no closed/open crossfade', () {
        final tl = VisemeTimeline.plan(e.value, e.key, rate: 0.45);
        expect(tl.cues.first.start, 0);
        for (var i = 1; i < tl.cues.length; i++) {
          final a = tl.cues[i - 1], b = tl.cues[i];
          expect(b.start, closeTo(a.end, 1e-9));
          // Crossfaded (open-to-open) transitions stay small; closed lips snap.
          if (b.viseme != Viseme.rest && a.viseme != Viseme.rest && !a.viseme.closed && !b.viseme.closed && b.duration > 0.07) {
            expect((a.viseme.openness - b.viseme.openness).abs(), lessThanOrEqualTo(0.6),
                reason: 'big jumps go through a middle shape: $a -> $b');
          }
        }
        for (final c in tl.cues.where((c) => c.viseme != Viseme.rest)) {
          expect(c.duration, lessThanOrEqualTo(VisemeTimeline.maxHold + 1e-9), reason: '$c');
        }
        // Sample every 5 ms: a closed shape is never partly mixed with another.
        for (var t = 0.0; t < tl.duration; t += 0.005) {
          final s = tl.sample(t);
          if (s.from.closed || s.to.closed) expect(s.mix, 1, reason: '$s at $t');
        }
        expect(tl.cues.last.viseme, Viseme.rest);
      });
    }

    test('pauses at punctuation become rest; the speech rate scales lengths', () {
      final tl = VisemeTimeline.plan('Hi. Ready?', CoachLanguage.en);
      final gap = tl.words[1].start - tl.words[0].end;
      expect(gap, greaterThan(0.3));
      expect(tl.sample(tl.words[0].end + gap / 2).viseme, Viseme.rest);
      final slow = VisemeTimeline.plan('Confidence is a skill', CoachLanguage.en, rate: 0.4);
      final fast = VisemeTimeline.plan('Confidence is a skill', CoachLanguage.en, rate: 0.6);
      expect(slow.duration, greaterThan(fast.duration));
    });

    test('open shapes crossfade over 30 ms', () {
      final tl = VisemeTimeline.fromTimedWords('ella', CoachLanguage.es, [(0, 4, 0.0, 0.4)]);
      final k = tl.cues.indexWhere((c) => c.viseme == Viseme.a2 || c.viseme == Viseme.a);
      final c = tl.cues[k];
      final s = tl.sample(c.start + 0.015);
      expect(s.to, c.viseme);
      expect(s.mix, closeTo(0.5, 0.01));
      expect(tl.sample(c.start + 0.031).mix, 1);
      expect(tl.sample(-1).viseme, Viseme.rest);
      expect(tl.sample(5).viseme, Viseme.rest);
    });

    test('middle shape is half-open, and rounded next to a rounded shape', () {
      expect(VisemeTimeline.middle(Viseme.mbp, Viseme.a).openness, inInclusiveRange(0.3, 0.7));
      expect(VisemeTimeline.middle(Viseme.mbp, Viseme.o).rounded, isTrue);
    });

    test('measured word times are kept exactly; "gran paso" closes the lips across the words', () {
      const text = 'Be clear about it';
      final tl = VisemeTimeline.fromTimedWords(text, CoachLanguage.en, [(0, 2, 0.1, 0.3), (3, 8, 0.35, 0.8), (9, 14, 0.9, 1.3), (15, 17, 1.35, 1.5)]);
      expect(tl.words.map((w) => w.start), [0.1, 0.35, 0.9, 1.35]);
      expect(tl.sample(0.12).to, Viseme.mbp);
      expect(tl.sample(0.05).viseme, Viseme.rest);
      const es2 = 'gran paso';
      final t2 = VisemeTimeline.fromTimedWords(es2, CoachLanguage.es, [(0, 4, 0, 0.3), (5, 9, 0.3, 0.7)]);
      expect(t2.words[0].segments.last.viseme, Viseme.mbp);
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
      now = const Duration(milliseconds: 1500);
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

    test('the mouth runs 80 ms ahead of the word timing', () {
      const text = 'Mmm okay';
      d.begin(text, CoachLanguage.en);
      d.started();
      final tl = d.timeline!;
      now = const Duration(milliseconds: 50);
      expect(d.sample().to, tl.sample(0.05 + VisemeTimeline.lead).to);
      expect(VisemeTimeline.lead, closeTo(0.08, 1e-9));
    });

    test('ends by itself 1 s after the plan if no completion callback arrives', () {
      d.begin('Short one', CoachLanguage.en);
      d.started();
      now = Duration(microseconds: ((d.timeline!.duration + 1.1) * 1e6).round());
      expect(d.sample().viseme, Viseme.rest);
      expect(d.active, isFalse);
    });
  });
}
