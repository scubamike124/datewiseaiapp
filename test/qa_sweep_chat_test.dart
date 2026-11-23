// Full-app QA sweep (v2), chat: Enter while a reply streams keeps the typed
// text (nothing is lost, nothing is sent), and a reply interrupted by an app
// restart comes back with "Try again".

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/chat_thread.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';

import 'helpers.dart';

/// A coach whose replies arrive only when the test adds them.
class _ControlledAI implements AIService {
  final streams = <StreamController<String>>[];

  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) {
    final c = StreamController<String>();
    streams.add(c);
    return c.stream;
  }

  @override
  String get providerLabel => 'controlled';
}

String _composerText(WidgetTester t) => t.widget<TextField>(find.byKey(const ValueKey('composer'))).controller!.text;

List<String> _userTexts(AppState s) => [for (final m in s.activeThread!.messages) if (m.isUser) m.text];

/// A saved conversation that ends on the user's message (the app closed
/// before the reply was saved).
String _threadEndingOnUser(String coach, String text) => jsonEncode([
      ChatThread(
        id: 't1',
        title: text,
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
        coachId: coach,
        messages: [
          ChatMessage(id: 'g', role: MessageRole.coach, text: 'Hi, I am your coach.', createdAt: DateTime(2026, 11, 1)),
          ChatMessage(id: 'u', role: MessageRole.user, text: text, createdAt: DateTime(2026, 11, 1)),
        ],
      ).toJson(),
    ]);

void main() {
  group('composer while a reply streams', () {
    for (final lang in ['en', 'es']) {
      final prefs = lang == 'es' ? spanishPrefs() : onboardedPrefs();
      final first = lang == 'es' ? 'Dame un buen primer mensaje' : 'Give me a strong opener';
      final second = lang == 'es' ? '¿Y si no me responde?' : 'What if they never reply?';

      testWidgets('[$lang] Enter keeps the text and sends nothing; it sends once the reply is done', (t) async {
        final app = await pumpApp(t, prefs: prefs, tab: AppTab.chat);
        await t.enterText(find.byKey(const ValueKey('composer')), first);
        await t.tap(find.byKey(const ValueKey('send')));
        await t.pump(const Duration(milliseconds: 40));
        expect(app.state.isResponding, isTrue);
        expect(_composerText(t), isEmpty, reason: 'an accepted message clears the field');

        // Typed and submitted with Enter while the reply streams.
        await t.enterText(find.byKey(const ValueKey('composer')), second);
        await t.testTextInput.receiveAction(TextInputAction.send);
        await t.pump();
        expect(_composerText(t), second, reason: 'nothing is lost');
        expect(_userTexts(app.state), [first], reason: 'nothing is sent while busy');
        // The round button is Stop while the reply streams.
        expect(find.byKey(const ValueKey('stop')), findsOneWidget);
        expect(find.byKey(const ValueKey('send')), findsNothing);

        await settleReply(t, app.state);
        expect(_composerText(t), second);
        await t.tap(find.byKey(const ValueKey('send')));
        await t.pump(const Duration(milliseconds: 40));
        expect(_userTexts(app.state), [first, second]);
        expect(_composerText(t), isEmpty);
        await settleReply(t, app.state);
      });
    }

    test('sendMessage refuses while busy and only calls onAccepted for an accepted message', () async {
      SharedPreferences.setMockInitialValues(onboardedPrefs());
      final ai = _ControlledAI();
      final state = AppState(storage: await StorageService.create(), ai: ai, store: FakeStoreService(entitled: true));
      var accepted = 0;
      final sending = state.sendMessage('One', onAccepted: () => accepted++);
      // Refused at once: the first send already holds the chat.
      expect(await state.sendMessage('Two', onAccepted: () => accepted++), isFalse);
      await pumpEventQueue();
      expect(accepted, 1, reason: 'called when the message is added, before the reply');
      expect(state.isResponding, isTrue);
      ai.streams.single
        ..add('Reply')
        ..close();
      expect(await sending, isTrue);
    });
  });

  group('reply interrupted by a restart', () {
    test('a placeholder is saved when the reply starts; after a restart it is interrupted and retryable', () async {
      SharedPreferences.setMockInitialValues(onboardedPrefs());
      final storage = await StorageService.create();
      final ai = _ControlledAI();
      final state = AppState(storage: storage, ai: ai, store: FakeStoreService(entitled: true));
      unawaited(state.sendMessage('Is this opener ok?'));
      await pumpEventQueue();
      expect(state.isResponding, isTrue);

      // What is on disk while the reply streams (no chunk has arrived yet).
      final saved = storage.loadThreads().first.messages;
      expect(saved.last.isUser, isFalse);
      expect(saved.last.status, MessageStatus.interrupted);
      expect(saved[saved.length - 2].text, 'Is this opener ok?');

      // The app restarts mid-reply.
      final ai2 = _ControlledAI();
      final relaunched = AppState(storage: await StorageService.create(), ai: ai2, store: FakeStoreService(entitled: true));
      expect(relaunched.activeThread!.messages.last.status, MessageStatus.interrupted);
      expect(relaunched.canRetry, isTrue);
      final retry = relaunched.retryLastReply();
      await pumpEventQueue();
      ai2.streams.single
        ..add('Yes, send it.')
        ..close();
      expect(await retry, isTrue);
      final msgs = relaunched.activeThread!.messages;
      expect(msgs.last.status, MessageStatus.ok);
      expect(msgs.last.text, 'Yes, send it.');
      expect(msgs.where((m) => m.status != MessageStatus.ok), isEmpty, reason: 'the interrupted reply is replaced');
    });

    test('a partial reply saved mid-stream reloads as interrupted, never sent as history', () {
      final m = ChatMessage.fromJson(
          ChatMessage(id: 'c', role: MessageRole.coach, text: 'Half a', createdAt: DateTime(2026), isStreaming: true).toJson());
      expect(m.status, MessageStatus.interrupted);
      expect(m.isComplete, isFalse);
      expect(ChatMessage.fromJson({'id': 'x', 'role': 'coach', 'text': 'Hal', 'isStreaming': true}).status,
          MessageStatus.interrupted);
    });

    test('a conversation saved before the placeholder existed (ends on the user) gets an interrupted reply', () async {
      SharedPreferences.setMockInitialValues({...onboardedPrefs(), 'dw_threads': _threadEndingOnUser('ava', 'Help me reply')});
      final state = AppState(storage: await StorageService.create(), ai: _ControlledAI(), store: FakeStoreService(entitled: true));
      final last = state.activeThread!.messages.last;
      expect(last.isUser, isFalse);
      expect(last.status, MessageStatus.interrupted);
      expect(state.canRetry, isTrue);
      expect(state.activeThread!.preview, 'Help me reply', reason: 'the preview skips the empty placeholder');
    });

    for (final lang in ['en', 'es']) {
      testWidgets('[$lang] the chat shows "reply interrupted" with Try again, and Try again answers', (t) async {
        final coach = lang == 'es' ? 'sofia' : 'ava';
        final text = lang == 'es' ? 'Dame un buen primer mensaje' : 'Give me a strong opener';
        final app = await pumpApp(t,
            prefs: {...(lang == 'es' ? spanishPrefs() : onboardedPrefs()), 'dw_threads': _threadEndingOnUser(coach, text)},
            tab: AppTab.chat);
        await t.pumpAndSettle();
        expect(
            find.text(lang == 'es'
                ? 'La respuesta se interrumpió al cerrarse la app. Tu mensaje está guardado.'
                : 'The reply was interrupted when the app closed. Your message is saved.'),
            findsOneWidget);
        expect(find.byKey(const ValueKey('retry')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('retry')));
        await t.pump();
        await settleReply(t, app.state);
        expect(find.byKey(const ValueKey('reply-failed')), findsNothing);
        expect(app.state.activeThread!.messages.last.status, MessageStatus.ok);
        expect(app.state.activeThread!.messages.last.text, isNotEmpty);
      });
    }
  });
}
