// The fair-use disclosure cannot drift from the server: lib/config/fair_use.dart
// must equal backend/wrangler.toml, and every place that discloses the limits
// (paywall, Terms, App Store description and review notes) shows those numbers.

import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/config/fair_use.dart';
import 'package:datewise_ai/content/legal_text.dart';
import 'package:datewise_ai/l10n/app_localizations.dart';
import 'package:datewise_ai/screens/paywall_screen.dart';

int wranglerVar(String toml, String name) {
  final m = RegExp('^$name\\s*=\\s*"(\\d+)"', multiLine: true).firstMatch(toml);
  expect(m, isNotNull, reason: '$name missing from backend/wrangler.toml');
  return int.parse(m![1]!);
}

void main() {
  final toml = File('backend/wrangler.toml').readAsStringSync();
  final en = lookupAppLocalizations(const Locale('en'));
  final es = lookupAppLocalizations(const Locale('es'));

  test('FairUse equals the limits in backend/wrangler.toml', () {
    expect(FairUse.dailyReplies, wranglerVar(toml, 'DAILY_MESSAGE_LIMIT'));
    expect(FairUse.monthlyReplies, wranglerVar(toml, 'MONTHLY_MESSAGE_LIMIT'));
    expect(FairUse.perMinute, wranglerVar(toml, 'PER_MINUTE_LIMIT'));
    expect(FairUse.concurrent, wranglerVar(toml, 'MAX_CONCURRENT'));
    expect(FairUse.noticePercent, wranglerVar(toml, 'SOFT_NOTICE_PERCENT'));
    // The Worker's built-in defaults agree too (used when a var is unset).
    final guard = File('backend/cost_guard.js').readAsStringSync();
    expect(guard, contains('DAILY_MESSAGE_LIMIT: ${FairUse.dailyReplies},'));
    expect(guard, contains('MONTHLY_MESSAGE_LIMIT: ${FairUse.monthlyReplies},'));
    expect(guard, contains('PER_MINUTE_LIMIT: ${FairUse.perMinute},'));
    expect(guard, contains('MAX_CONCURRENT: ${FairUse.concurrent},'));
  });

  test('number format: 1,500 in English, 1500 in Spanish', () {
    expect(FairUse.format(1500, 'en'), '1,500');
    expect(FairUse.format(150, 'en'), '150');
    expect(FairUse.format(1234567, 'en'), '1,234,567');
    expect(FairUse.format(1500, 'es'), '1500');
    expect(FairUse.format(15000, 'es'), '15 000');
  });

  String d(String lang) => FairUse.format(FairUse.dailyReplies, lang);
  String m(String lang) => FairUse.format(FairUse.monthlyReplies, lang);

  test('the paywall line states the limits, in English and Spanish', () {
    final a = fairUseLine(en);
    expect(a, contains('up to ${d('en')} coach replies a day and ${m('en')} a month'));
    expect(a, contains('at most ${FairUse.perMinute} a minute and ${FairUse.concurrent} at a time'));
    expect(a, contains('Typed and spoken messages count the same'));
    expect(a, contains('00:00 UTC'));
    final b = fairUseLine(es);
    expect(b, contains('hasta ${d('es')} respuestas del coach al día y ${m('es')} al mes'));
    expect(b, contains('${FairUse.perMinute} por minuto y ${FairUse.concurrent} a la vez'));
    expect(b, contains('Los mensajes escritos y hablados cuentan igual'));
    expect(b, contains('00:00 UTC'));
  });

  test('the Terms of Use state the limits, in English and Spanish', () {
    expect(kTermsOfService, contains('# Fair use'));
    expect(kTermsOfService, contains('up to ${d('en')} coach replies a day and ${m('en')} a month'));
    expect(kTermsOfService, contains('Typed and spoken messages count the same.'));
    expect(kTermsOfService, contains('chat pauses until the next day (00:00 UTC) or the next month'));
    expect(kTermsOfServiceEs, contains('# Uso justo'));
    expect(kTermsOfServiceEs, contains('hasta ${d('es')} respuestas del coach al día y ${m('es')} al mes'));
    expect(kTermsOfServiceEs, contains('el chat se pausa hasta el día siguiente (00:00 UTC) o el mes siguiente'));
  });

  test('the App Store description and review notes state the same limits', () {
    final md = File('docs/appstore/metadata.md').readAsStringSync();
    expect(md, contains('> Fair use: DateWise Premium includes generous everyday coaching for personal use, '
        'up to ${d('en')} coach replies a day and ${m('en')} a month '
        '(at most ${FairUse.perMinute} a minute and ${FairUse.concurrent} at a time).'));
    expect(md, contains('> Uso justo: DateWise Premium incluye coaching diario generoso para uso personal, '
        'hasta ${d('es')} respuestas del coach al día y ${m('es')} al mes '
        '(con un máximo de ${FairUse.perMinute} por minuto y ${FairUse.concurrent} a la vez).'));
    expect(md, contains('> FAIR USE'));
    expect(md, contains('up to ${d('en')} coach replies a day and ${m('en')} a month, '
        'at most ${FairUse.perMinute} a minute and ${FairUse.concurrent} at a time'));
    expect(md, contains('Sandbox purchases (App Review and TestFlight) have a smaller limit of '
        '${wranglerVar(toml, 'SANDBOX_DAILY_LIMIT')} replies a day'));
    expect(md, contains('(Sandbox: ${wranglerVar(toml, 'SANDBOX_DAILY_LIMIT')} a day)'));
  });

  test('no disclosure says "unlimited"', () {
    final texts = [
      fairUseLine(en),
      fairUseLine(es),
      kTermsOfService,
      kTermsOfServiceEs,
      kPrivacyPolicy,
      kPrivacyPolicyEs,
      File('docs/appstore/metadata.md').readAsStringSync(),
      File('lib/l10n/app_en.arb').readAsStringSync(),
      File('lib/l10n/app_es.arb').readAsStringSync(),
    ];
    for (final t in texts) {
      expect(t.toLowerCase(), isNot(contains('unlimited')));
      expect(t.toLowerCase(), isNot(contains('ilimitad')));
    }
  });
}
