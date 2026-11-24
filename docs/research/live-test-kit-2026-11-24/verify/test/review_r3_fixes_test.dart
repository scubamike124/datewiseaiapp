// Independent re-test of the round-2 fixes (2026-11-24): R1, R2, R3 and the
// m3 headroom note. Each group names its finding.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/dev/review_mode.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/screens/paywall_screen.dart';
import 'package:datewise_ai/screens/settings_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';

import 'helpers.dart';

const _consentTitle = 'Share messages with our AI provider?';

ShellController _shell(WidgetTester t) =>
    Provider.of<ShellController>(t.element(find.byType(DwTabBar)), listen: false);

/// A saved conversation whose last reply was stopped (Try again is offered).
Map<String, Object> _stoppedReply(Map<String, Object> base) => {
      ...base,
      'dw_threads': jsonEncode([
        {
          'id': 't1',
          'title': 'Opener help',
          'createdAt': '2026-11-20T10:00:00.000',
          'updatedAt': '2026-11-20T10:01:00.000',
          'coachId': 'ava',
          'messages': [
            {'id': 'u1', 'role': 'user', 'text': 'Give me a strong opener', 'createdAt': '2026-11-20T10:00:00.000'},
            {'id': 'c1', 'role': 'coach', 'text': 'Try', 'status': 'stopped', 'createdAt': '2026-11-20T10:01:00.000'},
          ],
        },
      ]),
    };

void main() {
  // --- R1: the "open Chat after onboarding" flag is used once ------------------------------------
  group('open Chat after onboarding is used once (R1)', () {
    testWidgets('a later rebuild of the tab shell (after a paywall) opens the requested tab, not Chat', (tester) async {
      setSurface(tester, const Size(390, 844), 1);
      final store = FakeStoreService(entitled: true);
      final app = await makeState(store: store);
      await tester.pumpWidget(wrap(app, const DateWiseApp()));
      await tester.pump();
      await app.state.completeOnboarding(
          goals: const [CoachingGoal.conversations], language: CoachLanguage.en, coachId: 'ava', adultConfirmed: true);
      await tester.pumpAndSettle();
      expect(_shell(tester).tab, AppTab.chat, reason: 'onboarding still lands on Chat (QA m-4)');
      expect(app.state.openChatFirst, isFalse, reason: 'consumed');

      // The shell is rebuilt from scratch (subscription lapses, paywall closed).
      store.expire();
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      app.state.dismissPaywall();
      await tester.pumpAndSettle();
      expect(_shell(tester).tab, AppTab.home);
    });

    for (final (screen, tab) in [
      ('settings', AppTab.you),
      ('progress', AppTab.progress),
      ('home', AppTab.home),
      ('coaches', AppTab.coaches),
      ('chat', AppTab.chat),
    ]) {
      testWidgets('review link ?screen=$screen opens $tab', (tester) async {
        setSurface(tester, const Size(390, 844), 1);
        final app = await makeState(prefs: const {}, entitled: false);
        final initial = (await tester.runAsync(() => ReviewMode.seed(screen, app.state, app.store)))!;
        expect(initial, tab);
        expect(app.state.openChatFirst, isFalse);
        await tester.pumpWidget(wrap(app, DateWiseApp(initialTab: initial)));
        await settleReply(tester, app.state);
        await tester.pumpAndSettle();
        expect(_shell(tester).tab, tab);
        if (tab == AppTab.you) expect(find.byType(SettingsScreen), findsOneWidget);
      });
    }
  });

  // --- R2: Try again after consent was withdrawn ------------------------------------------------
  group('Try again after AI sharing was switched off (R2)', () {
    Map<String, Object> withdrawn() => _stoppedReply(onboardedPrefs())
      ..remove('dw_ai_consent')
      ..remove('dw_ai_consent_version');

    testWidgets('asks for consent again; Not now sends nothing and keeps the stopped reply', (tester) async {
      final app = await pumpApp(tester, prefs: withdrawn(), tab: AppTab.chat);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('retry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('retry')));
      await tester.pumpAndSettle();
      expect(find.text(_consentTitle), findsOneWidget, reason: 'not a dead button');
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(app.state.aiConsentGiven, isFalse);
      expect(app.state.isResponding, isFalse);
      final msgs = app.state.activeThread!.messages;
      expect(msgs.last.status, MessageStatus.stopped);
      expect(msgs.length, 2);
      expect(find.byKey(const ValueKey('retry')), findsOneWidget);
    });

    testWidgets('Agree retries the reply, like the send path', (tester) async {
      final app = await pumpApp(tester, prefs: withdrawn(), tab: AppTab.chat);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('retry')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agree'));
      await tester.pump();
      await settleReply(tester, app.state);
      expect(app.state.aiConsentGiven, isTrue);
      final msgs = app.state.activeThread!.messages;
      expect(msgs.length, 2);
      expect(msgs.last.status, MessageStatus.ok);
      expect(msgs.last.text, isNot('Try'));
      expect(find.byKey(const ValueKey('retry')), findsNothing);
    });

    testWidgets('with consent, Try again retries without asking', (tester) async {
      final app = await pumpApp(tester, prefs: _stoppedReply(onboardedPrefs()), tab: AppTab.chat);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('retry')));
      await tester.pump();
      expect(find.text(_consentTitle), findsNothing);
      await settleReply(tester, app.state);
      expect(app.state.activeThread!.messages.last.status, MessageStatus.ok);
    });
  });

  // --- R3: versioned consent ---------------------------------------------------------------------
  group('consent is versioned (R3)', () {
    test('agreement to the older text (no version, or a lower one) is asked again', () async {
      expect(StorageService.aiConsentVersion, greaterThanOrEqualTo(2));
      for (final prefs in <Map<String, Object>>[
        {'dw_ai_consent': true},
        {'dw_ai_consent': true, 'dw_ai_consent_version': StorageService.aiConsentVersion - 1},
      ]) {
        final app = await makeState(prefs: {...onboardedPrefs()..remove('dw_ai_consent_version'), ...prefs});
        expect(app.storage.aiConsent, isFalse, reason: '$prefs');
        expect(app.state.aiConsentGiven, isFalse, reason: '$prefs');
        expect(await app.state.sendMessage('hi'), isFalse, reason: 'nothing is sent with the old consent');
      }
    });

    test('agreeing stores the current version; withdrawing removes both keys', () async {
      final app = await makeState(prefs: {...onboardedPrefs()..remove('dw_ai_consent')..remove('dw_ai_consent_version')});
      await app.state.giveAiConsent();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('dw_ai_consent'), isTrue);
      expect(prefs.getInt('dw_ai_consent_version'), StorageService.aiConsentVersion);
      final again = await makeState(prefs: {
        for (final k in prefs.getKeys()) k: prefs.get(k)!,
      });
      expect(again.state.aiConsentGiven, isTrue, reason: 'current consent survives a relaunch');
      await again.state.revokeAiConsent();
      final after = await SharedPreferences.getInstance();
      expect(after.getBool('dw_ai_consent'), isNull);
      expect(after.getInt('dw_ai_consent_version'), isNull);
    });

    testWidgets('an older consent brings back the consent dialog on the next send', (tester) async {
      final app = await pumpApp(tester,
          prefs: {...onboardedPrefs()..remove('dw_ai_consent_version')}, tab: AppTab.chat);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('composer')), 'Give me a strong opener');
      await tester.tap(find.byKey(const ValueKey('send')));
      await tester.pumpAndSettle();
      expect(find.text(_consentTitle), findsOneWidget);
      expect(find.textContaining('your country'), findsOneWidget, reason: 'the new disclosure is shown');
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(app.state.threads.expand((t) => t.messages), isEmpty);
    });
  });

  // --- m3 headroom: byte-aware history cap -------------------------------------------------------
  group('request body stays under the Worker cap for any text (m3 headroom)', () {
    const serverCap = 256 * 1024; // backend/worker.js MAX_CHAT_BODY_BYTES
    final svc = BackendAIService(endpoint: 'https://example.workers.dev');
    const profile = UserProfile(goals: [CoachingGoal.profile, CoachingGoal.conversations, CoachingGoal.dates]);

    List<ChatMessage> history(String Function(int i) text, {int turns = 30}) => [
          for (var i = 0; i < turns; i++)
            ChatMessage(
                id: 'm$i',
                role: i.isEven ? MessageRole.user : MessageRole.coach,
                text: text(i),
                createdAt: DateTime(2026)),
          ChatMessage(id: 'last', role: MessageRole.user, text: text(99), createdAt: DateTime(2026)),
        ];

    int bodyBytes(List<ChatMessage> h) =>
        utf8.encode(jsonEncode(svc.buildPayload(h, SubscriptionTier.magnet, profile, Coaches.fallback))).length;

    for (final (name, unit) in [
      ('CJK', '恋爱'),
      ('emoji', '😀'),
      ('accented and quotes', 'é"'),
      ('control characters', '\u0001'),
    ]) {
      test('$name: a full 24-turn history of 6,000-character turns fits with margin', () {
        final big = unit * 6000;
        final h = history((_) => big);
        final msgs = svc.buildMessages(h, SubscriptionTier.magnet, profile, Coaches.fallback);
        expect(msgs.length, 1 + BackendAIService.maxHistoryTurns, reason: 'all 24 turns are kept');
        final bytes = bodyBytes(h);
        expect(bytes, lessThan(serverCap * 0.9), reason: '$name: $bytes bytes');
        // The newest turn (the one being answered) is sent in full, up to 6,000 characters.
        final newest = msgs.last['content']!;
        expect(newest.length, inInclusiveRange(BackendAIService.maxMessageChars - 1, BackendAIService.maxMessageChars));
        expect(big.startsWith(newest), isTrue);
        // Older turns are trimmed on whole code points: no lone surrogate.
        for (final m in msgs.skip(1)) {
          final c = m['content']!;
          expect(c.runes.every((r) => r < 0xD800 || r > 0xDFFF), isTrue);
          expect(big.startsWith(c), isTrue);
        }
      });
    }

    test('ordinary text is not trimmed by the byte cap', () {
      final text = 'Hola, ¿qué tal? ' * 300; // 4,800 characters
      final msgs = svc.buildMessages(history((_) => text, turns: 4), SubscriptionTier.magnet, profile, Coaches.fallback);
      expect(msgs.skip(1).every((m) => m['content'] == text.trim()), isTrue);
    });

    test('capJsonBytes counts UTF-8 after JSON escaping and keeps whole code points', () {
      expect(BackendAIService.capJsonBytes('abc', 3), 'abc');
      expect(BackendAIService.capJsonBytes('恋爱恋', 7), '恋爱');
      expect(BackendAIService.capJsonBytes('😀😀', 7), '😀');
      expect(BackendAIService.capJsonBytes('""', 3), '"');
    });
  });
}
