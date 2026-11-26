// Speech pacing: rates, sentence pauses, text cleanup, voice preference and
// the lip-sync shape-change rate. Deterministic; the numbers printed by the
// "measurements" test are the before/after table in
// docs/avatar/SPEECH_PACING.md. Real voice quality and word markers can only
// be judged on a device.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:datewise_ai/avatar/lip_sync.dart';
import 'package:datewise_ai/avatar/speech_pace.dart';
import 'package:datewise_ai/avatar/viseme.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/services/speech_text.dart';
import 'package:datewise_ai/services/voice_service.dart';

import 'support/pacing_samples.dart';

Map<String, String> v(String name, String locale, {String? gender, String quality = 'default', String? id}) => {
      'name': name,
      'locale': locale,
      'quality': quality,
      if (gender != null) 'gender': gender,
      'identifier': id ?? 'com.apple.voice.$quality.$locale.$name',
    };

List<String> texts(CoachLanguage l) => l == CoachLanguage.en ? enReplies : esReplies;

/// (average changes/s over the whole reply, worst count in any 1 s window,
/// speaking words/min from the plan with pauses excluded).
({double avg, int max1s, double wpm}) measure(Coach c, double rate) {
  var changes = 0, words = 0;
  var dur = 0.0, speech = 0.0;
  var worst = 0;
  for (final t in texts(c.language)) {
    // One chunk per sentence, as the voice service speaks it.
    for (final chunk in SpeechText.chunks(SpeechText.clean(t, c.language))) {
      final tl = VisemeTimeline.plan(chunk.text, c.language, rate: rate);
      final times = <double>[];
      for (var i = 1; i < tl.cues.length; i++) {
        if (tl.cues[i].viseme != tl.cues[i - 1].viseme) times.add(tl.cues[i].start);
      }
      changes += times.length;
      dur += tl.duration;
      words += tl.words.length;
      for (final w in tl.words) {
        speech += w.duration;
      }
      for (final s in times) {
        worst = math.max(worst, times.where((x) => x >= s && x < s + 1).length);
      }
    }
  }
  return (avg: changes / dur, max1s: worst, wpm: words / speech * 60);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('speaking pace', () {
    test('every coach is at a comfortable pace in their own language (model: SpeechPace)', () {
      for (final c in Coaches.all) {
        final m = measure(c, CoachVoiceProfile.of(c).rate);
        final range = c.language == CoachLanguage.en ? (150.0, 165.0) : (140.0, 160.0);
        expect(m.wpm, inInclusiveRange(range.$1, range.$2), reason: '${c.id} ${m.wpm.toStringAsFixed(0)} wpm');
      }
    });

    test('rates are slower than build 203 and the coaches stay distinguishable', () {
      const old = {'ava': 0.54, 'ethan': 0.49, 'sofia': 0.46, 'diego': 0.45};
      for (final c in Coaches.all) {
        final p = CoachVoiceProfile.of(c);
        expect(p.rate, lessThan(old[c.id]!), reason: c.id);
        expect(p.rate, inInclusiveRange(0.40, 0.5), reason: 'calm, never above the platform default');
        expect(p.pitch, inInclusiveRange(0.92, 1.08), reason: 'no synthetic-sounding pitch shift');
      }
      expect(CoachVoiceProfile.ava.pitch, 1.0, reason: 'the least shifted voice stays natural');
      expect({for (final c in Coaches.all) (CoachVoiceProfile.of(c).pitch, CoachVoiceProfile.of(c).rate)}, hasLength(4));
      for (final pair in [(Coaches.ava, Coaches.sofia), (Coaches.ethan, Coaches.diego)]) {
        final a = CoachVoiceProfile.of(pair.$1), b = CoachVoiceProfile.of(pair.$2);
        expect((a.pitch - b.pitch).abs(), greaterThanOrEqualTo(0.049));
      }
    });

    test('SpeechPace: 0.5 is the platform default and the model is monotonic', () {
      expect(SpeechPace.wordsPerMinute(0.5), 170);
      expect(SpeechPace.wordsPerMinute(0.45), lessThan(SpeechPace.wordsPerMinute(0.5)));
      expect(SpeechPace.lettersPerSecond(0.4), lessThan(SpeechPace.lettersPerSecond(0.6)));
    });
  });

  group('sentence pauses and text cleanup', () {
    test('sentences become chunks with 300-450 ms between them and a longer pause between paragraphs', () {
      final c = SpeechText.chunks('First one. Second one! Third one?\n\nNew paragraph here. Last.');
      expect(c.map((x) => x.text), ['First one.', 'Second one!', 'Third one?', 'New paragraph here.', 'Last.']);
      expect(c[0].pause.inMilliseconds, inInclusiveRange(300, 450));
      expect(c[1].pause.inMilliseconds, inInclusiveRange(300, 450));
      expect(c[2].pause, greaterThan(c[1].pause), reason: 'paragraph break is longer');
      expect(c[3].pause.inMilliseconds, inInclusiveRange(300, 450));
      expect(c.last.pause, Duration.zero);
    });

    test('a very long sentence is also cut at clause boundaries with a short pause', () {
      const long = 'When you meet someone new, it helps to stay curious about their day, their work and the things they care about, '
          'because people open up when they feel heard.';
      final c = SpeechText.chunks(long);
      expect(c.length, greaterThan(1));
      expect(c.first.pause, SpeechText.clausePause);
      expect(c.last.pause, Duration.zero);
      expect(c.map((x) => x.text).join(' '), long);
    });

    test('decimals, quotes and Spanish inverted marks do not break sentences wrongly', () {
      expect(SpeechText.chunks('It costs 3.5 times more.').length, 1);
      final es = SpeechText.chunks('¿Cómo estás? ¡Muy bien! Gracias.');
      expect(es.map((x) => x.text), ['¿Cómo estás?', '¡Muy bien!', 'Gracias.']);
    });

    test('markdown, emoji and stage directions are removed', () {
      const raw = '## Tip\n**Be** _kind_ and `calm` 😊 (smiles) see [my guide](https://x.y/z).\n- first point\n- second point';
      final t = SpeechText.clean(raw, CoachLanguage.en);
      expect(t, isNot(contains('*')));
      expect(t, isNot(contains('#')));
      expect(t, isNot(contains('`')));
      expect(t, isNot(contains('_')));
      expect(t, isNot(contains('😊')));
      expect(t, isNot(contains('smiles')));
      expect(t, isNot(contains('http')));
      expect(t, contains('my guide'));
      expect(t, contains('first point'));
      expect(t, isNot(contains('- ')));
    });

    test('a longer parenthetical is read, with commas', () {
      expect(SpeechText.clean('Pick a place (a quiet cafe near you) and go.', CoachLanguage.en),
          'Pick a place, a quiet cafe near you, and go.');
    });

    test('English numbers, times, money and abbreviations', () {
      String e(String s) => SpeechText.clean(s, CoachLanguage.en);
      expect(e('Dinner at 7pm.'), 'Dinner at 7 p m.');
      expect(e('Meet at 7:30 PM tonight'), 'Meet at 7:30 p m tonight');
      expect(e('It is \$19.99 a month'), 'It is 19 dollars and 99 cents a month');
      expect(e('Only \$20.'), 'Only 20 dollars.');
      expect(e('Only \$1 today'), 'Only 1 dollar today');
      expect(e('Looks vs. feelings, etc. matter'), 'Looks versus feelings, et cetera, matter');
      expect(e('Warmth, humor, etc.'), 'Warmth, humor, et cetera.');
      expect(e('Be kind, e.g. listen well'), 'Be kind, for example listen well');
      expect(e('50% of dates'), '50 percent of dates');
      expect(e('Ask Dr. Lee'), 'Ask Doctor Lee');
      expect(e('Tom & Ava'), 'Tom and Ava');
    });

    test('Spanish numbers, times, money and abbreviations', () {
      String s(String x) => SpeechText.clean(x, CoachLanguage.es);
      expect(s('La cena es a las 7pm.'), 'La cena es a las 7 de la noche.');
      expect(s('Nos vemos a las 3 pm'), 'Nos vemos a las 3 de la tarde');
      expect(s('Cuesta \$19.99 al mes'), 'Cuesta 19 dólares con 99 centavos al mes');
      expect(s('Solo \$20.'), 'Solo 20 dólares.');
      expect(s('Cariño vs. amistad, etc. importan'), 'Cariño versus amistad, etcétera, importan');
      expect(s('Sé amable, p. ej. escucha'), 'Sé amable, por ejemplo escucha');
      expect(s('50% de las citas'), '50 por ciento de las citas');
      expect(s('Habla con la Dra. Pérez'), 'Habla con la Doctora Pérez');
    });

    test('abbreviation periods do not end a sentence', () {
      final c = SpeechText.chunks(SpeechText.clean('Looks vs. feelings matter. So does etc. in lists.', CoachLanguage.en));
      expect(c.length, 2);
    });

    test('sample replies split into sentence chunks', () {
      for (final l in CoachLanguage.values) {
        for (final t in texts(l)) {
          final c = SpeechText.chunks(SpeechText.clean(t, l));
          expect(c.length, inInclusiveRange(3, 6));
          for (final x in c.take(c.length - 1)) {
            expect(x.pause.inMilliseconds, inInclusiveRange(150, 700));
          }
        }
      }
    });
  });

  group('voice preference', () {
    String? pick(List<Map<String, String>> voices, Coach c) => DeviceVoiceService.pickVoice(voices, c)?['name'];

    test('Premium beats Enhanced beats default; compact loses to anything better in the locale', () {
      final voices = [
        v('Samantha', 'en-US', gender: 'female', id: 'com.apple.voice.compact.en-US.Samantha'),
        v('Ava', 'en-US', gender: 'female', quality: 'enhanced'),
        v('Zoe', 'en-US', gender: 'female', quality: 'premium'),
      ];
      expect(pick(voices, Coaches.ava), 'Zoe');
      expect(pick(voices.take(2).toList(), Coaches.ava), 'Ava');
      final compactOnly = [
        v('Samantha', 'en-US', gender: 'female', id: 'com.apple.voice.compact.en-US.Samantha'),
        v('Allison', 'en-US', gender: 'female'),
      ];
      expect(pick(compactOnly, Coaches.ava), 'Allison', reason: 'a non-compact default beats compact');
    });

    test('quality is read from the identifier when the quality field is missing', () {
      final voices = [
        {'name': 'Ava', 'locale': 'en-US', 'identifier': 'com.apple.voice.compact.en-US.Ava'},
        {'name': 'Samantha', 'locale': 'en-US', 'identifier': 'com.apple.voice.premium.en-US.Samantha'},
      ];
      expect(pick(voices, Coaches.ava), 'Samantha');
    });

    test('Siri and neural voices rank first; novelty voices last', () {
      final voices = [
        v('Zoe', 'en-US', gender: 'female', quality: 'premium'),
        v('Aria', 'en-US', gender: 'female', id: 'com.apple.ttsbundle.siri_Aria_en-US_premium'),
        v('Fred', 'en-US', gender: 'male', id: 'com.apple.speech.synthesis.voice.Fred'),
        v('Evan', 'en-US', gender: 'male'),
      ];
      expect(pick(voices, Coaches.ava), 'Aria');
      expect(pick(voices, Coaches.ethan), 'Evan', reason: 'a novelty voice never beats a real one');
    });

    test('a novelty voice never beats a real one in a later locale (the iOS simulator: Ethan spoke as Fred)', () {
      // The en voices of the iOS 26 simulator (ios-sim-release-e2e.yml): no real en-US male voice.
      final voices = [
        v('Samantha', 'en-US', gender: 'female', id: 'com.apple.voice.super-compact.en-US.Samantha'),
        v('Fred', 'en-US', gender: 'male', id: 'com.apple.speech.synthesis.voice.Fred'),
        v('Ralph', 'en-US', gender: 'male', id: 'com.apple.speech.synthesis.voice.Ralph'),
        v('Daniel', 'en-GB', gender: 'male', id: 'com.apple.voice.super-compact.en-GB.Daniel'),
        v('Karen', 'en-AU', gender: 'female', id: 'com.apple.voice.super-compact.en-AU.Karen'),
      ];
      expect(pick(voices, Coaches.ethan), 'Daniel');
      expect(pick(voices, Coaches.ava), 'Samantha', reason: 'the first locale still wins among real voices');
      // Only novelty voices of his gender: one of them, rather than no voice at all.
      final noveltyOnly = voices.where((x) => x['name'] != 'Daniel').toList();
      expect(pick(noveltyOnly, Coaches.ethan), anyOf('Fred', 'Ralph'));
    });

    test('es-MX over any other Spanish, even a better-quality es-ES; es-ES only as a last resort', () {
      final voices = [
        v('Mónica', 'es-ES', gender: 'female', quality: 'premium'),
        v('Paulina', 'es-MX', gender: 'female'),
        v('Marisol', 'es-US', gender: 'female', quality: 'enhanced'),
        v('Jorge', 'es-ES', gender: 'male', quality: 'enhanced'),
        v('Juan', 'es-MX', gender: 'male'),
      ];
      expect(DeviceVoiceService.pickVoice(voices, Coaches.sofia)!['locale'], 'es-MX');
      expect(DeviceVoiceService.pickVoice(voices, Coaches.diego)!['locale'], 'es-MX');
      final noMx = voices.where((x) => x['locale'] != 'es-MX').toList();
      expect(DeviceVoiceService.pickVoice(noMx, Coaches.sofia)!['locale'], 'es-US');
      final onlySpain = voices.where((x) => x['locale'] == 'es-ES').toList();
      expect(pick(onlySpain, Coaches.sofia), 'Mónica');
      final withLatam = [...onlySpain, v('Paulina', 'es-419', gender: 'female')];
      expect(DeviceVoiceService.pickVoice(withLatam, Coaches.sofia)!['locale'], 'es-419');
    });

    test('Android-style voices without metadata: es-MX still wins', () {
      final voices = [
        {'name': 'es-es-x-eed-local', 'locale': 'es-ES'},
        {'name': 'es-mx-x-eea-local', 'locale': 'es-MX'},
        {'name': 'es-us-x-sfb-local', 'locale': 'es-US'},
      ];
      expect(DeviceVoiceService.pickVoice(voices, Coaches.sofia)!['locale'], 'es-MX');
    });
  });

  group('premium voice tip wording', () {
    test('English and Spanish tell the user where to download Enhanced/Premium voices', () {
      // lib/l10n: voiceQualityBody.
      final en = _l10n('en'), es = _l10n('es');
      expect(en, contains('Settings'));
      expect(en, contains('Accessibility › Spoken Content › Voices'));
      expect(en, contains('Premium or Enhanced'));
      expect(es, contains('Accesibilidad › Contenido leído › Voces'));
      expect(es, contains('Premium o Mejorada'));
    });
  });

  group('lip-sync rate', () {
    test('minimum shape duration is raised and every non-bridge shape respects it', () {
      expect(VisemeTimeline.minShape, greaterThanOrEqualTo(0.12));
      for (final c in Coaches.all) {
        final rate = CoachVoiceProfile.of(c).rate;
        for (final t in texts(c.language)) {
          final tl = VisemeTimeline.plan(t, c.language, rate: rate);
          for (final cue in tl.cues.where((x) => x.viseme != Viseme.rest && !x.bridge)) {
            expect(cue.duration, greaterThanOrEqualTo(VisemeTimeline.minShape - 1e-9), reason: '${c.id} $cue');
          }
        }
      }
    });

    test('no repeated or near-identical consecutive shapes', () {
      for (final c in Coaches.all) {
        for (final t in texts(c.language)) {
          final tl = VisemeTimeline.plan(t, c.language, rate: CoachVoiceProfile.of(c).rate);
          for (var i = 1; i < tl.cues.length; i++) {
            expect(tl.cues[i].viseme, isNot(tl.cues[i - 1].viseme), reason: '${c.id} ${tl.cues[i]}');
          }
        }
      }
    });

    test('shape changes: average at most 6/s and never above 8/s in any second, en and es, all coaches', () {
      for (final c in Coaches.all) {
        final m = measure(c, CoachVoiceProfile.of(c).rate);
        expect(m.avg, lessThanOrEqualTo(6.0), reason: '${c.id} avg ${m.avg.toStringAsFixed(2)}');
        expect(m.max1s, lessThanOrEqualTo(8), reason: '${c.id} max ${m.max1s}');
      }
    });

    test('closed lips still show on m/b/p, and big jumps still go through a middle shape', () {
      final tl = VisemeTimeline.plan('Maybe my mum bought bread', CoachLanguage.en, rate: 0.45);
      expect(tl.cues.any((c) => c.viseme == Viseme.mbp), isTrue);
      final es = VisemeTimeline.plan('Mamá me ayuda con el primer mensaje', CoachLanguage.es, rate: 0.455);
      expect(es.cues.any((c) => c.viseme == Viseme.mbp), isTrue);
      for (var i = 1; i < tl.cues.length; i++) {
        final a = tl.cues[i - 1].viseme, b = tl.cues[i].viseme;
        if (tl.cues[i].duration < VisemeTimeline.bridgeLength + VisemeTimeline.minAfterBridge) continue;
        if (a.closed != b.closed) {
          final open = a.closed ? b : a;
          expect(open == Viseme.rest || open.openness > 0.3, isFalse);
        }
      }
    });

    test('the plan follows the slower speech rate (longer than at the old rates)', () {
      const t = 'Es totalmente normal sentirse nervioso antes de una primera cita.';
      final slow = VisemeTimeline.plan(t, CoachLanguage.es, rate: 0.455);
      final fast = VisemeTimeline.plan(t, CoachLanguage.es, rate: 0.54);
      expect(slow.duration, greaterThan(fast.duration * 1.1));
    });

    test('measurements (before = build 203 values, after = now)', () {
      // Before values were measured on commit 2d123a9 with the same sample
      // replies and the planner of that commit (all sentences in one plan).
      const before = {
        'ava': 'rate 0.54 pitch 0.98: 10.1 changes/s avg, 15 max',
        'ethan': 'rate 0.49 pitch 0.91: 9.8 avg, 14 max',
        'sofia': 'rate 0.46 pitch 1.10: 10.2 avg, 14 max',
        'diego': 'rate 0.45 pitch 0.88: 10.2 avg, 14 max',
      };
      for (final c in Coaches.all) {
        final p = CoachVoiceProfile.of(c);
        final m = measure(c, p.rate);
        // ignore: avoid_print
        print('MEASURE ${c.id}: before [${before[c.id]}] after rate ${p.rate} pitch ${p.pitch}: '
            '${m.wpm.toStringAsFixed(0)} wpm speech, ${m.avg.toStringAsFixed(1)} changes/s avg, ${m.max1s} max');
      }
    });
  });

  group('service: sentence by sentence', () {
    const channel = MethodChannel('flutter_tts');
    late List<String> spoken;
    late List<Duration> pauses;
    final voices = [
      {'name': 'Ava', 'locale': 'en-US', 'gender': 'female', 'quality': 'enhanced', 'identifier': 'com.apple.voice.enhanced.en-US.Ava'},
    ];

    setUp(() {
      spoken = [];
      pauses = [];
      DeviceVoiceService.useAudioPath = false;
      DeviceVoiceService.pauseFor = (d) async => pauses.add(d);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'speak') spoken.add('${call.arguments}');
        return 1;
      });
    });
    tearDown(() {
      DeviceVoiceService.pauseFor = (d) => Future<void>.delayed(d);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    Future<void> native(String method) async {
      const codec = StandardMethodCodec();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('flutter_tts', codec.encodeMethodCall(MethodCall(method)), (_) {});
      await Future<void>.delayed(Duration.zero);
    }

    test('speaks one sentence at a time; speaking stays on between them and ends after the last', () async {
      final s = DeviceVoiceService.forTesting(FlutterTts(), voices);
      await s.speak('First sentence here. Second one follows. Third one ends it.', Coaches.ava);
      expect(spoken, ['First sentence here.']);
      await native('speak.onStart');
      expect(s.speaking.value, isTrue);
      await native('speak.onComplete');
      expect(s.speaking.value, isTrue, reason: 'still mid-reply during the pause');
      expect(s.lipSync.active, isFalse, reason: 'lips rest in the pause');
      expect(pauses, [SpeechText.sentencePause]);
      expect(spoken, ['First sentence here.', 'Second one follows.']);
      await native('speak.onComplete');
      expect(spoken.last, 'Third one ends it.');
      await native('speak.onComplete');
      expect(s.speaking.value, isFalse);
      expect(pauses, [SpeechText.sentencePause, SpeechText.sentencePause]);
    });

    test('stop() during a reply stops the sequence', () async {
      final s = DeviceVoiceService.forTesting(FlutterTts(), voices);
      await s.speak('One sentence here. Another sentence there.', Coaches.ava);
      await native('speak.onStart');
      await s.stop();
      await native('speak.onComplete');
      expect(spoken, hasLength(1), reason: 'the second sentence never starts');
      expect(s.speaking.value, isFalse);
    });

    test('a new speak() replaces the old reply and its pending sentences', () async {
      final s = DeviceVoiceService.forTesting(FlutterTts(), voices);
      await s.speak('Old one here. Old two there.', Coaches.ava);
      await s.speak('Brand new reply.', Coaches.ava);
      await native('speak.onComplete');
      expect(spoken, ['Old one here.', 'Brand new reply.']);
      expect(s.speaking.value, isFalse);
    });

    test('an error mid-reply ends it and clears the speaking state', () async {
      final s = DeviceVoiceService.forTesting(FlutterTts(), voices);
      await s.speak('One sentence here. Another sentence there.', Coaches.ava);
      await native('speak.onStart');
      await native('speak.onCancel');
      expect(s.speaking.value, isFalse);
      expect(spoken, hasLength(1));
    });

    test('the lip-sync plan is made per sentence from the exact text spoken', () async {
      final s = DeviceVoiceService.forTesting(FlutterTts(), voices);
      await s.speak('Dinner at 7pm. **Bring** a smile 😊.', Coaches.ava);
      expect(s.lipSync.timeline!.text, 'Dinner at 7 p m.');
      await native('speak.onComplete');
      expect(spoken.last, 'Bring a smile.');
      expect(s.lipSync.timeline!.text, 'Bring a smile.');
    });
  });
}

String _l10n(String code) {
  // Read the generated localization source for the tip text.
  final path = 'lib/l10n/app_localizations_$code.dart';
  return _read(path);
}

String _read(String path) => File(path).readAsStringSync();
