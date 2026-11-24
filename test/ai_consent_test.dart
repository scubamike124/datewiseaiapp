// App Store Guideline 5.1.2(i): before the first message is sent to the
// third-party AI provider (Cloudflare Workers AI), the app asks once for
// permission. Nothing is sent without it, and Delete my data withdraws it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/screens/shell.dart';

import 'helpers.dart';

/// Onboarded and subscribed, but not yet asked about the AI provider.
Map<String, Object> _noConsent({String language = 'en'}) =>
    {...onboardedPrefs(coach: language == 'es' ? 'sofia' : 'ava', language: language)}..remove('dw_ai_consent');

String _composerText(WidgetTester t) => t.widget<TextField>(find.byKey(const ValueKey('composer'))).controller!.text;

const _titleEn = 'Share messages with our AI provider?';

void main() {
  testWidgets('the first send asks for consent; Not now sends nothing and keeps the text', (t) async {
    final app = await pumpApp(t, prefs: _noConsent(), tab: AppTab.chat);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('composer')), 'Give me a strong opener');
    await t.tap(find.byKey(const ValueKey('send')));
    await t.pumpAndSettle();

    expect(find.text(_titleEn), findsOneWidget);
    expect(find.textContaining('Cloudflare Workers AI'), findsOneWidget);
    expect(find.textContaining("Meta's Llama"), findsOneWidget);
    expect(find.text('Agree'), findsOneWidget);
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();

    expect(find.text(_titleEn), findsNothing);
    expect(app.state.threads.expand((th) => th.messages), isEmpty, reason: 'nothing is sent');
    expect(app.state.isResponding, isFalse);
    expect(_composerText(t), 'Give me a strong opener', reason: 'the text stays in the composer');
    expect(app.state.aiConsentGiven, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('dw_ai_consent'), isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('Agree sends the message, is stored, and is not asked again', (t) async {
    final app = await pumpApp(t, prefs: _noConsent(), tab: AppTab.chat);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('composer')), 'Give me a strong opener');
    await t.tap(find.byKey(const ValueKey('send')));
    await t.pumpAndSettle();
    await t.tap(find.text('Agree'));
    await t.pump();
    await settleReply(t, app.state);

    expect(app.state.aiConsentGiven, isTrue);
    expect((await SharedPreferences.getInstance()).getBool('dw_ai_consent'), isTrue);
    final messages = app.state.activeThread!.messages;
    expect(messages.where((m) => m.isUser).map((m) => m.text), ['Give me a strong opener']);
    expect(messages.last.isUser, isFalse);
    expect(_composerText(t), isEmpty);

    await t.enterText(find.byKey(const ValueKey('composer')), 'And a second one');
    await t.tap(find.byKey(const ValueKey('send')));
    await t.pump();
    expect(find.text(_titleEn), findsNothing, reason: 'asked only once');
    await settleReply(t, app.state);
    expect(app.state.activeThread!.messages.where((m) => m.isUser).length, 2);
  });

  testWidgets('Spanish: the consent is asked in Spanish', (t) async {
    await pumpApp(t, prefs: _noConsent(language: 'es'), tab: AppTab.chat);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('composer')), 'Quiero una cita');
    await t.tap(find.byKey(const ValueKey('send')));
    await t.pumpAndSettle();
    expect(find.text('¿Compartir tus mensajes con nuestro proveedor de IA?'), findsOneWidget);
    expect(find.text('Aceptar'), findsOneWidget);
    expect(find.text('Ahora no'), findsOneWidget);
    await t.tap(find.text('Ahora no'));
    await t.pumpAndSettle();
    expect(_composerText(t), 'Quiero una cita');
  });

  test('AppState.sendMessage refuses without consent', () async {
    final app = await makeState(prefs: _noConsent());
    expect(app.state.canChat, isTrue);
    expect(await app.state.sendMessage('Hello'), isFalse);
    expect(app.state.threads.expand((th) => th.messages), isEmpty);
    expect(app.state.isResponding, isFalse);
  });

  test('consent is restored after a restart and Delete my data withdraws it', () async {
    final app = await makeState(prefs: _noConsent());
    await app.state.giveAiConsent();
    expect(app.storage.aiConsent, isTrue);
    expect(await app.state.sendMessage('Hello'), isTrue);

    await app.state.deleteMyData();
    expect(app.state.aiConsentGiven, isFalse);
    expect(app.storage.aiConsent, isFalse);
    expect(await app.state.sendMessage('Hello again'), isFalse);
  });
}
