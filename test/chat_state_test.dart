// Chat behavior in AppState and on the chat screen: a failed reply keeps the
// user's message and offers "Try again"; leaving the chat cancels the stream;
// Coach memory reaches the system prompt only while ON; conversations persist
// per coach across restarts.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/ai_config.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/mock_ai_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';

import 'helpers.dart';

/// Scripted coach: each call takes the next behavior.
class ScriptedAI implements AIService {
  ScriptedAI(this.script);
  final List<Stream<String> Function()> script;
  final calls = <List<ChatMessage>>[];
  var cancels = 0;

  static Stream<String> Function() ok(List<String> tokens) => () => Stream.fromIterable(tokens);
  static Stream<String> Function() fail() =>
      () => Stream.error(const CoachUnavailableException('http', statusCode: 502));

  /// Tokens every 20 ms until canceled.
  Stream<String> Function() slow(int n) => () {
        late StreamController<String> c;
        Timer? t;
        var i = 0;
        c = StreamController<String>(
          onListen: () => t = Timer.periodic(const Duration(milliseconds: 20), (_) {
            if (i < n) {
              c.add('w$i ');
              i++;
            } else {
              t?.cancel();
              c.close();
            }
          }),
          onCancel: () {
            cancels++;
            t?.cancel();
          },
        );
        return c.stream;
      };

  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) {
    calls.add(List.of(history));
    return script.removeAt(0)();
  }

  @override
  String get providerLabel => 'scripted';
}

Future<(AppState, StorageService)> make(AIService ai, {Map<String, Object> prefs = const {}}) async {
  // The user already agreed to share messages with the AI provider.
  SharedPreferences.setMockInitialValues({'dw_ai_consent': true, ...prefs});
  final storage = await StorageService.create();
  return (AppState(storage: storage, ai: ai, store: FakeStoreService(entitled: true)), storage);
}

/// Storage whose conversation and active-day writes can be made to fail
/// (a full disk, a corrupt preferences store).
class ThrowingStorage extends StorageService {
  ThrowingStorage(super.prefs);
  bool failThreads = false;
  bool failActiveDays = false;

  @override
  Future<void> saveThreads(threads) =>
      failThreads ? Future.error(StateError('disk full')) : super.saveThreads(threads);

  @override
  Future<void> saveActiveDays(days) =>
      failActiveDays ? Future.error(StateError('disk full')) : super.saveActiveDays(days);
}

void main() {
  group('a storage error before the reply streams', () {
    Future<(AppState, ThrowingStorage, ScriptedAI)> setUpState() async {
      SharedPreferences.setMockInitialValues({'dw_ai_consent': true});
      final storage = ThrowingStorage(await SharedPreferences.getInstance());
      final ai = ScriptedAI([ScriptedAI.ok(['Hi ', 'there.'])]);
      final state = AppState(storage: storage, ai: ai, store: FakeStoreService(entitled: true));
      await state.selectCoach('ava');
      return (state, storage, ai);
    }

    for (final which in ['threads', 'activeDays']) {
      test('saving $which fails: not stuck "responding", the reply can be retried', () async {
        final (state, storage, ai) = await setUpState();
        await state.createThread();
        storage
          ..failThreads = which == 'threads'
          ..failActiveDays = which == 'activeDays';
        expect(await state.sendMessage('Help me reply'), isTrue);
        expect(state.isResponding, isFalse);
        expect(ai.calls, isEmpty, reason: 'no request when the reply could not be saved first');
        final last = state.activeThread!.messages.last;
        expect(last.status, MessageStatus.failed);
        expect(last.isStreaming, isFalse);
        // Nothing is left over: Stop is a no-op, and once storage works the reply is retried.
        await state.cancelReply();
        storage
          ..failThreads = false
          ..failActiveDays = false;
        expect(state.canRetry, isTrue);
        expect(await state.retryLastReply(), isTrue);
        expect(state.activeThread!.messages.last.text, 'Hi there.');
        expect(state.isResponding, isFalse);
      });
    }

    test('starting a new conversation fails: nothing sent, not stuck "responding"', () async {
      final (state, storage, ai) = await setUpState();
      storage.failThreads = true;
      expect(await state.sendMessage('Help me reply'), isFalse);
      expect(state.isResponding, isFalse);
      expect(ai.calls, isEmpty);
      storage.failThreads = false;
      expect(await state.sendMessage('Help me reply'), isTrue);
      expect(state.activeThread!.messages.last.text, 'Hi there.');
    });
  });

  group('failed reply', () {
    test('keeps the user message, marks the reply failed, and retry replaces it', () async {
      final ai = ScriptedAI([ScriptedAI.fail(), ScriptedAI.ok(['Here ', 'you go.'])]);
      final (state, storage) = await make(ai);
      await state.selectCoach('ava');
      expect(await state.sendMessage('Help me reply'), isTrue);

      var msgs = state.activeThread!.messages;
      expect(msgs[msgs.length - 2].text, 'Help me reply', reason: 'the user message is kept');
      expect(msgs.last.status, MessageStatus.failed);
      expect(msgs.last.text, isEmpty, reason: 'no fake coaching text');
      expect(state.canRetry, isTrue);
      expect(state.isResponding, isFalse);
      // Persisted: a failed reply can be retried after a restart.
      expect(storage.loadThreads().first.messages.last.status, MessageStatus.failed);

      expect(await state.retryLastReply(), isTrue);
      msgs = state.activeThread!.messages;
      expect(msgs.where((m) => m.isUser).map((m) => m.text), ['Help me reply']);
      expect(msgs.last.text, 'Here you go.');
      expect(msgs.last.status, MessageStatus.ok);
      expect(state.canRetry, isFalse);
      expect(ai.calls.last.last.text, 'Help me reply', reason: 'retry resends the same message');
      expect(ai.calls.last.where((m) => m.status != MessageStatus.ok), isEmpty);
    });

    test('against the real client: HTTP 502 from the Worker shows as a failed reply', () async {
      final backend = BackendAIService(
        endpoint: AIConfig.productionUrl,
        clientFactory: () => MockClient((_) async => http.Response('{"error":"Workers AI error"}', 502)),
      );
      final (state, _) = await make(backend);
      await state.selectCoach('sofia');
      await state.sendMessage('Hola');
      expect(state.activeThread!.messages.last.status, MessageStatus.failed);
      expect(state.activeThread!.messages.where((m) => m.isUser).single.text, 'Hola');
    });
  });

  group('cancel', () {
    test('cancelReply stops the stream, keeps the message and allows retry', () async {
      final ai = ScriptedAI([]);
      ai.script.add(ai.slow(100));
      final (state, _) = await make(ai);
      await state.selectCoach('ava');
      final sending = state.sendMessage('Plan a first date');
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(state.isResponding, isTrue);
      await state.cancelReply();
      await sending;
      expect(ai.cancels, 1, reason: 'the stream subscription was canceled');
      expect(state.isResponding, isFalse);
      final last = state.activeThread!.messages.last;
      expect(last.status, MessageStatus.stopped);
      expect(state.canRetry, isTrue);
      expect(state.activeThread!.messages.where((m) => m.isUser).single.text, 'Plan a first date');
    });

    testWidgets('leaving the Chat tab cancels a streaming reply', (tester) async {
      final ai = ScriptedAI([]);
      ai.script.add(ai.slow(1000));
      setSurface(tester, const Size(390, 844), 1);
      SharedPreferences.setMockInitialValues(onboardedPrefs());
      final storage = await StorageService.create();
      final app = TestApp(AppState(storage: storage, ai: ai, store: FakeStoreService(entitled: true)), FakeStoreService(entitled: true), storage);
      await tester.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat)));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('composer')), 'Hi');
      await tester.tap(find.byKey(const ValueKey('send')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(app.state.isResponding, isTrue);
      expect(find.byKey(const ValueKey('stop')), findsOneWidget, reason: 'the send button becomes Stop');

      await tester.tap(find.byKey(const ValueKey('tab-home')));
      await tester.pumpAndSettle();
      expect(ai.cancels, 1);
      expect(app.state.isResponding, isFalse);
      expect(app.state.activeThread!.messages.last.status, MessageStatus.stopped);

      // Back in the chat: the notice and "Try again" are shown.
      await tester.tap(find.byKey(const ValueKey('tab-chat')));
      await tester.pumpAndSettle();
      expect(find.text('The reply was stopped. Your message is saved.'), findsOneWidget);
      expect(find.byKey(const ValueKey('retry')), findsOneWidget);
    });

    testWidgets('a failed reply shows the friendly error and "Try again" works', (tester) async {
      final ai = ScriptedAI([ScriptedAI.fail(), ScriptedAI.ok(['All good now.'])]);
      setSurface(tester, const Size(390, 844), 1);
      SharedPreferences.setMockInitialValues(onboardedPrefs());
      final storage = await StorageService.create();
      final store = FakeStoreService(entitled: true);
      final app = TestApp(AppState(storage: storage, ai: ai, store: store), store, storage);
      await tester.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat)));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('composer')), 'Hi');
      await tester.tap(find.byKey(const ValueKey('send')));
      await tester.pumpAndSettle();
      // A 502 (server down) shows the specific notice (AI QA D3).
      expect(find.text('Coaching is temporarily unavailable. Try again in a few minutes. Your message is saved.'), findsOneWidget);
      expect(find.text('Hi'), findsOneWidget, reason: 'the message stays on screen');
      await tester.tap(find.byKey(const ValueKey('retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reply-failed')), findsNothing);
      expect(app.state.activeThread!.messages.last.text, 'All good now.');
    });

    for (final (error, text) in [
      (const CoachUnavailableException('http', statusCode: 429), 'Your coach is getting a lot of messages right now. Try again in a moment. Your message is saved.'),
      (const CoachUnavailableException('network: SocketException'), 'You seem to be offline. Check your connection and try again. Your message is saved.'),
      (const CoachUnavailableException('truncated'), "Couldn't reach your coach. Check your connection and try again. Your message is saved."),
    ]) {
      testWidgets('a failed reply ($error) shows its specific notice', (tester) async {
        final ai = ScriptedAI([() => Stream<String>.error(error)]);
        setSurface(tester, const Size(390, 844), 1);
        SharedPreferences.setMockInitialValues(onboardedPrefs());
        final storage = await StorageService.create();
        final store = FakeStoreService(entitled: true);
        final app = TestApp(AppState(storage: storage, ai: ai, store: store), store, storage);
        await tester.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat)));
        await tester.pump();
        await tester.enterText(find.byKey(const ValueKey('composer')), 'Hi');
        await tester.tap(find.byKey(const ValueKey('send')));
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget);
      });
    }
  });

  group('Coach memory in the request', () {
    Future<Map<String, dynamic>> sentWith({required bool memoryOn}) async {
      String? body;
      final backend = BackendAIService(
        endpoint: AIConfig.productionUrl,
        clientFactory: () => MockClient((req) async {
          body = req.body;
          return http.Response('data: {"response":"ok"}\n\ndata: [DONE]\n\n', 200);
        }),
      );
      final (state, _) = await make(backend);
      await state.completeOnboarding(goals: const [CoachingGoal.dates], language: CoachLanguage.en, coachId: 'ethan', adultConfirmed: true);
      await state.saveMemory('Shy at first, on Hinge.');
      await state.setMemoryEnabled(memoryOn);
      await state.sendMessage('Hi');
      return jsonDecode(body!) as Map<String, dynamic>;
    }

    test('ON: the note is in the system prompt and the profile', () async {
      final json = await sentWith(memoryOn: true);
      final system = ((json['messages'] as List).first as Map)['content'] as String;
      expect(system, contains('Shy at first, on Hinge.'));
      expect((json['profile'] as Map)['memory'], 'Shy at first, on Hinge.');
    });

    test('OFF: the note is not sent anywhere', () async {
      final json = await sentWith(memoryOn: false);
      expect(jsonEncode(json), isNot(contains('Shy at first')));
    });
  });

  test('conversations persist per coach across app restarts', () async {
    SharedPreferences.setMockInitialValues({'dw_ai_consent': true});
    final storage = await StorageService.create();
    final state = AppState(storage: storage, ai: MockAIService(), store: FakeStoreService(entitled: true));
    await state.selectCoach('ava');
    await state.sendMessage('Give me a strong opener');
    await state.selectCoach('sofia');
    await state.sendMessage('Dame un buen primer mensaje');
    await state.selectCoach('diego');

    // "Restart": a new StorageService and AppState over the same saved prefs.
    final restarted = AppState(storage: await StorageService.create(), ai: MockAIService());
    expect(restarted.selectedCoach, Coaches.diego);
    expect(restarted.threadsFor(Coaches.ava).single.messages.where((m) => m.isUser).single.text, 'Give me a strong opener');
    expect(restarted.threadsFor(Coaches.sofia).single.messages.where((m) => m.isUser).single.text, 'Dame un buen primer mensaje');
    expect(restarted.threadsFor(Coaches.sofia).single.messages.last.text, isNotEmpty);
    expect(restarted.threadsFor(Coaches.diego), isEmpty);
    await restarted.selectCoach('ava');
    expect(restarted.activeThread!.coachId, 'ava');
  });
}
