import 'dart:math' as math;

// Talking avatar: spelling-to-mouth-shape rules (EN/ES), the timeline, and
// the driver that follows the synthesizer's word events.

import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/lip_sync.dart';
import 'package:datewise_ai/avatar/speech_audio.dart';
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
          if (b.viseme != Viseme.rest && a.viseme != Viseme.rest && !a.viseme.closed && !b.viseme.closed &&
              b.duration >= VisemeTimeline.bridgeLength + VisemeTimeline.minAfterBridge) {
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

    test('every change is a hard switch; closed lips never sit next to an open mouth', () {
      for (final e in {
        CoachLanguage.en: "I'm Ava. Mmm, okay! Maybe a bigger, bolder opener: be playful.",
        CoachLanguage.es: 'Mamá, ¿me ayudas? Un beso, gran paso, envía un mensaje ya.',
      }.entries) {
        final tl = VisemeTimeline.plan(e.key == CoachLanguage.en ? e.value : e.value, e.key, rate: 0.5);
        for (var i = 1; i < tl.cues.length; i++) {
          final a = tl.cues[i - 1].viseme, b = tl.cues[i].viseme;
          // Too short to fit a middle shape of two frames: a plain switch.
          if (tl.cues[i].duration < VisemeTimeline.bridgeLength + VisemeTimeline.minAfterBridge) continue;
          if (a.closed != b.closed) {
            final open = a.closed ? b : a;
            expect(open == Viseme.rest || open.openness > 0.3, isFalse,
                reason: 'closed lips next to $open (${e.key.name}): no half-open step');
          }
        }
        for (var t = 0.0; t < tl.duration; t += 0.004) {
          expect(tl.sample(t).mix, 1, reason: 'no crossfade at $t');
        }
      }
      expect(VisemeTimeline.blend, 0);
      expect(VisemeTimeline.needsBridge(Viseme.mbp, Viseme.a), isTrue);
      expect(VisemeTimeline.needsBridge(Viseme.rest, Viseme.mbp), isTrue, reason: 'smiling rest shows teeth');
      expect(VisemeTimeline.smallestOpen(Viseme.mbp, Viseme.a), Viseme.i2);
    });

    test('jaw envelope rises and falls within every vowel (movement while speaking)', () {
      final tl = VisemeTimeline.fromTimedWords('casa', CoachLanguage.es, [(0, 4, 0.0, 0.6)]);
      final v = tl.cues.firstWhere((c) => c.viseme.isVowel);
      final mid = tl.jawAt((v.start + v.end) / 2), edge = tl.jawAt(v.start + 0.001);
      expect(mid, greaterThan(edge + 0.1));
      expect(tl.jawAt(-1), 0);
    });

    test('middle shape is half-open, and rounded next to a rounded shape', () {
      expect(VisemeTimeline.middle(Viseme.mbp, Viseme.a).openness, inInclusiveRange(0.3, 0.7));
      expect(VisemeTimeline.middle(Viseme.mbp, Viseme.o).rounded, isTrue);
    });

    test('measured word times are kept exactly; "gran paso" closes the lips across the words', () {
      const text = 'Be clear about it';
      final tl = VisemeTimeline.fromTimedWords(text, CoachLanguage.en, [(0, 2, 0.1, 0.3), (3, 8, 0.35, 0.8), (9, 14, 0.9, 1.3), (15, 17, 1.35, 1.5)]);
      expect(tl.words.map((w) => w.start), [0.1, 0.35, 0.9, 1.35]);
      expect(tl.sample(0.1 + 0.01).to, anyOf(Viseme.i2, Viseme.mbp));
      final long = VisemeTimeline.fromTimedWords('Mmm', CoachLanguage.en, [(0, 3, 0.1, 0.5)]);
      expect(long.sample(0.1 + 0.01).to, Viseme.i2, reason: 'from the smiling rest, lips part slightly first');
      expect(long.sample(0.1 + 0.06).to, Viseme.mbp);
      for (final c in long.cues.where((c) => c.viseme == Viseme.i2)) {
        expect(c.duration, greaterThanOrEqualTo(0.033), reason: 'no one-frame flicker');
      }
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

    test('ends by itself 1 s after the plan once the pace is confirmed by a word event', () {
      d.begin('Short one', CoachLanguage.en);
      d.started();
      d.word(0, 5);
      now = Duration(microseconds: ((d.timeline!.duration + 1.1) * 1e6).round());
      expect(d.sample().viseme, Viseme.rest);
      expect(d.active, isFalse);
    });

    test('without any word event it waits up to twice the plan before giving up (slow voices)', () {
      d.begin('A voice that never sends word events at all', CoachLanguage.en);
      d.started();
      final dur = d.timeline!.duration;
      now = Duration(microseconds: ((dur + 1.5) * 1e6).round());
      d.sample();
      expect(d.active, isTrue, reason: 'still speaking, maybe slower than planned');
      now = Duration(microseconds: ((dur * 2 + 2.1) * 1e6).round());
      d.sample();
      expect(d.active, isFalse);
    });

    test('with real loudness: the jaw follows it, vowels open fully only when loud, no rest while audible', () {
      const text = 'Hola, soy Diego.';
      d.begin(text, CoachLanguage.es);
      d.started();
      // 1 s of audio: loud from 0.1 to 0.5 s, quiet 0.5-0.7 s, loud 0.7-1.0 s.
      final v = [for (var i = 0; i < 100; i++) (i >= 10 && i < 50) || i >= 70 ? 0.5 : (i >= 50 && i < 70 ? 0.0 : 0.0)];
      d.addLevels(0, 0.01, v);
      expect(d.hasAudio, isTrue);
      now = const Duration(milliseconds: 250);
      expect(d.jaw(), greaterThan(0.5));
      now = const Duration(milliseconds: 600);
      expect(d.jaw(), lessThan(0.1));
      now = const Duration(milliseconds: 200);
      final s = d.sample();
      expect(s.to, isNot(Viseme.rest));
      if (s.to.isVowel) expect(s.to, s.to.full);
    });
  });

  group('audio alignment', () {
    test('the loudness is warped onto the plan: phrases line up with the speech, pauses with silence', () {
      const text = 'Hola, soy Diego. Sé claro con lo que buscas.';
      final tl = VisemeTimeline.plan(text, CoachLanguage.es);
      final a = AudioAlignment(tl);
      // Synthetic audio at 0.8x the planned pace, with the plan's pauses:
      // speech wherever the plan has a word, silence elsewhere.
      const speed = 0.8;
      final n = (tl.duration * speed / 0.01).ceil();
      final v = [
        for (var i = 0; i < n; i++)
          tl.words.any((w) => w.start <= i * 0.01 / speed && i * 0.01 / speed <= w.end) ? 0.4 : 0.0,
      ];
      a.addLevels(0, 0.01, v);
      a.complete();
      var sum = 0.0;
      for (final w in tl.words) {
        final err = (a.planTime(w.start * speed)! - w.start).abs();
        expect(err, lessThan(0.12), reason: w.text);
        sum += err;
      }
      expect(sum / tl.words.length, lessThan(0.06));
      expect(a.level(tl.words.first.start * speed + 0.05), closeTo(1, 1e-9));
    });

    test('a long reply is warped in bounded time and memory', () {
      final text = List.filled(40, 'Esta es una frase de prueba bastante larga, con pausas.').join(' ');
      final tl = VisemeTimeline.plan(text, CoachLanguage.es);
      expect(tl.duration, greaterThan(120));
      final a = AudioAlignment(tl);
      final n = (tl.duration / 0.01).ceil();
      final sw = Stopwatch()..start();
      a.addLevels(0, 0.01, [for (var i = 0; i < n; i++) (i ~/ 30).isEven ? 0.5 : 0.0]);
      a.complete();
      expect(sw.elapsedMilliseconds, lessThan(3000));
      expect(a.planTime(60), isNotNull);
    });

    test('levels arriving in 100 ms chunks: each call stays cheap (UI isolate)', () {
      final text = List.filled(12, 'Esta es una frase de prueba, con pausas y palabras largas.').join(' ');
      final tl = VisemeTimeline.plan(text, CoachLanguage.es);
      final a = AudioAlignment(tl);
      final n = (tl.duration / 0.01).ceil();
      final all = [for (var i = 0; i < n; i++) (i ~/ 25).isEven ? 0.5 : 0.0];
      var worst = 0;
      for (var i = 0; i < n; i += 10) {
        final sw = Stopwatch()..start();
        a.addLevels(i * 0.01, 0.01, all.sublist(i, math.min(n, i + 10)));
        worst = math.max(worst, sw.elapsedMicroseconds);
      }
      final sw = Stopwatch()..start();
      a.complete();
      worst = math.max(worst, sw.elapsedMicroseconds);
      // Debug-mode test VM; release builds are several times faster.
      // ignore: avoid_print
      print('AudioAlignment worst call: ${(worst / 1000).toStringAsFixed(1)} ms (${tl.duration.toStringAsFixed(0)} s reply)');
      expect(worst, lessThan(150000), reason: 'worst call ${worst ~/ 1000} ms');
    });

    test('lip closures snap to the nearest loudness dip (within 120 ms)', () {
      const text = 'mamá';
      final tl = VisemeTimeline.fromTimedWords(text, CoachLanguage.es, [(0, 4, 0.0, 0.8)]);
      final a = AudioAlignment(tl);
      // Loud, with dips at 0.05 s and 0.40 s (the two m's), 0.8 s long.
      a.addLevels(0, 0.01, [for (var i = 0; i < 80; i++) (i - 5).abs() < 3 || (i - 40).abs() < 3 ? 0.02 : 0.5]);
      a.complete();
      final cl = a.closures();
      expect(cl, hasLength(tl.cues.where((c) => c.viseme == Viseme.mbp).length));
      for (final (s0, e0) in cl) {
        final mid = (s0 + e0) / 2;
        expect([0.05, 0.40].any((d) => (mid - d).abs() <= 0.03), isTrue, reason: 'closure centred at $mid');
      }
      expect(a.inClosure(0.40), isTrue);
      expect(a.inClosure(0.25), isFalse);
    });

    test('markers past the audio or out of order are ignored (unit mistakes)', () {
      const text = 'one two three';
      final tl = VisemeTimeline.plan(text, CoachLanguage.en);
      final a = AudioAlignment(tl);
      a.addLevels(0, 0.01, List.filled(150, 0.3));
      a.addMarker(0, 0.2);
      a.addMarker(4, 9.0); // seconds computed from bytes as samples: far past 1.5 s
      a.complete();
      expect(a.planTime(0.9), isNot(closeTo(tl.words[1].start, 1e-9)));
    });

    test('word markers (iOS 17) take precedence and map exactly', () {
      const text = 'one two three';
      final tl = VisemeTimeline.plan(text, CoachLanguage.en);
      final a = AudioAlignment(tl);
      a.addMarker(0, 0.2);
      a.addMarker(4, 0.9);
      a.addMarker(8, 1.5);
      expect(a.planTime(0.9), closeTo(tl.words[1].start, 1e-9));
      expect(a.planTime(1.2), closeTo((tl.words[1].start + tl.words[2].start) / 2, 1e-9));
    });

    test('channel events parse', () {
      expect(SpeechAudioEvent.parse({'e': 'start'}), isA<SpeechAudioStarted>());
      final l = SpeechAudioEvent.parse({'e': 'levels', 't0': 0.5, 'hop': 0.01, 'v': [0.1, 0.2]}) as SpeechAudioLevels;
      expect((l.t0, l.hop), (0.5, 0.01));
      expect(l.values, [0.1, 0.2]);
      final m = SpeechAudioEvent.parse({'e': 'marker', 'start': 3, 'end': 7, 't': 1.25}) as SpeechAudioMarker;
      expect((m.charStart, m.charEnd, m.t), (3, 7, 1.25));
      expect(SpeechAudioEvent.parse({'e': 'error', 'message': 'x', 'started': true}), isA<SpeechAudioError>());
      expect(SpeechAudioEvent.parse({'e': 'synthesized'}), isA<SpeechAudioSynthesized>());
      expect(SpeechAudioEvent.parse('junk'), isNull);
    });
  });
}
