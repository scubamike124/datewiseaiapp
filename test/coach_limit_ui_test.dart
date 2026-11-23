// The chat-v7 limit UI: a refused reply shows its localized limit notice (EN
// and ES), "Try again" only where an instant retry can help, a paywall button
// for subscription refusals, the reason is saved with the message, and the
// soft fair-use notice sits above the composer. No copy says "unlimited".

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/coach_usage.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';

import 'helpers.dart';

/// Refuses every reply with [code] (HTTP [status]).
class _RefusingAI implements AIService {
  _RefusingAI(this.status, this.code);
  final int status;
  final String code;

  @override
  String get providerLabel => 'refusing';

  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) =>
      Stream.error(CoachUnavailableException('http', statusCode: status, code: code));
}

Future<TestApp> _pumpChat(WidgetTester tester, AIService ai, Map<String, Object> prefs) async {
  setSurface(tester, const Size(390, 844), 1);
  SharedPreferences.setMockInitialValues(prefs);
  final storage = await StorageService.create();
  final store = FakeStoreService(entitled: true);
  final app = TestApp(AppState(storage: storage, ai: ai, store: store), store, storage);
  await tester.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat)));
  await tester.pump();
  return app;
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('composer')), text);
  await tester.tap(find.byKey(const ValueKey('send')));
  await tester.pumpAndSettle();
}

String _notice(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('reply-failed-notice'))).data!;

void main() {
  tearDown(() => CoachUsage.state.value = null);

  for (final (lang, prefs, code, status, text, retry) in [
    ('en', onboardedPrefs(), CoachLimitCode.dailyLimit, 429,
        "You've reached today's coaching limit. It resets at midnight (UTC).", false),
    ('es', spanishPrefs(), CoachLimitCode.dailyLimit, 429,
        'Llegaste al límite de coaching de hoy. Se restablece a la medianoche (UTC).', false),
    ('en', onboardedPrefs(), CoachLimitCode.monthlyLimit, 429,
        "You've reached this month's fair-use limit. It resets on the 1st.", false),
    ('es', spanishPrefs(), CoachLimitCode.monthlyLimit, 429,
        'Llegaste al límite de uso justo de este mes. Se restablece el día 1.', false),
    ('en', onboardedPrefs(), CoachLimitCode.rateLimited, 429,
        "You're sending messages quickly. Please wait a moment and try again.", true),
    ('es', spanishPrefs(), CoachLimitCode.rateLimited, 429,
        'Estás enviando mensajes muy rápido. Espera un momento e inténtalo de nuevo.', true),
    ('en', onboardedPrefs(), CoachLimitCode.serviceBudgetExhausted, 503,
        'Coaching is busy right now. Please try again later.', true),
    ('es', spanishPrefs(), CoachLimitCode.subscriptionExpired, 403,
        'Tu suscripción a DateWise Premium no está activa. Renuévala para seguir chateando.', true),
    ('en', onboardedPrefs(), CoachLimitCode.subscriptionRevoked, 403,
        'This purchase was refunded or revoked, so coaching is locked.', false),
    ('es', spanishPrefs(), CoachLimitCode.appUpdateRequired, 426,
        'Actualiza DateWise a la última versión para seguir chateando con tu coach.', false),
  ]) {
    testWidgets('[$lang] $code shows its limit notice, ${retry ? 'with' : 'without'} "Try again"', (tester) async {
      final app = await _pumpChat(tester, _RefusingAI(status, code), prefs);
      await _send(tester, 'Hi');
      expect(_notice(tester), text);
      expect(find.byKey(const ValueKey('retry')), retry ? findsOneWidget : findsNothing);
      expect(app.state.canRetry, retry);
      expect(_notice(tester).toLowerCase(), isNot(contains('unlimited')));
      expect(_notice(tester).toLowerCase(), isNot(contains('ilimitad')));
    });
  }

  // Subscription refusals offer the paywall (Subscribe, Restore purchases) in the bubble itself.
  for (final (lang, prefs, code, label) in [
    ('en', onboardedPrefs(), CoachLimitCode.subscriptionRevoked, 'See DateWise Premium'),
    ('es', spanishPrefs(), CoachLimitCode.subscriptionRevoked, 'Ver DateWise Premium'),
    ('en', onboardedPrefs(), CoachLimitCode.subscriptionExpired, 'See DateWise Premium'),
    ('es', spanishPrefs(), CoachLimitCode.subscriptionExpired, 'Ver DateWise Premium'),
    ('en', onboardedPrefs(), CoachLimitCode.subscriptionRequired, 'See DateWise Premium'),
    ('es', spanishPrefs(), CoachLimitCode.subscriptionRequired, 'Ver DateWise Premium'),
    ('en', onboardedPrefs(), CoachLimitCode.subscriptionInvalid, 'Restore purchases'),
    ('es', spanishPrefs(), CoachLimitCode.subscriptionInvalid, 'Restaurar compras'),
  ]) {
    testWidgets('[$lang] $code offers "$label", which opens the paywall with Restore purchases', (tester) async {
      await _pumpChat(tester, _RefusingAI(403, code), prefs);
      await _send(tester, 'Hi');
      final button = find.byKey(const ValueKey('reply-paywall'));
      expect(button, findsOneWidget);
      expect(find.descendant(of: button, matching: find.text(label)), findsOneWidget);
      // Revoked: no instant retry, so the paywall is the only action. The others keep "Try again".
      expect(find.byKey(const ValueKey('retry')),
          code == CoachLimitCode.subscriptionRevoked ? findsNothing : findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-restore')), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-subscribe')), findsOneWidget);
    });
  }

  for (final code in [CoachLimitCode.dailyLimit, CoachLimitCode.guardUnavailable, CoachLimitCode.appUpdateRequired, 'SOMETHING_NEW']) {
    testWidgets('$code does not offer the paywall', (tester) async {
      await _pumpChat(tester, _RefusingAI(429, code), onboardedPrefs());
      await _send(tester, 'Hi');
      expect(find.byKey(const ValueKey('reply-failed-notice')), findsOneWidget);
      expect(find.byKey(const ValueKey('reply-paywall')), findsNothing);
    });
  }

  testWidgets('an unknown code falls back to the status notice', (tester) async {
    await _pumpChat(tester, _RefusingAI(429, 'SOMETHING_NEW'), onboardedPrefs());
    await _send(tester, 'Hi');
    expect(_notice(tester), 'Your coach is getting a lot of messages right now. Try again in a moment. Your message is saved.');
    expect(find.byKey(const ValueKey('retry')), findsOneWidget);
  });

  testWidgets('the refusal code is saved with the reply and shown again after a restart', (tester) async {
    final app = await _pumpChat(tester, _RefusingAI(429, CoachLimitCode.dailyLimit), onboardedPrefs());
    await _send(tester, 'Hi');
    final last = app.state.activeThread!.messages.last;
    expect(last.failedCode, CoachLimitCode.dailyLimit);
    expect(last.failedStatus, 429);

    final store = FakeStoreService(entitled: true);
    final restarted = TestApp(
        AppState(storage: await StorageService.create(), ai: _RefusingAI(429, 'X'), store: store), store, app.storage);
    expect(restarted.state.activeThread!.messages.last.failedCode, CoachLimitCode.dailyLimit);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(wrap(restarted, const DateWiseApp(initialTab: AppTab.chat)));
    await tester.pumpAndSettle();
    expect(_notice(tester), "You've reached today's coaching limit. It resets at midnight (UTC).");
    expect(find.byKey(const ValueKey('retry')), findsNothing);
  });

  test('failedCode round-trips like failedStatus; junk from storage is dropped', () {
    final m = ChatMessage(
        id: '1',
        role: MessageRole.coach,
        text: '',
        createdAt: DateTime(2026),
        status: MessageStatus.failed,
        failedStatus: 429,
        failedCode: CoachLimitCode.monthlyLimit);
    final json = jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>;
    expect(json['failedCode'], 'MONTHLY_LIMIT');
    expect(ChatMessage.fromJson(json).failedCode, 'MONTHLY_LIMIT');
    expect(ChatMessage.fromJson({...json, 'failedCode': '<script>'}).failedCode, isNull);
    expect(ChatMessage.fromJson({...json, 'failedCode': 7}).failedCode, isNull);
    // Only a failed reply keeps it.
    m.status = MessageStatus.ok;
    expect(m.toJson().containsKey('failedCode'), isFalse);
  });

  for (final (lang, prefs, notice, text) in [
    ('en', onboardedPrefs(), 'approaching_daily_limit', "You're close to today's fair-use limit."),
    ('es', spanishPrefs(), 'approaching_daily_limit', 'Te estás acercando al límite de uso justo de hoy.'),
    ('en', onboardedPrefs(), 'approaching_monthly_limit', "You're close to this month's fair-use limit."),
    ('es', spanishPrefs(), 'approaching_monthly_limit', 'Te estás acercando al límite de uso justo de este mes.'),
  ]) {
    testWidgets('[$lang] the soft notice ($notice) shows above the composer', (tester) async {
      await _pumpChat(tester, _RefusingAI(503, 'X'), prefs);
      expect(find.byKey(const ValueKey('usage-notice')), findsNothing);
      CoachUsage.state.value = CoachUsageState(notice: notice);
      await tester.pump();
      expect(find.byKey(const ValueKey('usage-notice')), findsOneWidget);
      expect(find.text(text), findsOneWidget);
      final banner = tester.getRect(find.byKey(const ValueKey('usage-notice')));
      final composer = tester.getRect(find.byKey(const ValueKey('composer')));
      expect(banner.bottom, lessThanOrEqualTo(composer.top), reason: 'above the composer');
      expect(banner.height, lessThan(60), reason: 'small and unobtrusive: at most two short lines');
      // A reply without the header clears it.
      CoachUsage.state.value = const CoachUsageState();
      await tester.pump();
      expect(find.byKey(const ValueKey('usage-notice')), findsNothing);
    });
  }

  test('no copy anywhere says unlimited (EN/ES)', () {
    for (final f in ['lib/l10n/app_en.arb', 'lib/l10n/app_es.arb']) {
      final arb = jsonDecode(File(f).readAsStringSync()) as Map<String, dynamic>;
      for (final e in arb.entries) {
        if (e.key.startsWith('@') || e.value is! String) continue;
        final v = (e.value as String).toLowerCase();
        expect(v.contains('unlimited') || v.contains('ilimitad'), isFalse, reason: '$f ${e.key}');
      }
    }
  });
}
