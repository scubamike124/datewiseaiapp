// QA (independent review of PR #27): voice mapping, iOS permission strings
// and copy honesty. Unit tests on code and files only: no device, no
// microphone, no TTS engine. Whether each voice actually sounds right on an
// iPhone is BLOCKED (physical device) — see docs/qa/AI_VOICE_REPORT.md.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/services/voice_service.dart';

Map<String, String> v(String name, String locale, {String? gender, String quality = 'default'}) => {
      'name': name,
      'locale': locale,
      'quality': quality,
      if (gender != null) 'gender': gender,
      'identifier': 'com.apple.voice.$quality.$locale.$name',
    };

Map<String, String>? pick(List<Map<String, String>> voices, Coach c) => DeviceVoiceService.pickVoice(voices, c);

/// Reads an InfoPlist.strings / Info.plist value for [key].
String? plistString(String text, String key) {
  final strings = RegExp('"$key"\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)";').firstMatch(text);
  if (strings != null) return strings.group(1);
  final plist = RegExp('<key>$key</key>\\s*<string>([^<]*)</string>').firstMatch(text);
  return plist?.group(1);
}

void main() {
  group('coach → voice profile', () {
    test('four distinct (locale list, pitch, rate) profiles, in the coach\'s own language', () {
      final profiles = {for (final c in Coaches.all) c.id: CoachVoiceProfile.of(c)};
      expect({for (final p in profiles.values) (p.pitch, p.rate)}, hasLength(4));
      for (final c in Coaches.all) {
        final p = profiles[c.id]!;
        expect(p.locales.first, c.language.locale, reason: '${c.name}: first TTS locale = coach locale');
        expect(p.locales.every((l) => l.startsWith(c.language.name)), isTrue, reason: '${c.name}: never another language');
        expect(p.pitch, inInclusiveRange(0.5, 2.0));
        expect(p.rate, inInclusiveRange(0.0, 1.0));
      }
      expect(Coaches.ava.language.locale, 'en-US');
      expect(Coaches.ethan.language.locale, 'en-US');
      expect(Coaches.sofia.language.locale, 'es-MX');
      expect(Coaches.diego.language.locale, 'es-MX');
    });

    test('the documented values (for the report)', () {
      String d(Coach c) {
        final p = CoachVoiceProfile.of(c);
        return '${c.id}:${p.locales.join('>')}:${p.pitch}:${p.rate}';
      }

      expect(Coaches.all.map(d).toList(), [
        'ava:en-US>en-GB>en-AU>en:1.05:0.5',
        'ethan:en-US>en-GB>en-AU>en:0.92:0.47',
        'sofia:es-MX>es-US>es-ES>es:1.08:0.49',
        'diego:es-MX>es-US>es-ES>es:0.9:0.46',
      ]);
    });

    test('female coaches never get a known male name first, and vice versa', () {
      for (final c in Coaches.all) {
        final p = CoachVoiceProfile.of(c);
        expect(p.preferredNames.toSet().intersection(p.otherGenderNames.toSet()), isEmpty, reason: c.name);
      }
    });

    test('a Spanish-US-only iPhone (no es-MX voices): Sofía and Diego get distinct es-US voices', () {
      final voices = [
        v('Samantha', 'en-US', gender: 'female'),
        v('Aaron', 'en-US', gender: 'male'),
        v('Paulina', 'es-US', gender: 'female'),
        v('Juan', 'es-US', gender: 'male'),
      ];
      expect(pick(voices, Coaches.sofia)!['name'], 'Paulina');
      expect(pick(voices, Coaches.diego)!['name'], 'Juan');
      expect(pick(voices, Coaches.ethan)!['name'], 'Aaron');
    });

    test('a stock iOS install (compact voices only, no downloads) keeps the four apart', () {
      // Typical out-of-box en-US voices on iOS 17/18 plus the Spanish defaults.
      final voices = [
        v('Samantha', 'en-US', gender: 'female'),
        v('Aaron', 'en-US', gender: 'male'),
        v('Fred', 'en-US', gender: 'male'),
        v('Nicky', 'en-US', gender: 'female'),
        v('Paulina', 'es-MX', gender: 'female'),
        v('Juan', 'es-MX', gender: 'male'),
        v('Eddy', 'es-MX', gender: 'male'),
      ];
      final picked = {for (final c in Coaches.all) c.id: pick(voices, c)!['name']};
      expect(picked, {'ava': 'Samantha', 'ethan': 'Aaron', 'sofia': 'Paulina', 'diego': 'Juan'});
    });

    test('voice not installed for the language → null → speak() falls back to setLanguage(text language locale)', () {
      final englishOnly = [v('Samantha', 'en-US', gender: 'female'), v('Aaron', 'en-US', gender: 'male')];
      expect(pick(englishOnly, Coaches.sofia), isNull);
      expect(pick(englishOnly, Coaches.diego), isNull);
      // voice_service.dart speak(): voice == null → _tts.setLanguage(language.locale),
      // the detected language of the text (the coach's own by default).
      final src = File('lib/services/voice_service.dart').readAsStringSync();
      expect(src, contains('await _tts.setLanguage(language.locale);'));
    });

    test('D6 fixed: TTS follows the language of the reply, with a same-gender voice', () {
      // A Spanish coach answering an English-speaking user (the language rule
      // in persona.dart allows it) is read with an English voice of her gender.
      final src = File('lib/services/voice_service.dart').readAsStringSync();
      expect(src, contains('ReplyLanguage.detect(clean, fallback: coach.language)'));
      final voices = [v('Samantha', 'en-US', gender: 'female'), v('Aaron', 'en-US', gender: 'male'),
        v('Paulina', 'es-MX', gender: 'female'), v('Juan', 'es-MX', gender: 'male')];
      expect(DeviceVoiceService.pickVoice(voices, Coaches.sofia, language: CoachLanguage.en)!['name'], 'Samantha');
      expect(DeviceVoiceService.pickVoice(voices, Coaches.diego, language: CoachLanguage.en)!['name'], 'Aaron');
      expect(DeviceVoiceService.pickVoice(voices, Coaches.ava, language: CoachLanguage.es)!['name'], 'Paulina');
      expect(DeviceVoiceService.pickVoice(voices, Coaches.ethan, language: CoachLanguage.es)!['name'], 'Juan');
    });
  });

  group('speech recognition locale', () {
    test('mic recognition uses the mic language with regional fallbacks, on device only (D7 fixed)', () {
      final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
      expect(chat, contains('ReplyLanguage.forMic(_state.selectedCoach'));
      expect(chat, contains('fallbackLocales: locales.sublist(1)'));
      final speech = File('lib/services/speech_service.dart').readAsStringSync();
      expect(speech, contains("locale.replaceAll('-', '_')"));
      expect(speech, contains('onDevice: true'));
      expect(speech, contains('await _stt.locales()'));
    });
  });

  group('iOS permission strings (EN + ES)', () {
    const keys = ['NSMicrophoneUsageDescription', 'NSSpeechRecognitionUsageDescription'];
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final en = File('ios/Runner/en.lproj/InfoPlist.strings').readAsStringSync();
    final es = File('ios/Runner/es.lproj/InfoPlist.strings').readAsStringSync();

    test('both keys exist in Info.plist, en.lproj and es.lproj', () {
      for (final k in keys) {
        expect(plistString(plist, k), isNotEmpty, reason: 'Info.plist $k');
        expect(plistString(en, k), plistString(plist, k), reason: 'en.lproj $k matches Info.plist');
        expect(plistString(es, k), isNotEmpty, reason: 'es.lproj $k');
        expect(plistString(es, k), isNot(plistString(en, k)), reason: 'es.lproj $k is translated');
      }
      expect(plist, contains('<string>es</string>'), reason: 'CFBundleLocalizations lists es');
    });

    test('the Spanish strings are Spanish and name the purpose', () {
      expect(plistString(es, 'NSMicrophoneUsageDescription'), contains('micrófono'));
      expect(plistString(es, 'NSSpeechRecognitionUsageDescription'), contains('texto'));
    });

    test('InfoPlist.strings files are in the Xcode project with the es region', () {
      final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(pbx, contains('es.lproj/InfoPlist.strings'));
      expect(pbx, contains('en.lproj/InfoPlist.strings'));
      expect(RegExp(r'knownRegions = \([^)]*\bes,', multiLine: true).hasMatch(pbx), isTrue);
    });
  });

  group('copy honesty: still portraits + voice, no animation or lip-sync claims', () {
    final banned = RegExp(
      r'animat|lip[- ]?sync|lip sync|lips move|video call|videollamada|live avatar|talking avatar|'
      r'avatar animado|avatar que habla|sincroniza|labios|moving portrait|facetime|face[- ]to[- ]face|cara a cara',
      caseSensitive: false,
    );
    final files = [
      'lib/l10n/app_en.arb',
      'lib/l10n/app_es.arb',
      'docs/appstore/metadata.md',
      'lib/content/legal_text.dart',
      'lib/models/coach.dart',
    ];
    for (final f in files) {
      test(f, () {
        final hits = File(f)
            .readAsLinesSync()
            .asMap()
            .entries
            .where((e) => banned.hasMatch(e.value))
            .map((e) => '$f:${e.key + 1}: ${e.value.trim()}')
            .toList();
        expect(hits, isEmpty);
      });
    }
  });
}
