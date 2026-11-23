// A lapsed subscription that swaps the tabs for the paywall (it had not
// been closed this session) closes the chat. What the user was typing is
// kept in memory and is back in the composer once they subscribe or
// restore, never sent by itself; nothing reaches the backend meanwhile;
// "Delete all conversations" and "Delete my data" drop the kept draft.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/screens/paywall_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';

import 'helpers.dart';

class _CountingAI implements AIService {
  int calls = 0;
  @override
  String get providerLabel => 'counting';
  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) {
    calls++;
    return Stream.fromIterable(['ok']);
  }
}

Finder get _composer => find.byKey(const ValueKey('composer'));
String _composerText(WidgetTester t) => t.widget<TextField>(_composer).controller!.text;

/// The whole app with a counting backend.
Future<(TestApp, _CountingAI)> _pump(WidgetTester t, FakeStoreService store, {AppTab tab = AppTab.chat}) async {
  setSurface(t, const Size(390, 844), 1);
  SharedPreferences.setMockInitialValues(onboardedPrefs());
  final storage = await StorageService.create();
  final ai = _CountingAI();
  final app = TestApp(AppState(storage: storage, ai: ai, store: store), store, storage);
  await t.pumpWidget(wrap(app, DateWiseApp(initialTab: tab)));
  await t.pumpAndSettle();
  return (app, ai);
}

/// Subscribes (the fake store answers after 10 ms of test time).
Future<void> _buy(WidgetTester t, FakeStoreService store) async {
  final bought = store.buy();
  await t.pump(const Duration(milliseconds: 20));
  await bought;
  await t.pumpAndSettle();
}

void main() {
  group('paywall interrupting the chat', () {
    testWidgets('a typed draft is back in the composer after subscribing, and is not sent', (t) async {
      final store = FakeStoreService(entitled: true);
      final (app, ai) = await _pump(t, store);
      await t.enterText(_composer, 'What should I wear on Friday');
      await t.pump();
      store.expire();
      await t.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(_composer, findsNothing);
      await t.ensureVisible(find.byKey(const ValueKey('paywall-subscribe')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('paywall-subscribe')));
      await t.pump(const Duration(milliseconds: 20));
      await t.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      expect(_composerText(t), 'What should I wear on Friday');
      expect(ai.calls, 0, reason: 'the draft is never sent by itself');
      expect(app.state.activeThread?.messages ?? const [], isEmpty);
    });

    testWidgets('restoring returns to the chat with the draft, even from another tab', (t) async {
      final store = FakeStoreService(entitled: true);
      final (_, ai) = await _pump(t, store, tab: AppTab.home);
      await t.tap(find.byKey(const ValueKey('tab-chat')));
      await t.pumpAndSettle();
      await t.enterText(_composer, 'Is it too soon to call');
      await t.pump();
      store.expire();
      await t.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      // Subscribed again (from the paywall).
      await _buy(t, store);
      expect(find.byType(PaywallScreen), findsNothing);
      final chat = t.widget<IndexedStack>(find.byType(IndexedStack).first);
      expect(chat.index, AppTab.chat.index, reason: 'back in the chat');
      expect(_composerText(t), 'Is it too soon to call');
      expect(ai.calls, 0);
    });

    testWidgets('closing the paywall without subscribing: the draft stays, and sending reaches nothing', (t) async {
      final store = FakeStoreService(entitled: true);
      final (app, ai) = await _pump(t, store);
      await t.enterText(_composer, 'Help me reply to her');
      await t.pump();
      store.expire();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('paywall-close')));
      await t.pumpAndSettle();
      expect(await app.state.sendMessage('Help me reply to her'), isFalse);
      expect(ai.calls, 0, reason: 'nothing reaches the backend without a subscription');
      // Subscribing later (paywall closed: the tabs stayed) shows the draft.
      await _buy(t, store);
      expect(_composerText(t), 'Help me reply to her');
      expect(ai.calls, 0);
    });
  });

  group('kept drafts and deleting', () {
    Future<AppState> lapsedWithDraft() async {
      final app = await makeState(prefs: onboardedPrefs());
      app.state.keepDraft('a private thought');
      expect(app.state.hasDraft, isTrue);
      return app.state;
    }

    test('Delete all conversations drops the kept draft', () async {
      final state = await lapsedWithDraft();
      await state.deleteAllConversations();
      expect(state.hasDraft, isFalse);
      expect(state.takeDraft(), isNull);
    });

    test('Delete my data drops the kept draft', () async {
      final state = await lapsedWithDraft();
      await state.deleteMyData();
      expect(state.hasDraft, isFalse);
      expect(state.takeDraft(), isNull);
    });

    test('a draft is kept in memory only, per coach and conversation', () async {
      final app = await makeState(prefs: onboardedPrefs());
      final prefs = await SharedPreferences.getInstance();
      final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
      app.state.keepDraft('only on this device');
      expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, before, reason: 'nothing written to storage');
      await app.state.selectCoach('sofia');
      expect(app.state.takeDraft(), isNull, reason: 'another coach has its own draft');
      await app.state.selectCoach('ava');
      expect(app.state.takeDraft(), 'only on this device');
      expect(app.state.takeDraft(), isNull, reason: 'taken once');
    });

    testWidgets('Delete my data while a kept draft is in the closing chat leaves nothing behind', (t) async {
      final store = FakeStoreService(entitled: true);
      final (app, _) = await _pump(t, store);
      await t.enterText(_composer, 'Something private');
      await t.pump();
      store.expire();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('paywall-close')));
      await t.pumpAndSettle();
      expect(app.state.hasDraft, isFalse, reason: 'back in the composer');
      // The chat closes as the app returns to the welcome screen: its text
      // must not be kept again.
      await app.state.deleteMyData();
      await t.pumpAndSettle();
      expect(_composer, findsNothing);
      expect(app.state.hasDraft, isFalse);
      expect(app.state.takeDraft(), isNull);
    });
  });
}
