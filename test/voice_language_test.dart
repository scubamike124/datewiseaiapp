// Read-aloud and mic language (AI QA D6/D7). Coaches answer in the user's
// language; the voice follows the language actually used, with a
// same-gender voice and the coach's own pitch and rate, and the mic uses the
// coach's language unless the user's last message was in the other one.

import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/services/reply_language.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/services/voice_service.dart';

ChatMessage _msg(String text, {bool user = true}) =>
    ChatMessage(id: text, role: user ? MessageRole.user : MessageRole.coach, text: text, createdAt: DateTime(2026));

void main() {
  group('ReplyLanguage.detect', () {
    const en = CoachLanguage.en;
    const es = CoachLanguage.es;

    test('Spanish markers and words', () {
      for (final t in [
        '¡Hola! ¿Cómo te fue en la cita?',
        'Quiero escribirle un mensaje, pero no sé qué decir.',
        'Mañana tengo una cita',
        'Dale, suena bien, gracias por la ayuda',
      ]) {
        expect(ReplyLanguage.detect(t, fallback: en), es, reason: t);
      }
    });

    test('English words, including a stray accent (café) and curly apostrophes', () {
      for (final t in [
        "Hi, I'm nervous about my first date.",
        'How do I reply to her message?',
        'Let’s meet at the café on Friday, what do you think?',
        'You can ask her about the trip she mentioned.',
      ]) {
        expect(ReplyLanguage.detect(t, fallback: es), en, reason: t);
      }
    });

    test('no clear sign (short or neutral text) → the fallback', () {
      for (final t in ['ok', 'jaja', '👍', 'Ana', '']) {
        expect(ReplyLanguage.detect(t, fallback: es), es, reason: t);
        expect(ReplyLanguage.detect(t, fallback: en), en, reason: t);
      }
    });

    test("the coaches' own greetings and voice intros are detected as their language", () {
      for (final c in Coaches.all) {
        expect(ReplyLanguage.detect(c.greeting, fallback: c.language == en ? es : en), c.language, reason: c.id);
        expect(ReplyLanguage.detect(c.voiceIntro, fallback: c.language == en ? es : en), c.language, reason: c.id);
      }
    });
  });

  group('mic language', () {
    test("the coach's language by default (no user message yet)", () {
      expect(ReplyLanguage.forMic(Coaches.sofia, [_msg(Coaches.sofia.greeting, user: false)]), CoachLanguage.es);
      expect(ReplyLanguage.forMic(Coaches.ava, const []), CoachLanguage.en);
    });

    test("the other language when the user's last message was in it", () {
      final thread = [
        _msg(Coaches.sofia.greeting, user: false),
        _msg('Hola'),
        _msg('¡Hola!', user: false),
        _msg('Can you help me write my profile in English?'),
      ];
      expect(ReplyLanguage.forMic(Coaches.sofia, thread), CoachLanguage.en);
      expect(ReplyLanguage.forMic(Coaches.ethan, [_msg('¿Qué le escribo después de la cita?')]), CoachLanguage.es);
    });

    test('a neutral last message keeps the coach language', () {
      expect(ReplyLanguage.forMic(Coaches.diego, [_msg('Can you help me?'), _msg('ok')]), CoachLanguage.es);
    });
  });

  group('mic locale fallback chain', () {
    test('es-MX → es-US → es-ES → any es; en-US → en-GB → any en', () {
      expect(SpeechService.localesFor(CoachLanguage.es), ['es-MX', 'es-US', 'es-ES', 'es']);
      expect(SpeechService.localesFor(CoachLanguage.en), ['en-US', 'en-GB', 'en']);
    });

    test('picks the first locale the device supports, as the device spells it', () {
      final es = SpeechService.localesFor(CoachLanguage.es);
      final en = SpeechService.localesFor(CoachLanguage.en);
      expect(SpeechService.pickLocale(['en_US', 'es_MX', 'es_ES'], es), 'es_MX');
      expect(SpeechService.pickLocale(['en_US', 'es_ES', 'es_US'], es), 'es_US');
      expect(SpeechService.pickLocale(['en_US', 'es_ES'], es), 'es_ES');
      expect(SpeechService.pickLocale(['en_US', 'es_CO'], es), 'es_CO', reason: 'any Spanish');
      expect(SpeechService.pickLocale(['en_GB', 'en_AU'], en), 'en_GB');
      expect(SpeechService.pickLocale(['en-IN', 'fr-FR'], en), 'en-IN');
    });

    test('unknown device list, or no match: the first wanted locale (recognition then reports unsupported)', () {
      final es = SpeechService.localesFor(CoachLanguage.es);
      expect(SpeechService.pickLocale(const [], es), 'es-MX');
      expect(SpeechService.pickLocale(['en_US', 'fr_FR'], es), 'es-MX');
    });
  });

  group('read-aloud voice', () {
    Map<String, String> v(String name, String locale, String gender) =>
        {'name': name, 'locale': locale, 'gender': gender, 'identifier': 'com.apple.voice.$name'};
    final voices = [
      v('Samantha', 'en-US', 'female'),
      v('Aaron', 'en-US', 'male'),
      v('Paulina', 'es-MX', 'female'),
      v('Juan', 'es-MX', 'male'),
    ];

    test("each coach's own language uses their own voice (unchanged)", () {
      expect(DeviceVoiceService.pickVoice(voices, Coaches.ava)!['name'], 'Samantha');
      expect(DeviceVoiceService.pickVoice(voices, Coaches.sofia, language: CoachLanguage.es)!['name'], 'Paulina');
    });

    test('the other language: a same-gender voice of that language', () {
      expect(DeviceVoiceService.pickVoice(voices, Coaches.sofia, language: CoachLanguage.en)!['name'], 'Samantha');
      expect(DeviceVoiceService.pickVoice(voices, Coaches.diego, language: CoachLanguage.en)!['name'], 'Aaron');
      expect(DeviceVoiceService.pickVoice(voices, Coaches.ava, language: CoachLanguage.es)!['name'], 'Paulina');
      expect(DeviceVoiceService.pickVoice(voices, Coaches.ethan, language: CoachLanguage.es)!['name'], 'Juan');
    });

    test('never a voice in the wrong language; none installed → null (system voice for that language)', () {
      final englishOnly = voices.where((x) => x['locale']!.startsWith('en')).toList();
      expect(DeviceVoiceService.pickVoice(englishOnly, Coaches.ava, language: CoachLanguage.es), isNull);
    });

    test("the voice profile of the other language; pitch and rate stay the coach's own", () {
      expect(CoachVoiceProfile.forLanguage(Coaches.sofia, CoachLanguage.en).locales.first, 'en-US');
      expect(CoachVoiceProfile.forLanguage(Coaches.sofia, CoachLanguage.en).preferredNames,
          CoachVoiceProfile.ava.preferredNames);
      expect(CoachVoiceProfile.forLanguage(Coaches.diego, CoachLanguage.en).preferredNames,
          CoachVoiceProfile.ethan.preferredNames);
      expect(CoachVoiceProfile.forLanguage(Coaches.ava, CoachLanguage.en), CoachVoiceProfile.ava);
      // speak() sets pitch and rate from CoachVoiceProfile.of(coach).
      expect(CoachVoiceProfile.of(Coaches.sofia).pitch, isNot(CoachVoiceProfile.ava.pitch));
    });
  });
}
