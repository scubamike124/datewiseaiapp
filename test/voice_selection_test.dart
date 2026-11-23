// Each coach gets a distinct, gender- and language-appropriate system voice
// (DeviceVoiceService.pickVoice), checked against fake getVoices lists shaped
// like iOS (name, locale, quality, gender, identifier) and Android (name,
// locale only).

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

String? pick(List<Map<String, String>> voices, Coach c) => DeviceVoiceService.pickVoice(voices, c)?['name'];

void main() {
  // A typical iPhone with US English and Mexican/Spanish voices installed.
  final iphone = [
    v('Samantha', 'en-US', gender: 'female'),
    v('Ava', 'en-US', gender: 'female', quality: 'enhanced'),
    v('Evan', 'en-US', gender: 'male', quality: 'enhanced'),
    v('Daniel', 'en-GB', gender: 'male'),
    v('Karen', 'en-AU', gender: 'female'),
    v('Paulina', 'es-MX', gender: 'female', quality: 'enhanced'),
    v('Juan', 'es-MX', gender: 'male'),
    v('Mónica', 'es-ES', gender: 'female'),
    v('Jorge', 'es-ES', gender: 'male'),
  ];

  test('four coaches, four different voices, matching language and gender', () {
    expect(pick(iphone, Coaches.ava), 'Ava');
    expect(pick(iphone, Coaches.ethan), 'Evan');
    expect(pick(iphone, Coaches.sofia), 'Paulina');
    expect(pick(iphone, Coaches.diego), 'Juan');
    expect({for (final c in Coaches.all) pick(iphone, c)}, hasLength(4));
  });

  test('locale order: es-MX, then es-US, then es-ES (and en-US first for English)', () {
    final noMx = iphone.where((x) => x['locale'] != 'es-MX').toList()..add(v('Paulina', 'es-US', gender: 'female'));
    expect(DeviceVoiceService.pickVoice(noMx, Coaches.sofia)!['locale'], 'es-US');
    final onlySpain = iphone.where((x) => !x['locale']!.startsWith('es-MX')).toList();
    expect(pick(onlySpain, Coaches.sofia), 'Mónica');
    expect(pick(onlySpain, Coaches.diego), 'Jorge');
    expect(DeviceVoiceService.pickVoice(iphone, Coaches.ethan)!['locale'], 'en-US', reason: 'Evan (en-US) over Daniel (en-GB)');
  });

  test('gender beats locale order: a female es-ES voice over a male es-MX one for Sofía', () {
    final voices = [v('Juan', 'es-MX', gender: 'male'), v('Mónica', 'es-ES', gender: 'female')];
    expect(pick(voices, Coaches.sofia), 'Mónica');
    expect(pick(voices, Coaches.diego), 'Juan');
  });

  test('without gender metadata (Android, older iOS), the curated name lists decide', () {
    final voices = [
      {'name': 'Samantha', 'locale': 'en-US'},
      {'name': 'Alex', 'locale': 'en-US'},
      {'name': 'Paulina', 'locale': 'es-MX'},
      {'name': 'Juan', 'locale': 'es_MX'}, // underscore locales are normalized
    ];
    expect(pick(voices, Coaches.ava), 'Samantha');
    expect(pick(voices, Coaches.ethan), 'Alex');
    expect(pick(voices, Coaches.sofia), 'Paulina');
    expect(pick(voices, Coaches.diego), 'Juan');
  });

  test('a known other-gender name is avoided when an unknown voice exists', () {
    final voices = [
      {'name': 'Juan', 'locale': 'es-MX'},
      {'name': 'es-mx-x-esc-local', 'locale': 'es-MX'},
    ];
    expect(pick(voices, Coaches.sofia), 'es-mx-x-esc-local');
  });

  test('quality breaks ties within the same gender and locale', () {
    final voices = [v('Zoe', 'en-US', gender: 'female'), v('Zoe', 'en-US', gender: 'female', quality: 'premium')];
    expect(DeviceVoiceService.pickVoice(voices, Coaches.ava)!['quality'], 'premium');
  });

  test('a downloaded Premium/Enhanced voice beats a default voice, even one with a better-known name', () {
    final voices = [
      v('Samantha', 'en-US', gender: 'female'),
      v('Zoe', 'en-US', gender: 'female', quality: 'premium'),
      v('Juan', 'es-MX', gender: 'male'),
      v('Diego', 'es-MX', gender: 'male', quality: 'enhanced'),
    ];
    expect(pick(voices, Coaches.ava), 'Zoe');
    expect(pick(voices, Coaches.diego), 'Diego');
  });

  test('a coach speaking the other language gets a different voice from that language\'s own coach when one exists', () {
    final voices = [
      v('Paulina', 'es-MX', gender: 'female', quality: 'enhanced'),
      v('Marisol', 'es-MX', gender: 'female'),
      v('Juan', 'es-MX', gender: 'male'),
      v('Ava', 'en-US', gender: 'female'),
      v('Evan', 'en-US', gender: 'male'),
      v('Tom', 'en-US', gender: 'male'),
    ];
    String? d(Coach c, CoachLanguage l) => DeviceVoiceService.pickVoiceDistinct(voices, c, l)?['name'];
    expect(d(Coaches.sofia, CoachLanguage.es), 'Paulina');
    expect(d(Coaches.ava, CoachLanguage.es), 'Marisol', reason: 'not Sofía\'s Paulina');
    expect(d(Coaches.diego, CoachLanguage.en), 'Tom', reason: 'not Ethan\'s Evan');
    expect(d(Coaches.ethan, CoachLanguage.es), 'Juan', reason: 'only one Spanish male voice: shared, pitch differs');
  });

  test('a single voice per language: both coaches use it; pitch and rate tell them apart', () {
    final voices = [v('Samantha', 'en-US', gender: 'female'), v('Paulina', 'es-MX', gender: 'female')];
    expect(pick(voices, Coaches.ethan), 'Samantha', reason: 'last resort: right language, other gender');
    expect(pick(voices, Coaches.diego), 'Paulina');
    final profiles = Coaches.all.map(CoachVoiceProfile.of).toList();
    expect({for (final p in profiles) (p.pitch, p.rate)}, hasLength(4), reason: 'every coach sounds different');
    expect(CoachVoiceProfile.of(Coaches.ethan).pitch, lessThan(CoachVoiceProfile.of(Coaches.ava).pitch));
    expect(CoachVoiceProfile.of(Coaches.diego).pitch, lessThan(CoachVoiceProfile.of(Coaches.sofia).pitch));
  });

  test('never a voice in the wrong language; none at all → null (system default for the locale)', () {
    final english = [v('Samantha', 'en-US', gender: 'female')];
    expect(pick(english, Coaches.sofia), isNull);
    expect(pick(const [], Coaches.ava), isNull);
  });

  test('voice profiles: English coaches use en-US first, Spanish coaches es-MX, es-US, es-ES', () {
    expect(CoachVoiceProfile.of(Coaches.ava).locales.first, 'en-US');
    expect(CoachVoiceProfile.of(Coaches.sofia).locales.take(3), ['es-MX', 'es-US', 'es-ES']);
    expect(CoachVoiceProfile.of(Coaches.sofia).preferredNames, containsAll(['Paulina', 'Mónica']));
    expect(CoachVoiceProfile.of(Coaches.diego).preferredNames, containsAll(['Juan', 'Jorge']));
    expect(CoachVoiceProfile.of(Coaches.ava).preferredNames, containsAll(['Samantha', 'Ava']));
    expect(CoachVoiceProfile.of(Coaches.ethan).preferredNames, containsAll(['Alex', 'Daniel', 'Evan', 'Nathan']));
  });
}
