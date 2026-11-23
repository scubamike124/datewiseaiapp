// "Find a table" (owner decision 2026-11-23: no sign-in for v1; booking is a
// link-out to Apple Maps only). The button appears under the coach's reply on
// first-date plans, opens exactly https://maps.apple.com/?q=<term> in the UI
// language, launches only on tap, and is absent elsewhere.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';

import 'package:datewise_ai/app_links.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';
import 'package:datewise_ai/widgets/find_table_link.dart';

import 'helpers.dart';

final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

/// A coach whose replies arrive only when the test adds them.
class _HeldAI implements AIService {
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
  String get providerLabel => 'held';
}

void main() {
  late List<Uri> launched;
  final realLaunch = FindTableLink.launch;
  tearDown(() => FindTableLink.launch = realLaunch);
  setUp(() {
    launched = [];
    FindTableLink.launch = (uri) async {
      launched.add(uri);
      return true;
    };
  });

  Future<void> openDatePlan(WidgetTester tester, TestApp app) async {
    await tester.ensureVisible(find.byKey(const ValueKey('tile-date')));
    await tester.tap(find.byKey(const ValueKey('tile-date')));
    await tester.pump();
    await tester.pump();
    await settleReply(tester, app.state);
  }

  test('builds the exact, URL-encoded Apple Maps search', () {
    expect(AppLinks.findTableUri('restaurants').toString(), 'https://maps.apple.com/?q=restaurants');
    expect(AppLinks.findTableUri('restaurantes').toString(), 'https://maps.apple.com/?q=restaurantes');
    expect(AppLinks.findTableUri(' Café Olé & bar ').toString(), 'https://maps.apple.com/?q=Caf%C3%A9%20Ol%C3%A9%20%26%20bar');
  });

  test('date-plan path: the quick action, plan item and coach starters, EN and ES', () {
    ChatMessage user(String t) => ChatMessage(id: t, role: MessageRole.user, text: t, createdAt: DateTime(2026));
    final greeting = ChatMessage(id: 'g', role: MessageRole.coach, text: 'Hi', createdAt: DateTime(2026));
    for (final p in [
      'Help me prepare for a date.',
      'Help me plan a great first date.',
      'Ayúdame a prepararme para una cita.',
      'Plan a first date',
      'Planea una primera cita',
    ]) {
      expect(FindTableLink.isDatePlan([greeting, user(p)]), isTrue, reason: p);
    }
    expect(Coaches.ethan.starters, contains('Plan a first date'));
    expect(Coaches.diego.starters, contains('Planea una primera cita'));
    expect(FindTableLink.isDatePlan([greeting, user('Help me reply to a message.')]), isFalse);
    expect(FindTableLink.isDatePlan([greeting]), isFalse);
    // Only the conversation's first message decides: a later date question
    // in another conversation does not turn it into a date plan.
    expect(FindTableLink.isDatePlan([user('Rewrite my dating bio.'), user('Help me prepare for a date.')]), isFalse);
  });

  testWidgets('EN: shown under the reply on the date path, launches only on tap', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs());
    await openDatePlan(tester, app);
    final button = find.byKey(const ValueKey('find-table'));
    expect(button, findsOneWidget);
    expect(find.text('Find a table'), findsOneWidget);
    expect(launched, isEmpty, reason: 'nothing opens until the user taps');
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));

    final handle = tester.ensureSemantics();
    await tester.pump();
    final node = tester.getSemantics(button);
    expect(node.label, 'Find a table nearby. Opens Apple Maps.');
    expect(node.flagsCollection.isLink, isTrue);
    expect(node.flagsCollection.isButton, isFalse);
    handle.dispose();

    await tester.tap(button);
    await tester.pump();
    expect(launched.map((u) => u.toString()), ['https://maps.apple.com/?q=restaurants']);
    // The chat stays on the device: the link carries only the search term.
    expect(launched.single.queryParameters.keys, ['q']);
  }, variant: ios);

  testWidgets('ES: Spanish label and search term', (tester) async {
    final app = await pumpApp(tester, prefs: spanishPrefs());
    await openDatePlan(tester, app);
    expect(find.text('Buscar mesa'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('find-table')));
    await tester.pump();
    expect(launched.map((u) => u.toString()), ['https://maps.apple.com/?q=restaurantes']);
  }, variant: ios);

  testWidgets('not shown on other paths', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs());
    await tester.ensureVisible(find.byKey(const ValueKey('tile-reply')));
    await tester.tap(find.byKey(const ValueKey('tile-reply')));
    await tester.pump();
    await tester.pump();
    await settleReply(tester, app.state);
    expect(find.byKey(const ValueKey('find-table')), findsNothing);
    expect(launched, isEmpty);
  }, variant: ios);

  testWidgets('not shown where Apple Maps is not the phone map (Android, web)', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs());
    await openDatePlan(tester, app);
    expect(FindTableLink.available, isFalse);
    expect(find.byKey(const ValueKey('find-table')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final (lang, prefs) in [('EN', onboardedPrefs()), ('ES', spanishPrefs())]) {
    testWidgets('$lang: fits at text scale 2.0 on the smallest phone', (tester) async {
      final app = await pumpApp(tester, size: const Size(375, 667), scale: 2.0, prefs: prefs);
      await openDatePlan(tester, app);
      final button = find.byKey(const ValueKey('find-table'));
      await tester.ensureVisible(button);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      expect(tester.getRect(button).right, lessThanOrEqualTo(375));
    }, variant: ios);
  }

  testWidgets('hidden while the reply streams and after a failed reply', (tester) async {
    setSurface(tester, const Size(390, 844), 1.0);
    SharedPreferences.setMockInitialValues(onboardedPrefs());
    final ai = _HeldAI();
    final storage = await StorageService.create();
    final store = FakeStoreService(entitled: true);
    final state = AppState(storage: storage, ai: ai, store: store);
    await tester.pumpWidget(wrap(TestApp(state, store, storage), const DateWiseApp(initialTab: AppTab.chat)));
    await tester.pump();
    final button = find.byKey(const ValueKey('find-table'));

    // Streaming: part of the reply is on screen, the button is not.
    unawaited(state.sendMessage('Help me prepare for a date.'));
    await tester.pump();
    ai.streams.single.add('Keep it simple: **a café** for an hour. ');
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.isResponding, isTrue);
    expect(find.textContaining('a café', findRichText: true), findsWidgets);
    expect(button, findsNothing);
    await ai.streams.single.close();
    for (var i = 0; i < 40 && state.isResponding; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(button, findsOneWidget, reason: 'shown once the reply is complete');

    // A failed follow-up reply: the button goes with it.
    unawaited(state.sendMessage('Any other idea?'));
    await tester.pump();
    ai.streams.last.addError(Exception('network down'));
    await ai.streams.last.close();
    for (var i = 0; i < 40 && state.isResponding; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.activeThread!.messages.last.status, isNot(MessageStatus.ok));
    expect(button, findsNothing);
    expect(launched, isEmpty);
  }, variant: ios);
}
