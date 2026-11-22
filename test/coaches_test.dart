// The four DateWise coaches: identity, language rules, the request sent to
// the backend, the offline demo coach, and id migration from the old roster.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/chat_thread.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/mock_ai_service.dart';
import 'package:datewise_ai/services/persona.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/state/app_state.dart';

void main() {
  group('the four coaches (approved identities)', () {
    test('Ava, Ethan, Sofía and Diego with their approved descriptions', () {
      expect(Coaches.all.map((c) => c.id), ['ava', 'ethan', 'sofia', 'diego']);
      expect(Coaches.all.map((c) => c.name), ['Ava', 'Ethan', 'Sofía', 'Diego']);
      expect(Coaches.ava.description, 'Confidence coach. Direct, supportive, focused on results.');
      expect(Coaches.ethan.description, 'Strategy coach. Practical, modern, laid-back.');
      expect(Coaches.sofia.description, 'Coach de confianza. Cálida y motivadora.');
      expect(Coaches.diego.description, 'Coach de relaciones. Práctico y honesto.');
    });

    test('two English and two Spanish coaches, with labels in their language', () {
      expect(Coaches.forLanguage(CoachLanguage.en), [Coaches.ava, Coaches.ethan]);
      expect(Coaches.forLanguage(CoachLanguage.es), [Coaches.sofia, Coaches.diego]);
      expect(Coaches.ava.chatLabel, 'Chat with Ava');
      expect(Coaches.sofia.chatLabel, 'Chatear con Sofía');
      expect(Coaches.diego.composerHint, 'Escríbele a Diego…');
    });

    test('portraits come only from assets/coaches/{id}-hero.jpg and -avatar.jpg', () {
      for (final c in Coaches.all) {
        expect(c.heroAsset, 'assets/coaches/${c.id}-hero.jpg');
        expect(c.avatarAsset, 'assets/coaches/${c.id}-avatar.jpg');
      }
    });

    test('every coach is labelled as AI', () {
      for (final c in Coaches.all) {
        expect(c.aiLabel, anyOf(contains('AI'), contains('IA')));
        expect(c.greeting, anyOf(contains(' AI '), contains('con IA')));
      }
    });
  });

  group('coach id migration (existing users)', () {
    test('old ids map to the new coaches', () {
      expect(Coaches.migrateId('emily'), 'ava');
      expect(Coaches.migrateId('james'), 'ethan');
      expect(Coaches.migrateId('isabella'), 'sofia');
      expect(Coaches.migrateId('mateo'), 'diego');
      expect(Coaches.migrateId('sofia'), 'sofia');
      expect(Coaches.migrateId('nobody'), isNull);
      expect(Coaches.byId('isabella'), Coaches.sofia);
      expect(Coaches.byId(null), Coaches.ava);
    });

    test('a stored old coach id loads as the new coach and is re-saved', () async {
      SharedPreferences.setMockInitialValues({'dw_coach': 'mateo'});
      final storage = await StorageService.create();
      expect(storage.loadCoachId(), 'diego');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dw_coach'), 'diego');
    });

    test('saved conversations with old ids keep their coach', () {
      ChatThread load(String? id) => ChatThread.fromJson({
            'id': 't',
            'title': 'x',
            if (id != null) 'coachId': id,
            'messages': [],
          });
      expect(load('emily').coachId, 'ava');
      expect(load('james').coachId, 'ethan');
      expect(load('isabella').coachId, 'sofia');
      expect(load('mateo').coachId, 'diego');
      expect(load(null).coachId, 'ava');
    });
  });

  group('persona language rules', () {
    test('Spanish coaches reply in Spanish by default, and in the user language otherwise', () {
      for (final c in [Coaches.sofia, Coaches.diego]) {
        final p = c.systemPrompt;
        expect(p, startsWith('You are ${c.name}'));
        expect(p, contains('By default reply in natural, warm Latin-American Spanish'));
        expect(p, contains("If the user writes to you in another language, reply in the user's language instead."));
      }
    });

    test('English coaches reply in English by default', () {
      for (final c in [Coaches.ava, Coaches.ethan]) {
        expect(c.systemPrompt, contains('By default reply in natural, warm English.'));
      }
    });

    test('each coach has its own style rules, and safety and honesty rules', () {
      final prompts = Coaches.all.map((c) => c.systemPrompt).toSet();
      expect(prompts, hasLength(4));
      expect(Coaches.ava.systemPrompt, contains('confidence coach: direct, supportive and focused on results'));
      expect(Coaches.ethan.systemPrompt, contains('strategy coach: practical, modern and laid-back'));
      expect(Coaches.sofia.systemPrompt, contains('warm and motivating'));
      expect(Coaches.diego.systemPrompt, contains('relationship coach: practical and honest'));
      for (final c in Coaches.all) {
        expect(c.systemPrompt, contains('Never claim to be human'));
        expect(c.systemPrompt, contains('public place'));
      }
    });

    test('the full prompt never mentions plans or prices, and asks for reply options only as a final line', () {
      final p = CoachPersona.systemPrompt(SubscriptionTier.magnet, coach: Coaches.ethan);
      expect(p, contains('Never mention prices, plans, upgrades or subscriptions.'));
      expect(p, isNot(contains('Flame')));
      expect(p, contains('OPTIONS:'));
    });
  });

  group('the request sent to the backend', () {
    final svc = BackendAIService(endpoint: 'https://example.invalid', chatFallback: MockAIService());
    final history = [ChatMessage(id: '1', role: MessageRole.user, text: 'Hola', createdAt: DateTime(2026))];

    test('carries the coach id, the structured profile and the system message', () {
      const profile = UserProfile(goals: [CoachingGoal.profile], language: CoachLanguage.es);
      final body = svc.buildPayload(history, SubscriptionTier.magnet, profile, Coaches.sofia);
      expect(body['coachId'], 'sofia');
      expect(body['profile'], {'goals': ['profile'], 'language': 'es'});
      final msgs = body['messages'] as List<Map<String, String>>;
      expect(msgs.first['role'], 'system');
      expect(msgs.first['content'], startsWith('You are Sofía'));
      expect(msgs.last, {'role': 'user', 'content': 'Hola'});
      expect(svc.buildPayload(history, SubscriptionTier.magnet, null)['coachId'], 'ava');
    });

    test('the connection-failure notice is in the coach language', () {
      expect(BackendAIService.unavailableMessage(Coaches.diego), startsWith('Ahora mismo'));
      expect(BackendAIService.unavailableMessage(Coaches.ava), startsWith("I'm having trouble"));
    });
  });

  group('offline demo coach', () {
    test('Spanish coaches answer in Spanish', () async {
      final ai = MockAIService();
      final history = [ChatMessage(id: '1', role: MessageRole.user, text: 'Quiero una cita', createdAt: DateTime(2026))];
      final es = (await ai.streamReply(history: history, tier: SubscriptionTier.magnet, coach: Coaches.diego).toList()).join();
      expect(es, contains('lugar público'));
    });

    test('every Spanish starter gets a Spanish answer', () {
      for (final c in Coaches.forLanguage(CoachLanguage.es)) {
        for (final s in c.starters) {
          final reply = MockAIService.spanishReply(s, c);
          expect(reply, isNotEmpty);
          expect(reply, isNot(contains('Hey')), reason: s);
        }
      }
    });
  });

  group('conversations per coach', () {
    test('a new conversation opens with the coach greeting and is titled from the first message', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(storage: await StorageService.create(), ai: MockAIService());
      await state.selectCoach('sofia');
      final t = await state.createThread();
      expect(t.coachId, 'sofia');
      expect(t.messages.single.text, Coaches.sofia.greeting);
      expect(t.title, 'Nueva conversación');
    });

    test('switching coach keeps each coach’s conversations apart', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.create();
      final state = AppState(storage: storage, ai: MockAIService());
      await state.selectCoach('ava');
      await state.createThread();
      final avaId = state.activeThread!.id;
      await state.selectCoach('diego');
      expect(state.activeThread, isNull, reason: 'Diego has no conversation yet');
      await state.selectCoach('ava');
      expect(state.activeThread!.id, avaId);
      final reloaded = AppState(storage: storage, ai: MockAIService());
      expect(reloaded.threadsFor(Coaches.ava), hasLength(1));
    });
  });
}
