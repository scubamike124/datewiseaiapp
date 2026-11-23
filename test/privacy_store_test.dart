// Privacy and subscription: the 18+ gate cannot be bypassed, no analytics or
// tracking SDKs, Delete my data wipes the device but not the App Store
// subscription, one product only, restore, and the entitlement re-check on
// resume.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/mock_ai_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';

import 'helpers.dart';

Future<void> toAgeStep(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('get-started')));
  await tester.tap(find.byKey(const ValueKey('get-started')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('goal-profile')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
  await tester.pumpAndSettle();
}

void main() {
  group('18+ gate', () {
    test('onboarding cannot complete without the 18+ confirmation', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.create();
      final state = AppState(storage: storage, ai: MockAIService());
      final ok = await state.completeOnboarding(
          goals: const [CoachingGoal.profile], language: CoachLanguage.en, coachId: 'ava', adultConfirmed: false);
      expect(ok, isFalse);
      expect(state.onboarded, isFalse);
      expect(storage.hasOnboarded, isFalse);
    });

    test('after "under 18", onboarding is refused even with confirmation, and the block survives restarts and Delete my data', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.create();
      final state = AppState(storage: storage, ai: MockAIService());
      await state.markUnderage();
      expect(await state.completeOnboarding(
              goals: const [CoachingGoal.profile], language: CoachLanguage.en, coachId: 'ava', adultConfirmed: true),
          isFalse);
      await state.deleteMyData();
      final restarted = AppState(storage: await StorageService.create(), ai: MockAIService());
      expect(restarted.underageBlocked, isTrue);
      expect(restarted.onboarded, isFalse);
    });

    test('a stored "onboarded" flag does not open the app for a blocked user', () async {
      SharedPreferences.setMockInitialValues({'dw_onboarded': true, 'dw_underage': true});
      final state = AppState(storage: await StorageService.create(), ai: MockAIService());
      expect(state.onboarded, isFalse);
      expect(state.underageBlocked, isTrue);
    });

    testWidgets('"I am under 18" ends on the adults-only page, with no way back, also after a restart', (tester) async {
      final app = await pumpApp(tester, entitled: false);
      await toAgeStep(tester);
      await tester.tap(find.byKey(const ValueKey('age-under')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('underage')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-back')), findsNothing);
      expect(find.byKey(const ValueKey('get-started')), findsNothing);
      // The system back gesture does not leave the page either.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('underage')), findsOneWidget);
      expect(app.storage.underage, isTrue);

      // Restart.
      final restarted = TestApp(AppState(storage: await StorageService.create(), ai: MockAIService(), store: app.store), app.store, app.storage);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(wrap(restarted, const DateWiseApp()));
      await tester.pump();
      expect(find.byKey(const ValueKey('underage')), findsOneWidget);
    });

    testWidgets('Continue stays disabled until 18+ is confirmed', (tester) async {
      final app = await pumpApp(tester, entitled: false);
      await toAgeStep(tester);
      await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
      await tester.pumpAndSettle();
      expect(find.text('DateWise is for adults.'), findsOneWidget, reason: 'still on the age step');
      expect(app.state.onboarded, isFalse);
    });
  });

  test('no analytics, ads or tracking SDKs', () {
    final pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
    final lock = File('pubspec.lock').readAsStringSync().toLowerCase();
    for (final sdk in [
      'firebase_analytics', 'firebase_crashlytics', 'google_mobile_ads', 'facebook', 'appsflyer', 'adjust_sdk',
      'amplitude', 'mixpanel', 'segment', 'sentry', 'branch', 'onesignal', 'app_tracking_transparency', 'posthog', 'datadog',
    ]) {
      expect(pubspec.contains(sdk), isFalse, reason: sdk);
      expect(lock.contains('  $sdk:'), isFalse, reason: sdk);
    }
  });

  group('Delete my data', () {
    testWidgets('says the App Store subscription is not canceled, wipes the device, keeps the entitlement', (tester) async {
      final app = await pumpApp(tester, prefs: {...onboardedPrefs(), 'dw_memory_on': true, 'dw_memory_text': 'note', 'dw_tier': 'magnet'}, tab: AppTab.you);
      expect(find.text('Does not cancel your subscription. Cancel it in Apple settings.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('row-delete-data')));
      await tester.tap(find.byKey(const ValueKey('row-delete-data')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your subscription is managed by Apple and stays active'), findsOneWidget);
      expect(find.textContaining('subscription status'), findsNothing, reason: 'nothing about a subscription status is stored or erased');
      expect(find.textContaining('Settings › [your name] › Subscriptions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('dw_')), isEmpty);
      expect(app.state.memoryText, isEmpty);
      expect(app.state.memoryEnabled, isFalse);
      expect(app.store.isEntitled, isTrue, reason: 'the Apple subscription is untouched');
      expect(find.byKey(const ValueKey('welcome')), findsOneWidget);
    });
  });

  group('subscription', () {
    test('only datewise_premium_monthly; no free, annual or lifetime option anywhere', () {
      expect(StoreConfig.productId, 'datewise_premium_monthly');
      final code = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') || f.path.endsWith('.arb'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      final ids = RegExp(r'datewise_premium_\w+').allMatches(code).map((m) => m[0]).toSet();
      expect(ids, {'datewise_premium_monthly'});
      for (final w in [RegExp(r'\bannual', caseSensitive: false), RegExp(r'\byearly', caseSensitive: false),
          RegExp(r'\blifetime', caseSensitive: false), RegExp(r'free (plan|tier|trial|version)', caseSensitive: false),
          RegExp(r'/wk|per week|weekly ?price', caseSensitive: false), RegExp(r'prueba gratis|gratis', caseSensitive: false)]) {
        final hits = w.allMatches(code).map((m) => code.substring((m.start - 40).clamp(0, code.length), (m.end + 40).clamp(0, code.length))).toList();
        // The Terms say chat is available only with the paid subscription.
        hits.removeWhere((h) =>
            h.contains('only with this paid subscription') || h.contains('solo está disponible con esta suscripción') || h.contains('No free plan, no trial, no annual plan'));
        expect(hits, isEmpty, reason: '$w: $hits');
      }
    });

    testWidgets('restore purchases (fake store) from the paywall unlocks chat', (tester) async {
      final store = FakeStoreService(purchasedBefore: true);
      final app = await pumpApp(tester, prefs: onboardedPrefs(), store: store);
      expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('paywall-restore')));
      await tester.tap(find.byKey(const ValueKey('paywall-restore')));
      await tester.pumpAndSettle();
      expect(store.isEntitled, isTrue);
      expect(app.state.canChat, isTrue);
      expect(find.byKey(const ValueKey('tab-home')), findsOneWidget);
    });

    testWidgets('restore with nothing to restore says so', (tester) async {
      await pumpApp(tester, prefs: onboardedPrefs(), store: FakeStoreService());
      await tester.ensureVisible(find.byKey(const ValueKey('paywall-restore')));
      await tester.tap(find.byKey(const ValueKey('paywall-restore')));
      await tester.pumpAndSettle();
      expect(find.text('No active DateWise Premium subscription was found for this Apple Account.'), findsOneWidget);
    });

    testWidgets('restore from You (fake store)', (tester) async {
      final store = FakeStoreService(entitled: true);
      await pumpApp(tester, prefs: onboardedPrefs(), store: store, tab: AppTab.you);
      await tester.ensureVisible(find.byKey(const ValueKey('row-restore')));
      await tester.tap(find.byKey(const ValueKey('row-restore')));
      await tester.pump();
      expect(find.text('DateWise Premium is active.'), findsOneWidget);
    });

    testWidgets('the entitlement is re-checked when the app returns to the foreground', (tester) async {
      final store = FakeStoreService(entitled: true);
      final app = await pumpApp(tester, prefs: onboardedPrefs(), store: store, tab: AppTab.chat);
      expect(store.refreshCalls, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      store.expire(); // canceled in Apple's settings while away
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(store.refreshCalls, 1);
      expect(app.state.canChat, isFalse);
      expect(find.byKey(const ValueKey('composer')), findsNothing, reason: 'chat locks again');
    });

    testWidgets('paywall disclosures (English)', (tester) async {
      await pumpApp(tester, prefs: onboardedPrefs(), entitled: false);
      final d = tester.widget<Text>(find.byKey(const ValueKey('paywall-disclosure'))).data!;
      expect(d, startsWith(r'$9.99/month.'));
      expect(d, contains('charged to your Apple Account at confirmation of purchase'));
      expect(d, contains('renews automatically every month at \$9.99 unless you cancel it'));
      expect(d, contains('at least 24 hours before the end of the current period'));
      expect(d, contains('Settings › [your name] › Subscriptions'));
      expect(find.text(r'Subscribe for $9.99/month'), findsOneWidget);
      expect(find.text('DateWise Premium'), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-terms')), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-privacy')), findsOneWidget);
    });
  });
}
