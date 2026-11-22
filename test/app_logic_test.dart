// Unit tests: subscription gating, Coach memory, delete-data wipe, the weekly
// plan, the streak, reply options and voice selection.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/l10n/l10n.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/reply_options.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/models/weekly_plan.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/mock_ai_service.dart';
import 'package:datewise_ai/services/persona.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/services/voice_service.dart';
import 'package:datewise_ai/state/app_state.dart';

Future<(AppState, StorageService)> make({Map<String, Object> prefs = const {}, StoreService? store, DateTime? now}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storage = await StorageService.create();
  final state = AppState(storage: storage, ai: MockAIService(), store: store, clock: now == null ? null : () => now);
  return (state, storage);
}

void main() {
  group('store gating (fake store)', () {
    test('no chat without an active subscription; chat after buying', () async {
      final store = FakeStoreService();
      final (state, _) = await make(store: store);
      await state.selectCoach('ava');
      expect(state.canChat, isFalse);
      expect(await state.sendMessage('Hi'), isFalse);
      expect(state.threads, isEmpty, reason: 'nothing is sent or saved');

      expect(await store.buy(), PurchaseResult.purchased);
      expect(state.canChat, isTrue);
      final sent = state.sendMessage('Give me a strong opener');
      await sent;
      expect(await sent, isTrue);
      expect(state.activeThread!.messages.last.isUser, isFalse);

      store.expire();
      expect(state.canChat, isFalse);
      expect(await state.sendMessage('Again'), isFalse);
    });

    test('restore brings back an active subscription (new install or device)', () async {
      final store = FakeStoreService(purchasedBefore: true);
      final (state, _) = await make(store: store);
      expect(state.canChat, isFalse);
      expect(await store.restore(), isTrue);
      expect(store.isEntitled, isTrue);
      expect(state.canChat, isTrue);
    });

    test('restore finds nothing once the subscription was canceled or expired', () async {
      final store = FakeStoreService();
      await store.buy();
      store.expire();
      expect(await store.restore(), isFalse);
      expect(store.isEntitled, isFalse);
    });

    test('one product; the price only ever comes from the store (no hard-coded fallback)', () {
      expect(StoreConfig.productId, 'datewise_premium_monthly');
      expect(FakeStoreService(price: '9,99 €').storePrice, '9,99 €', reason: 'the StoreKit price is shown as is');
      expect(FakeStoreService(price: null).storePrice, isNull);
      expect(UnsupportedStoreService().storePrice, isNull);
      expect(UnsupportedStoreService().canPurchase, isFalse);
    });
  });

  group('Coach memory', () {
    test('is OFF by default and nothing is sent', () async {
      final (state, _) = await make(prefs: {'dw_memory_text': 'I am shy'});
      expect(state.memoryEnabled, isFalse);
      expect(state.profileForCoach?.memory, isNull);
    });

    test('is sent with the profile only while ON; can be edited and cleared', () async {
      final (state, storage) = await make();
      await state.completeOnboarding(goals: const [CoachingGoal.dates], language: CoachLanguage.en, coachId: 'ethan', adultConfirmed: true);
      await state.saveMemory('Shy at first, on Hinge.');
      expect(state.profileForCoach!.memory, isNull);

      await state.setMemoryEnabled(true);
      expect(state.profileForCoach!.memory, 'Shy at first, on Hinge.');
      final svc = BackendAIService(endpoint: 'https://example.invalid');
      final history = [ChatMessage(id: '1', role: MessageRole.user, text: 'Hi', createdAt: DateTime(2026))];
      final on = svc.buildPayload(history, SubscriptionTier.magnet, state.profileForCoach, Coaches.ethan);
      expect((on['profile'] as Map)['memory'], 'Shy at first, on Hinge.');
      expect(CoachPersona.systemPrompt(SubscriptionTier.magnet, profile: state.profileForCoach, coach: Coaches.ethan),
          contains('Shy at first, on Hinge.'));

      await state.setMemoryEnabled(false);
      final off = svc.buildPayload(history, SubscriptionTier.magnet, state.profileForCoach, Coaches.ethan);
      expect((off['profile'] as Map).containsKey('memory'), isFalse);
      expect(CoachPersona.systemPrompt(SubscriptionTier.magnet, profile: state.profileForCoach, coach: Coaches.ethan),
          isNot(contains('Shy at first')));

      await state.clearMemory();
      expect(state.memoryText, isEmpty);
      expect(storage.memoryText, isEmpty);
      expect(storage.loadProfile()!.toJson().containsKey('memory'), isFalse, reason: 'memory is never stored in the profile');
    });
  });

  group('delete data', () {
    test('Delete my data wipes everything and returns to onboarding', () async {
      final store = FakeStoreService(entitled: true);
      final (state, storage) = await make(store: store, prefs: {'dw_tier': 'magnet'});
      await state.completeOnboarding(goals: const [CoachingGoal.profile], language: CoachLanguage.es, coachId: 'sofia', adultConfirmed: true);
      await state.saveMemory('note');
      await state.setMemoryEnabled(true);
      await state.togglePlanItem(0);
      await state.sendMessage('Hola');
      expect(state.threads, isNotEmpty);

      await state.deleteMyData();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('dw_')), isEmpty,
          reason: 'conversations, profile, plan, memory, stats and subscription flags are all gone');
      expect(state.onboarded, isFalse);
      expect(state.threads, isEmpty);
      expect(state.plan, isNull);
      expect(state.memoryEnabled, isFalse);
      expect(state.memoryText, isEmpty);
      expect(state.daysUsed, 0);
      expect(storage.loadThreads(), isEmpty);
      expect(store.isEntitled, isTrue, reason: 'the App Store subscription itself is not canceled');
    });

    test('Delete all conversations keeps settings', () async {
      final (state, storage) = await make(store: FakeStoreService(entitled: true));
      await state.completeOnboarding(goals: const [CoachingGoal.profile], language: CoachLanguage.en, coachId: 'ava', adultConfirmed: true);
      await state.sendMessage('Hi');
      await state.deleteAllConversations();
      expect(state.threads, isEmpty);
      expect(storage.loadThreads(), isEmpty);
      expect(state.onboarded, isTrue);
      expect(state.selectedCoach, Coaches.ava);
      expect(state.conversationCount, 0);
    });
  });

  group('weekly plan', () {
    test('built from the onboarding goals, topped up to three items', () {
      final plan = WeeklyPlan.fromGoals(const [CoachingGoal.relationship], DateTime(2026, 11, 25));
      expect(plan.items.map((i) => i.goal), [CoachingGoal.relationship, CoachingGoal.conversations, CoachingGoal.profile]);
      expect(plan.weekStart, DateTime(2026, 11, 23), reason: 'Monday');
    });

    test('ticks persist across launches', () async {
      final now = DateTime(2026, 11, 25, 20);
      final (state, storage) = await make(now: now);
      await state.completeOnboarding(
          goals: const [CoachingGoal.profile, CoachingGoal.dates], language: CoachLanguage.en, coachId: 'ava', adultConfirmed: true);
      await state.togglePlanItem(1);
      final reloaded = AppState(storage: storage, ai: MockAIService(), clock: () => now);
      expect(reloaded.plan!.items.map((i) => i.done), [false, true, false]);
      expect(reloaded.plan!.items[0].goal, CoachingGoal.profile);
      expect(lookupAppLocalizations(const Locale('en')).planItemTitle(CoachingGoal.profile, Coaches.ava),
          'Rewrite your bio with Ava');
      expect(lookupAppLocalizations(const Locale('es')).planItemTitle(CoachingGoal.profile, Coaches.sofia),
          'Reescribe tu biografía con Sofía');
    });

    test('ticks reset when a new week starts; items stay', () async {
      final (state, storage) = await make(now: DateTime(2026, 11, 25));
      await state.completeOnboarding(goals: const [CoachingGoal.profile], language: CoachLanguage.en, coachId: 'ava', adultConfirmed: true);
      await state.togglePlanItem(0);
      final nextWeek = AppState(storage: storage, ai: MockAIService(), clock: () => DateTime(2026, 12, 1));
      expect(nextWeek.plan!.doneCount, 0);
      expect(nextWeek.plan!.items.first.goal, CoachingGoal.profile);
    });
  });

  group('progress counts', () {
    test('streak counts consecutive days ending today or yesterday', () {
      final now = DateTime(2026, 11, 22, 9);
      expect(currentStreak({}, now), 0);
      expect(currentStreak({'2026-11-22', '2026-11-21', '2026-11-20', '2026-11-18'}, now), 3);
      expect(currentStreak({'2026-11-21', '2026-11-20'}, now), 2, reason: 'today not used yet');
      expect(currentStreak({'2026-11-19'}, now), 0);
    });

    test('messaging records the day and counts the conversation', () async {
      final (state, _) = await make(now: DateTime(2026, 11, 22, 10));
      await state.selectCoach('ava');
      await state.createThread();
      expect(state.conversationCount, 0, reason: 'a greeting alone is not a conversation');
      await state.sendMessage('Hi');
      expect(state.conversationCount, 1);
      expect(state.streakDays, 1);
      expect(state.daysUsed, 1);
    });
  });

  group('reply options', () {
    test('parsed only when the model provides the OPTIONS line', () {
      final none = parseReply('Just send something specific.');
      expect(none.options, isEmpty);
      expect(none.body, 'Just send something specific.');

      final some = parseReply('Try one of these.\nOPTIONS: Safe | "That trail looks unreal. Where was it?" || Playful | “That view beats my Sunday.”');
      expect(some.body, 'Try one of these.');
      expect(some.options.map((o) => o.label), ['Safe', 'Playful']);
      expect(some.options.first.text, 'That trail looks unreal. Where was it?');
      expect(some.options.last.text, 'That view beats my Sunday.');
    });
  });

  group('voice service', () {
    test('no TTS on web/tests: the voice service reports unavailable', () {
      expect(NoVoiceService().available, isFalse);
    });
  });
}
