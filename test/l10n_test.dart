// English and Spanish app chrome: language resolution, ARB completeness,
// coach-name spelling, US spelling, and the main screens in Spanish.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/content/legal_text.dart';
import 'package:datewise_ai/l10n/l10n.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/screens/legal_screen.dart';
import 'package:datewise_ai/screens/onboarding_screen.dart';
import 'package:datewise_ai/screens/paywall_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/screens/welcome_screen.dart';

import 'helpers.dart';

Map<String, dynamic> arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('language', () {
    test('device locale: any es* is Spanish, everything else English', () {
      expect(AppLocales.resolve(const [Locale('es', 'MX')]), AppLocales.es);
      expect(AppLocales.resolve(const [Locale('es', 'ES')]), AppLocales.es);
      expect(AppLocales.resolve(const [Locale('es', 'US')]), AppLocales.es);
      expect(AppLocales.resolve(const [Locale('es', '419')]), AppLocales.es);
      expect(AppLocales.resolve(const [Locale('en', 'US')]), AppLocales.en);
      expect(AppLocales.resolve(const [Locale('fr', 'FR')]), AppLocales.en);
      expect(AppLocales.resolve(const [Locale('fr'), Locale('es')]), AppLocales.es, reason: 'first supported preference');
      expect(AppLocales.resolve(null), AppLocales.en);
    });

    testWidgets('a Spanish device starts in Spanish before any choice', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('es', 'MX')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await pumpApp(tester);
      expect(find.text('Comenzar'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);
    });

    testWidgets('the onboarding/Settings choice overrides the device language', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('es', 'MX')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final app = await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.you);
      expect(find.text('Language'), findsOneWidget, reason: 'English was chosen');
      await tester.tap(find.byKey(const ValueKey('row-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-es')));
      await tester.pumpAndSettle();
      expect(app.state.language, CoachLanguage.es);
      expect(find.text('Idioma'), findsOneWidget);
      expect(find.text('Tus datos'.toUpperCase()), findsOneWidget);
      expect(app.storage.loadProfile()!.language, CoachLanguage.es, reason: 'saved');
    });
  });

  group('ARB catalog', () {
    final en = arb('en');
    final es = arb('es');
    final keys = en.keys.where((k) => !k.startsWith('@')).toSet();

    test('every English string has a Spanish translation', () {
      final esKeys = es.keys.where((k) => !k.startsWith('@')).toSet();
      expect(esKeys, keys);
      for (final k in keys) {
        if (k == 'legalTranslationNote') continue; // only shown in Spanish
        expect((es[k] as String).trim(), isNotEmpty, reason: k);
        expect((en[k] as String).trim(), isNotEmpty, reason: k);
      }
    });

    test('placeholders match between languages', () {
      final ph = RegExp(r'(?<!\w)\{(\w+)[,}]');
      for (final k in keys) {
        final a = ph.allMatches(en[k] as String).map((m) => m[1]).toSet();
        final b = ph.allMatches(es[k] as String).map((m) => m[1]).toSet();
        expect(b.difference(a.union({'gender'})), isEmpty, reason: k);
      }
    });

    test('coach names are spelled Ava, Ethan, Sofía, Diego (with the accent)', () {
      final all = [...en.values, ...es.values].whereType<String>().join('\n');
      expect(all, isNot(contains('Sofia')));
      expect(all, contains('Sofía'));
      expect(Coaches.all.map((c) => c.name), ['Ava', 'Ethan', 'Sofía', 'Diego']);
    });

    test('Spanish is neutral Latin-American: no vosotros/voseo forms, no "ordenador"/"móvil"', () {
      final text = es.values.whereType<String>().join('\n').toLowerCase();
      for (final w in ['vosotros', 'os', 'habéis', 'tenéis', 'podéis', 'ordenador', 'móvil', 'vos', 'querés', 'tenés', 'coger']) {
        expect(RegExp('(?<![\\wáéíóúñ])$w(?![\\wáéíóúñ])').hasMatch(text), isFalse, reason: w);
      }
    });
  });

  test('US spelling everywhere in app code, copy and docs', () {
    final uk = RegExp(
      r'\b(practis(e|es|ed|ing)|labell(ed|ing)|cancell(ed|ing)|colou?rs?\b(?<=colour)|colour(s|ed|ful)?|favourite|personalis(e|ed|es|ation)|organis(e|ed|ation)|recognis(e|ed|er)|analys(e|es|ed|ing)\b|initialis(e|ed)|optimis(e|ed)|sanitis(e|es|ed)|localis(e|ed|ation)|behaviour|centre|licence|honour|got to\b(?= \?))',
      caseSensitive: false,
    );
    final files = [
      ...Directory('lib').listSync(recursive: true),
      ...Directory('test').listSync(recursive: true),
    ].whereType<File>().where((f) => f.path.endsWith('.dart') || f.path.endsWith('.arb'));
    final hits = <String>[];
    for (final f in files) {
      if (f.path.endsWith('l10n_test.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // `analyses` as the plural noun (photo analyses) is fine in US English.
        final line = lines[i].replaceAll(RegExp(r'analyses\b(?! the| several| an| one)', caseSensitive: false), '');
        if (uk.hasMatch(line)) hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  group('screens in Spanish', () {
    const es = Locale('es');

    testWidgets('welcome', (tester) async {
      await pumpScreen(tester, const WelcomeScreen(), locale: es);
      expect(find.text('Comenzar'), findsOneWidget);
      expect(find.text('Mejores conversaciones'), findsOneWidget);
      expect(find.text('Ava · Coach con IA · Inglés'), findsOneWidget);
    });

    testWidgets('onboarding steps', (tester) async {
      await pumpScreen(tester, const OnboardingScreen(), locale: es);
      expect(find.text('¿Con qué te gustaría recibir ayuda?'), findsOneWidget);
      expect(find.text('PASO 1 DE 4'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      await pumpScreen(tester, const OnboardingScreen(key: ValueKey('step-4'), initialStep: 3), locale: es);
      expect(find.text('Elige a tu coach de citas'), findsOneWidget);
      expect(find.text('Chatear con Sofía'), findsOneWidget);
      expect(find.text('Coach de confianza. Directa, solidaria y enfocada en resultados.'), findsOneWidget);
    });

    testWidgets('home, coaches, chat, progress, settings with Sofía', (tester) async {
      await pumpApp(tester, prefs: spanishPrefs());
      expect(find.text('TU PLAN DE ESTA SEMANA'), findsOneWidget);
      expect(find.text('Hablar con Sofía'), findsOneWidget);
      expect(find.textContaining('Sofía está lista'), findsOneWidget, reason: 'feminine agreement');
      expect(find.text('Practicar una conversación'), findsOneWidget);
      for (final t in ['Inicio', 'Coaches', 'Chat', 'Progreso', 'Tú']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.byKey(const ValueKey('tab-chat')));
      await tester.pumpAndSettle();
      expect(find.text('Coach de citas con IA · Español'), findsOneWidget);
      expect(find.text('Escríbele a Sofía…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-progress')));
      await tester.pumpAndSettle();
      expect(find.text('Progreso'), findsWidgets);
      expect(find.text('0 de 3 hechos'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-you')));
      await tester.pumpAndSettle();
      expect(find.text('Memoria del coach'), findsWidgets);
      expect(find.text('Eliminar mis datos'), findsOneWidget);
      expect(find.text('No cancela tu suscripción. Cancélala en la configuración de Apple.'), findsOneWidget);
    });

    testWidgets('Diego gets masculine agreement', (tester) async {
      await pumpApp(tester, prefs: onboardedPrefs(coach: 'diego', language: 'es'));
      expect(find.textContaining('Diego está listo'), findsOneWidget);
    });

    testWidgets('paywall with Apple disclosures', (tester) async {
      await pumpScreen(tester, PaywallScreen(onClose: () {}), locale: es, entitled: false, prefs: spanishPrefs());
      expect(find.text('DATEWISE PREMIUM'), findsOneWidget);
      expect(find.text(r'Suscribirme por $9.99/mes'), findsOneWidget);
      expect(find.text('al mes'), findsOneWidget);
      expect(find.text('Mensual · renovación automática'), findsOneWidget);
      final disclosure = tester.widget<Text>(find.byKey(const ValueKey('paywall-disclosure'))).data!;
      expect(disclosure, startsWith(r'$9.99/mes.'));
      expect(disclosure, contains('Apple ID'));
      expect(disclosure, contains('se renueva automáticamente cada mes'));
      expect(disclosure, contains('Configuración › Apple ID › Suscripciones'));
      expect(find.text('Restaurar compras'), findsOneWidget);
    });

    testWidgets('legal screens: Spanish titles and translated text, marked as a translation', (tester) async {
      await pumpScreen(tester, const LegalScreen.doc(LegalDoc.privacy), locale: es);
      expect(find.text('Política de privacidad'), findsOneWidget);
      expect(find.byKey(const ValueKey('legal-translation-note')), findsOneWidget);
      expect(find.text('Información que proporcionas'), findsOneWidget);
      await pumpScreen(tester, const LegalScreen.doc(LegalDoc.terms), locale: es);
      expect(find.text('Términos de uso'), findsOneWidget);
      expect(kTermsOfServiceEs, contains('Configuración › Apple ID › Suscripciones'));
      await pumpScreen(tester, const LegalScreen.doc(LegalDoc.terms));
      expect(find.text('Terms of Use'), findsOneWidget);
      expect(find.byKey(const ValueKey('legal-translation-note')), findsNothing);
    });

    testWidgets('store errors are localized', (tester) async {
      final es = lookupAppLocalizations(const Locale('es'));
      expect(es.purchaseFailed, 'No se pudo completar la compra. Inténtalo de nuevo.');
      expect(es.noSubscriptionForAppleId, contains('Apple ID'));
    });
  });
}
