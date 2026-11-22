// The four DateWise coaches: identity, language and persistence.

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
  group('the four coaches', () {
    test('Emily, James, Isabella and Mateo, with distinct ids, names and colours', () {
      expect(Coaches.all.map((c) => c.id), ['emily', 'james', 'isabella', 'mateo']);
      expect(Coaches.all.map((c) => c.name).toSet().length, 4);
      expect(Coaches.all.map((c) => c.color).toSet().length, 4);
      expect(Coaches.all.map((c) => c.tagline).toSet().length, 4);
    });

    test('two English coaches and two Spanish coaches', () {
      expect(Coaches.forLanguage(CoachLanguage.en).map((c) => c.id), ['emily', 'james']);
      expect(Coaches.forLanguage(CoachLanguage.es).map((c) => c.id), ['isabella', 'mateo']);
    });

    test('each coach has a distinct style, greeting and four starters', () {
      expect(Coaches.all.map((c) => c.styleRules.join()).toSet().length, 4);
      expect(Coaches.all.map((c) => c.greeting).toSet().length, 4);
      for (final c in Coaches.all) {
        expect(c.starters, hasLength(4), reason: c.id);
        expect(c.greeting, contains(c.name), reason: c.id);
      }
    });

    test('an unknown or missing id falls back to Emily', () {
      expect(Coaches.byId(null), Coaches.emily);
      expect(Coaches.byId('nobody'), Coaches.emily);
      expect(Coaches.byId('mateo'), Coaches.mateo);
    });

    test('Spanish coaches speak Spanish on screen; English coaches English', () {
      for (final c in Coaches.forLanguage(CoachLanguage.es)) {
        expect(c.greeting, contains('Soy'), reason: c.id);
        expect(c.tagline, contains(' y '), reason: c.id);
        expect(c.starters.join(' '), isNot(matches(RegExp(r'\b(the|my|your)\b'))), reason: c.id);
      }
      for (final c in Coaches.forLanguage(CoachLanguage.en)) {
        expect(c.greeting, contains("I'm"), reason: c.id);
      }
    });
  });

  group('the system prompt sent to the model', () {
    test('names the coach and pins the reply language', () {
      final es = CoachPersona.systemPrompt(SubscriptionTier.magnet, coach: Coaches.isabella);
      expect(es, startsWith('You are Isabella'));
      expect(es, contains('Reply ONLY in natural, warm, neutral Latin-American Spanish'));
      final en = CoachPersona.systemPrompt(SubscriptionTier.magnet, coach: Coaches.james);
      expect(en, startsWith('You are James'));
      expect(en, contains('Reply ONLY in natural, warm English'));
      expect(en, isNot(contains('You are DateWise AI')), reason: 'one identity only');
    });

    test('each coach gets a different prompt, and the default is Emily', () {
      final prompts = Coaches.all.map((c) => CoachPersona.systemPrompt(SubscriptionTier.magnet, coach: c)).toSet();
      expect(prompts.length, 4);
      expect(CoachPersona.systemPrompt(SubscriptionTier.magnet), startsWith('You are Emily'));
    });

    test('keeps the safety and honesty rules for every coach', () {
      for (final c in Coaches.all) {
        final p = CoachPersona.systemPrompt(SubscriptionTier.magnet, coach: c);
        expect(p, contains('Never invent facts about the user'), reason: c.id);
        expect(p, contains('Decline manipulative'), reason: c.id);
        expect(p, contains('public place'), reason: c.id);
      }
    });

    test('the backend request carries the conversation coach as the system message', () {
      final svc = BackendAIService(endpoint: 'https://example.invalid', chatFallback: MockAIService());
      final history = [ChatMessage(id: '1', role: MessageRole.user, text: 'Hola', createdAt: DateTime(2026))];
      final msgs = svc.buildMessages(history, SubscriptionTier.magnet, null, Coaches.mateo);
      expect(msgs.first['role'], 'system');
      expect(msgs.first['content'], startsWith('You are Mateo'));
      expect(msgs.last, {'role': 'user', 'content': 'Hola'});
    });

    test('the request names the coach and keeps the system message for older Workers', () {
      final svc = BackendAIService(endpoint: 'https://example.invalid', chatFallback: MockAIService());
      final history = [ChatMessage(id: '1', role: MessageRole.user, text: 'Hola', createdAt: DateTime(2026))];
      final body = svc.buildPayload(history, SubscriptionTier.magnet, null, Coaches.isabella);
      expect(body['coachId'], 'isabella');
      expect(body.containsKey('profile'), isFalse, reason: 'no profile sent when there is none');
      final msgs = body['messages'] as List<Map<String, String>>;
      expect(msgs.first['role'], 'system');
      expect(svc.buildPayload(history, SubscriptionTier.magnet, null)['coachId'], 'emily');
      const profile = UserProfile(
          gender: Gender.female, age: 31, interestedIn: InterestedIn.men, goal: DatingGoal.serious, app: DatingApp.hinge, city: 'Lima');
      final withProfile = svc.buildPayload(history, SubscriptionTier.magnet, profile, Coaches.isabella);
      expect(withProfile['profile'],
          {'gender': 'female', 'age': 31, 'interestedIn': 'men', 'goal': 'serious', 'app': 'hinge', 'city': 'Lima'},
          reason: 'structured fields only: the Worker builds the summary from known values');
      expect(withProfile.containsKey('context'), isFalse);
    });

    test('the connection-failure notice is in the coach language', () {
      expect(BackendAIService.unavailableMessage(Coaches.mateo), startsWith('Ahora mismo'));
      expect(BackendAIService.unavailableMessage(Coaches.emily), startsWith("I'm having trouble"));
    });
  });

  group('offline coach (demo build)', () {
    test('Spanish coaches answer in Spanish, by intent', () {
      expect(MockAIService.spanishReply('Ayúdame con mi perfil', Coaches.isabella), contains('biografía'));
      expect(MockAIService.spanishReply('¿Qué le escribo primero?', Coaches.mateo), contains('primer mensaje'));
      expect(MockAIService.spanishReply('Mi pareja dejó de escribirme', Coaches.isabella), contains('mensaje ligero'));
      expect(MockAIService.spanishReply('Quiero una cita', Coaches.mateo), contains('lugar público'));
    });

    test('every Spanish starter gets its own intent (photos and stalled chats first)', () {
      final expected = {
        'Reescribe mi biografía': 'biografía',
        'Mi pareja dejó de escribirme': 'mensaje ligero',
        '¿Cómo hablo de lo que siento?': 'en qué punto estás',
        'Revisa mis fotos de perfil': 'fotos',
        'Dame un buen primer mensaje': 'primer mensaje',
        'La conversación se enfrió, ¿qué le escribo?': 'mensaje ligero',
        'Planea una primera cita': 'lugar público',
      };
      for (final c in Coaches.forLanguage(CoachLanguage.es)) {
        for (final starter in c.starters) {
          expect(expected.keys, contains(starter), reason: 'new starter needs an expectation: $starter');
          expect(MockAIService.spanishReply(starter, c), contains(expected[starter]!), reason: starter);
        }
      }
      expect(MockAIService.spanishReply('Revisa mis fotos de perfil', Coaches.mateo), isNot(contains('biografía')));
    });

    test('streamReply follows the coach language', () async {
      final ai = MockAIService();
      final history = [ChatMessage(id: '1', role: MessageRole.user, text: 'Quiero una cita', createdAt: DateTime(2026))];
      final es = (await ai.streamReply(history: history, tier: SubscriptionTier.magnet, coach: Coaches.mateo).toList()).join();
      expect(es, contains('lugar público'));
    });
  });

  group('greeting', () {
    final profile = UserProfile(
      gender: Gender.values.first,
      age: 29,
      interestedIn: InterestedIn.values.first,
      goal: DatingGoal.values.first,
      app: DatingApp.values.first,
    );

    test('an English coach introduces themself, then keeps the full personalised onboarding greeting', () {
      final g = CoachPersona.greeting(SubscriptionTier.magnet, profile: profile, coach: Coaches.emily);
      expect(g, startsWith("Hi, I'm **Emily**"));
      expect(g, contains(profile.interestedIn.label.toLowerCase()), reason: 'interested-in is kept');
      expect(g, contains('Photo'), reason: "the tier's first step (Magnet: photo coach) is kept");
      expect(g, isNot(contains('_I already know')));
    });

    test('a Spanish coach greets in Spanish only', () {
      final g = CoachPersona.greeting(SubscriptionTier.magnet, profile: profile, coach: Coaches.isabella);
      expect(g, Coaches.isabella.greeting);
    });
  });

  group('persistence', () {
    test('a conversation keeps its coach through save and load; old saves load as Emily', () {
      final t = ChatThread(id: 't', title: 'x', createdAt: DateTime(2026), updatedAt: DateTime(2026), coachId: 'isabella');
      expect(ChatThread.fromJson(t.toJson()).coachId, 'isabella');
      final legacy = t.toJson()..remove('coachId');
      expect(ChatThread.fromJson(legacy).coachId, 'emily');
    });

    test('choosing a coach is remembered and starts a conversation with that coach', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.create();
      final state = AppState(storage: storage, ai: MockAIService());
      expect(state.hasChosenCoach, isFalse);
      await state.selectCoach('mateo');
      expect(state.selectedCoach, Coaches.mateo);
      expect(state.activeThread!.coachId, 'mateo');
      expect(state.activeThread!.messages.single.text, Coaches.mateo.greeting);

      final reloaded = AppState(storage: await StorageService.create(), ai: MockAIService());
      expect(reloaded.hasChosenCoach, isTrue);
      expect(reloaded.selectedCoach, Coaches.mateo);
      expect(reloaded.activeCoach, Coaches.mateo);
    });

    test('conversations with every coach get titled from the first message', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(storage: await StorageService.create(), ai: MockAIService());
      await state.selectCoach('mateo');
      expect(state.activeThread!.title, 'Nueva conversación');
      await state.sendMessage(text: 'Planea una primera cita para el sábado por la tarde');
      expect(state.activeThread!.title, 'Planea una primera cita para…');
      await state.selectCoach('james');
      expect(state.activeThread!.title, 'New conversation');
      await state.sendMessage(text: 'Give me a strong opener');
      expect(state.activeThread!.title, 'Give me a strong opener');
    });

    test('a new conversation can continue with the coach on screen', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(storage: await StorageService.create(), ai: MockAIService());
      await state.selectCoach('mateo');
      final t = await state.createThread(coach: Coaches.emily);
      expect(t.coachId, 'emily');
      expect(t.messages.single.text, contains('Emily'));
      expect(state.selectedCoach, Coaches.mateo, reason: 'the saved choice is unchanged');
    });

    test('switching coach replaces an untouched greeting but never a real conversation', () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(storage: await StorageService.create(), ai: MockAIService());
      await state.selectCoach('emily');
      await state.selectCoach('james'); // Emily's untouched greeting is replaced
      expect(state.threads.map((t) => t.coachId), ['james']);
      await state.sendMessage(text: 'Give me a strong opener');
      await state.selectCoach('isabella'); // James's conversation stays
      expect(state.threads.map((t) => t.coachId).toList(), ['isabella', 'james']);
      expect(state.activeCoach, Coaches.isabella);
    });
  });

  group('names the redesign issues use (#6-#10, #13)', () {
    test('kCoaches, coachById, coachesFor, displayName, gender and systemPrompt', () {
      expect(kCoaches, Coaches.all);
      expect(coachById('isabella'), Coaches.isabella);
      expect(coachById('nobody'), isNull);
      expect(coachesFor(CoachLanguage.es), [Coaches.isabella, Coaches.mateo]);
      expect(Coaches.all.map((c) => c.displayName), ['Emily', 'James', 'Isabella', 'Mateo']);
      expect(Coaches.all.map((c) => c.gender),
          [CoachGender.female, CoachGender.male, CoachGender.female, CoachGender.male]);
      expect(Coaches.mateo.systemPrompt, startsWith('You are Mateo'));
      expect(Coaches.mateo.systemPrompt, contains('Spanish'));
      for (final c in Coaches.all) {
        expect('${c.systemPrompt} ${c.tagline} ${c.greeting}', isNot(contains('Amber')), reason: c.id);
      }
    });
  });
}
