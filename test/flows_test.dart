// End-to-end flows on the real screens with the offline coach and the fake
// store: onboarding to paywall to chat, quick actions, plan ticks, Coach
// memory and Delete my data.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/store_service.dart';

import 'helpers.dart';

void main() {
  testWidgets('new user: welcome → goals → language → 18+ → coach → paywall → subscribe → chat', (tester) async {
    final app = await pumpApp(tester, entitled: false);
    expect(find.text('Sign in'), findsNothing, reason: 'there is no account backend');
    await tester.ensureVisible(find.byKey(const ValueKey('get-started')));
    await tester.tap(find.byKey(const ValueKey('get-started')));
    await tester.pumpAndSettle();

    // Goals: Continue is disabled until one is picked.
    await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
    await tester.pumpAndSettle();
    expect(find.text('What would you like help with?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('goal-confidence')));
    await tester.tap(find.byKey(const ValueKey('goal-conversations')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
    await tester.pumpAndSettle();

    // Language: choosing Español switches the whole app to Spanish at once.
    expect(find.text('Choose your language'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lang-es')));
    await tester.pumpAndSettle();
    expect(find.text('Elige tu idioma'), findsOneWidget);
    expect(find.text('Continuar'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
    await tester.pumpAndSettle();

    // 18+ must be confirmed.
    await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
    await tester.pumpAndSettle();
    expect(find.text('DateWise es solo para adultos.'), findsOneWidget);
    expect(find.text('Tengo 18 años o más'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('age-confirm')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
    await tester.pumpAndSettle();

    // Coach: Spanish coaches first for a Spanish speaker.
    final sofia = tester.getTopLeft(find.byKey(const ValueKey('coach-card-sofia')));
    final ava = tester.getTopLeft(find.byKey(const ValueKey('coach-card-ava')));
    expect(sofia.dy, lessThan(ava.dy));
    await tester.tap(find.byKey(const ValueKey('chat-sofia')));
    await tester.pumpAndSettle();

    // Paywall, before any chat, in Spanish with Apple's disclosures.
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
    expect(app.state.selectedCoach, Coaches.sofia);
    expect(app.state.plan!.items.first.goal.name, 'confidence');
    final disclosure = tester.widget<Text>(find.byKey(const ValueKey('paywall-disclosure'))).data!;
    expect(disclosure, contains(r'$9.99/mes'));
    expect(disclosure, contains('se renueva automáticamente cada mes'));
    expect(disclosure, contains('24 horas antes'));
    expect(disclosure, contains('Configuración › [tu nombre] › Suscripciones'));
    expect(disclosure, contains('Cuenta de Apple'));
    expect(find.text('Restaurar compras'), findsOneWidget);
    expect(find.text('Términos de uso'), findsOneWidget);
    expect(find.text('Privacidad'), findsOneWidget);
    expect(find.text(r'Suscribirme por $9.99/mes'), findsOneWidget);
    expect(find.textContaining('prueba'), findsNothing);
    expect(find.textContaining('gratis', findRichText: true), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('paywall-subscribe')));
    await tester.tap(find.byKey(const ValueKey('paywall-subscribe')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(app.store.isEntitled, isTrue);
    expect(find.byKey(const ValueKey('tab-home')), findsOneWidget);

    // Spanish tabs; chat with Sofía, labeled as AI.
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Progreso'), findsOneWidget);
    expect(find.text('Tú'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab-chat')));
    await tester.pumpAndSettle();
    expect(find.text('Coach de citas con IA · Español'), findsOneWidget);
    expect(find.text('Escríbele a Sofía…'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('composer')), 'Quiero una cita');
    await tester.tap(find.byKey(const ValueKey('send')));
    await tester.pump();
    await settleReply(tester, app.state);
    expect(app.state.activeThread!.messages.last.text, contains('lugar público'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('under 18 cannot continue', (tester) async {
    await pumpApp(tester, entitled: false);
    await tester.ensureVisible(find.byKey(const ValueKey('get-started')));
    await tester.tap(find.byKey(const ValueKey('get-started')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-profile')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('age-under')));
    await tester.pumpAndSettle();
    expect(find.text('Sorry, DateWise is only for adults.'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-continue')), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-back')), findsNothing, reason: 'no way back into onboarding');
  });

  testWidgets('closing the paywall keeps chat locked; subscribing from chat unlocks it', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs(), entitled: false);
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paywall-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-chat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('locked-subscribe')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('paywall-subscribe')));
    await tester.tap(find.byKey(const ValueKey('paywall-subscribe')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(app.store.isEntitled, isTrue);
    expect(find.byKey(const ValueKey('composer')), findsOneWidget);
  });

  testWidgets('web build without purchases says to subscribe in the iPhone app', (tester) async {
    await pumpApp(tester, prefs: onboardedPrefs(), store: UnsupportedStoreService());
    expect(find.text('Subscribe in the iPhone app. Purchases are not available on the web.'), findsOneWidget);
    expect(find.byKey(const ValueKey('paywall-subscribe')), findsNothing);
  });

  testWidgets('a quick action opens the chat and sends its starter prompt', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs());
    await tester.ensureVisible(find.byKey(const ValueKey('tile-reply')));
    await tester.tap(find.byKey(const ValueKey('tile-reply')));
    await tester.pump();
    await tester.pump();
    expect(app.state.activeThread!.messages.where((m) => m.isUser).single.text, 'Help me reply to a message.');
    await settleReply(tester, app.state);
    expect(find.byKey(const ValueKey('composer')), findsOneWidget);
  });

  testWidgets('voice buttons are hidden when speech is unavailable', (tester) async {
    await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.chat);
    expect(find.byKey(const ValueKey('voice-mode')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab-home')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-voice')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab-coaches')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-ava')), findsNothing, reason: 'no TTS, no voice preview');
  });

  testWidgets('ticking a plan item on Home persists and shows in Progress', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs());
    await tester.tap(find.byKey(const ValueKey('plan-0')));
    await tester.pump();
    expect(app.state.plan!.items[0].done, isTrue);
    expect(app.storage.loadPlan()!.items[0].done, isTrue);
    await tester.tap(find.byKey(const ValueKey('tab-progress')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 done'), findsOneWidget);
  });

  testWidgets('Coach memory toggle (off by default), edit and clear', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.you);
    expect(app.state.memoryEnabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('row-memory')));
    await tester.pump();
    expect(app.state.memoryEnabled, isTrue);
    await tester.tap(find.byKey(const ValueKey('row-memory-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('memory-field')), 'Shy at first.');
    await tester.tap(find.byKey(const ValueKey('memory-save')));
    await tester.pumpAndSettle();
    expect(app.state.memoryText, 'Shy at first.');
    expect(find.text('Shy at first.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('row-memory-clear')));
    await tester.tap(find.byKey(const ValueKey('row-memory-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-action')));
    await tester.pumpAndSettle();
    expect(app.state.memoryText, isEmpty);
  });

  testWidgets('Delete my data returns to the welcome screen', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.you);
    await tester.ensureVisible(find.byKey(const ValueKey('row-delete-data')));
    await tester.tap(find.byKey(const ValueKey('row-delete-data')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('welcome')), findsOneWidget);
    expect(app.state.onboarded, isFalse);
  });

  testWidgets('switching coach from the Coaches tab opens their chat', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.coaches);
    await tester.ensureVisible(find.byKey(const ValueKey('chat-diego')));
    await tester.tap(find.byKey(const ValueKey('chat-diego')));
    await tester.pumpAndSettle();
    expect(app.state.selectedCoach, Coaches.diego);
    expect(find.text('Message Diego…'), findsOneWidget, reason: 'English UI');
  });
}
