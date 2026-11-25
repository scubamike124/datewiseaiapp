// "Find a table" and the "Plan a table" sheet (owner decisions 2026-11-23 and
// 2026-11-25: no sign-in, no partner API, no booking in the app, $0). The
// button appears under the coach's reply on date plans and restaurant or
// reservation questions, in text chat and in the voice conversation, on every
// platform. It opens the planner; the planner's results are search links that
// carry only what the user typed (never chat text), open only on tap, and
// never claim availability, a hold or a booking.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';

import 'package:datewise_ai/app_links.dart';
import 'package:datewise_ai/l10n/l10n.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/table_plan.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';
import 'package:datewise_ai/widgets/find_table_link.dart';
import 'package:datewise_ai/widgets/plan_table_sheet.dart';

import 'helpers.dart';

final ios = TargetPlatformVariant.only(TargetPlatform.iOS);
final android = TargetPlatformVariant.only(TargetPlatform.android);
final en = lookupAppLocalizations(const Locale('en'));
final es = lookupAppLocalizations(const Locale('es'));

/// The owner's example: Chicago, Italian, $$, Saturday 2026-11-28 at 19:30, 4 people.
const exampleOpenTable = 'https://www.opentable.com/s/?covers=4&dateTime=2026-11-28T19%3A30%3A00&term=Italian%20Chicago';
const exampleGoogle = 'https://www.google.com/maps/search/?api=1&query=moderately%20priced%20Italian%20restaurants%20in%20Chicago';
const exampleApple = 'https://maps.apple.com/?q=moderately%20priced%20Italian%20restaurants%20in%20Chicago';

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

/// Speech that is ready, so the voice conversation can be opened.
class _Speech implements SpeechService {
  @override
  bool get available => true;
  @override
  bool get permissionDenied => false;
  @override
  bool get canOpenSettings => false;
  @override
  Future<void> openSettings() async {}
  @override
  Future<bool> ensureReady() async => true;
  @override
  Future<void> recheckPermission() async {}
  @override
  Future<SpeechStart> start({required String localeId, List<String> fallbackLocales = const [], required void Function(String words) onWords, void Function()? onUnsupported, void Function(String words)? onEnded}) async => SpeechStart.started;
  @override
  Future<String> stop() async => '';
  @override
  Future<void> cancel() async {}
}

ChatMessage _user(String t) => ChatMessage(id: t, role: MessageRole.user, text: t, createdAt: DateTime(2026));
final _greeting = ChatMessage(id: 'g', role: MessageRole.coach, text: 'Hi', createdAt: DateTime(2026));

void main() {
  late List<Uri> launched;
  final realLaunch = PlanTableSheet.launch;
  final realNow = PlanTableSheet.now;
  tearDown(() {
    PlanTableSheet.launch = realLaunch;
    PlanTableSheet.now = realNow;
  });
  setUp(() {
    launched = [];
    PlanTableSheet.launch = (uri) async {
      launched.add(uri);
      return true;
    };
    // Saturday 2026-11-28, mid-afternoon: the default is today at 19:30.
    PlanTableSheet.now = () => DateTime(2026, 11, 28, 15, 5);
  });

  Future<void> openDatePlan(WidgetTester tester, TestApp app) async {
    await tester.ensureVisible(find.byKey(const ValueKey('tile-date')));
    await tester.tap(find.byKey(const ValueKey('tile-date')));
    await tester.pump();
    await tester.pump();
    await settleReply(tester, app.state);
  }

  Future<void> openSheet(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('find-table'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-table')), findsOneWidget);
  }

  Future<void> tapIn(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  /// Fills in the owner's example (the date and time are the defaults).
  Future<void> fillExample(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('plan-table-area')), 'Chicago');
    await tester.enterText(find.byKey(const ValueKey('plan-table-cuisine')), 'Italian');
    await tapIn(tester, 'plan-table-budget-2');
    await tapIn(tester, 'plan-table-more');
    await tapIn(tester, 'plan-table-more');
  }

  group('links', () {
    test('Apple Maps: the exact, URL-encoded search', () {
      expect(AppLinks.findTableUri('restaurants').toString(), 'https://maps.apple.com/?q=restaurants');
      expect(AppLinks.findTableUri(' Café Olé & bar ').toString(), 'https://maps.apple.com/?q=Caf%C3%A9%20Ol%C3%A9%20%26%20bar');
    });

    test('Google Maps: the documented api=1 search URL, no key', () {
      final u = AppLinks.googleMapsSearchUri('Italian restaurants in Chicago');
      expect(u.toString(), 'https://www.google.com/maps/search/?api=1&query=Italian%20restaurants%20in%20Chicago');
      expect(u.queryParameters, {'api': '1', 'query': 'Italian restaurants in Chicago'});
      expect(AppLinks.googleMapsSearchUri('Café & bar').queryParameters['query'], 'Café & bar');
    });

    test('OpenTable: covers, local dateTime and term; no term when empty', () {
      final u = AppLinks.openTableSearchUri(covers: 4, dateTime: DateTime(2026, 11, 28, 19, 30), term: 'Italian Chicago');
      expect(u.toString(), exampleOpenTable);
      expect(u.queryParameters, {'covers': '4', 'dateTime': '2026-11-28T19:30:00', 'term': 'Italian Chicago'});
      expect(AppLinks.openTableSearchUri(covers: 2, dateTime: DateTime(2027, 1, 5, 8, 0)).toString(),
          'https://www.opentable.com/s/?covers=2&dateTime=2027-01-05T08%3A00%3A00');
      expect(AppLinks.openTableSearchUri(covers: 2, dateTime: DateTime(2026, 12, 1, 20), term: 'Café & bar').queryParameters['term'],
          'Café & bar');
    });

    test("the owner's example, EN and ES", () {
      final plan = TablePlan(
        area: 'Chicago',
        cuisine: 'Italian',
        budget: 2,
        date: DateTime(2026, 11, 28),
        time: const TimeOfDay(hour: 19, minute: 30),
        partySize: 4,
      );
      expect(plan.openTableUri.toString(), exampleOpenTable);
      expect(plan.googleMapsUri(en).toString(), exampleGoogle);
      expect(plan.appleMapsUri(en).toString(), exampleApple);
      final esPlan = TablePlan(
        area: 'Polanco',
        cuisine: 'italiana',
        budget: 2,
        date: DateTime(2026, 11, 28),
        time: const TimeOfDay(hour: 19, minute: 30),
        partySize: 4,
      );
      expect(esPlan.mapsQuery(es), 'restaurantes italiana de precio medio en Polanco');
      // OpenTable's term is the same in any UI language: what the user typed.
      expect(esPlan.openTableUri.queryParameters['term'], 'italiana Polanco');
    });

    test('empty parts are dropped; text is one trimmed line, capped', () {
      TablePlan plan({String area = '', String cuisine = '', int budget = 0}) => TablePlan(
          area: area, cuisine: cuisine, budget: budget, date: DateTime(2026, 11, 28), time: const TimeOfDay(hour: 19, minute: 30));
      expect(plan().mapsQuery(en), 'restaurants');
      expect(plan().mapsQuery(es), 'restaurantes');
      expect(plan().openTableUri.queryParameters.containsKey('term'), isFalse);
      expect(plan().openTableUri.queryParameters['covers'], '2', reason: 'party of 2 by default');
      expect(plan(area: '  Wicker\n Park ').mapsQuery(en), 'restaurants in Wicker Park');
      expect(plan(budget: 1).mapsQuery(en), 'cheap restaurants');
      expect(plan(budget: 4, cuisine: 'sushi').mapsQuery(en), 'fine dining sushi restaurants');
      expect(plan(budget: 3).mapsQuery(es), 'restaurantes elegantes');
      expect(plan(area: 'x' * 200).area.length, TablePlan.maxTextLength);
    });

    test('default date and time: 19:30 today, or the next half hour', () {
      (DateTime, TimeOfDay) d(int h, int m) => TablePlan.defaultsFor(DateTime(2026, 11, 28, h, m));
      expect(d(9, 0), (DateTime(2026, 11, 28), const TimeOfDay(hour: 19, minute: 30)));
      expect(d(19, 30), (DateTime(2026, 11, 28), const TimeOfDay(hour: 19, minute: 30)));
      expect(d(19, 31), (DateTime(2026, 11, 28), const TimeOfDay(hour: 20, minute: 0)));
      expect(d(20, 10), (DateTime(2026, 11, 28), const TimeOfDay(hour: 20, minute: 30)));
      expect(d(23, 29), (DateTime(2026, 11, 28), const TimeOfDay(hour: 23, minute: 30)));
      // No half hour left today: tomorrow at 19:30 (also across a month end).
      expect(d(23, 40), (DateTime(2026, 11, 29), const TimeOfDay(hour: 19, minute: 30)));
      expect(TablePlan.defaultsFor(DateTime(2026, 11, 30, 23, 45)), (DateTime(2026, 12, 1), const TimeOfDay(hour: 19, minute: 30)));
    });
  });

  test('date-plan path: the quick action, plan item and coach starters, EN and ES', () {
    for (final p in [
      'Help me prepare for a date.',
      'Help me plan a great first date.',
      'Ayúdame a prepararme para una cita.',
      'Plan a first date',
      'Planea una primera cita',
    ]) {
      expect(FindTableLink.isDatePlan([_greeting, _user(p)]), isTrue, reason: p);
    }
    expect(Coaches.ethan.starters, contains('Plan a first date'));
    expect(Coaches.diego.starters, contains('Planea una primera cita'));
    expect(FindTableLink.isDatePlan([_greeting, _user('Help me reply to a message.')]), isFalse);
    expect(FindTableLink.isDatePlan([_greeting]), isFalse);
    // Only the conversation's first message decides: a later date question
    // in another conversation does not turn it into a date plan.
    expect(FindTableLink.isDatePlan([_user('Rewrite my dating bio.'), _user('Help me prepare for a date.')]), isFalse);
  });

  group('wantsTable: restaurant and reservation words, whole words, Unicode-aware', () {
    bool wants(String t) => FindTableLink.wantsTable([_greeting, _user(t)]);

    test('English positives', () {
      for (final p in [
        'Can you book reservations?',
        'I need a reservation for Friday',
        'Can you help me book a table for two on Friday?',
        'Book us a table somewhere nice',
        'Can you get us a table at 8?',
        'Where can we get a table tonight?',
        'Table for 2 please',
        'Where should we go for dinner?',
        'Any romantic restaurants near me?',
        'Good spot for brunch?',
        'Lunch date ideas',
        'Where should we grab drinks?',
        'RESTAURANT ideas for Saturday',
      ]) {
        expect(wants(p), isTrue, reason: p);
      }
    });

    test('Spanish positives (accents included)', () {
      for (final p in [
        '¿Puedes hacer una reserva?',
        '¿Puedes hacer una reservación?',
        'Necesito reservaciones para el sábado',
        '¿Me ayudas a reservar?',
        'Busco un restaurante romántico para el sábado',
        '¿Dónde podemos cenar?',
        '¿Dónde cenamos el viernes?',
        'Una cena tranquila',
        'Mesa para dos',
        '¿Conoces un buen lugar de comida mexicana?',
        'Ideas para un almuerzo',
        'RESERVACIÓN para cuatro',
      ]) {
        expect(wants(p), isTrue, reason: p);
      }
    });

    test('negatives: other topics and words that only contain a table word', () {
      for (final p in [
        'Help me reply to a message.',
        'How do I text her back?',
        'She left her tablet at my place',
        'He is very reserved',
        'Es muy reservado',
        'Estoy reservando energía para el lunes',
        'My dinnerware is ugly',
        'Me gusta la cenaduría',
        'Sobremesa larga',
        '¿Cómo le respondo?',
        'Tengo una cita el sábado',
        'Booking.com sent me spam',
      ]) {
        expect(wants(p), isFalse, reason: p);
      }
    });

    test('the latest user message decides', () {
      expect(FindTableLink.wantsTable([_greeting]), isFalse);
      expect(FindTableLink.wantsTable([_user('Any restaurants?'), _user('How do I text her back?')]), isFalse);
      expect(FindTableLink.wantsTable([_user('How do I text her back?'), _user('And a restaurant?')]), isTrue);
    });
  });

  testWidgets('EN: the button opens the planner; the planner launches the exact links only on tap', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs());
    await openDatePlan(tester, app);
    final button = find.byKey(const ValueKey('find-table'));
    expect(button, findsOneWidget);
    expect(find.text('Find a table'), findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));

    final handle = tester.ensureSemantics();
    await tester.pump();
    final node = tester.getSemantics(button);
    expect(node.label, 'Find a table. Opens a restaurant search planner.');
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();

    await openSheet(tester);
    expect(launched, isEmpty, reason: 'opening the planner opens nothing outside the app');
    expect(find.text('Plan a table'), findsOneWidget);
    expect(find.textContaining("DateWise can't see availability or book."), findsOneWidget);
    expect(find.textContaining('you book there'), findsOneWidget);
    // Defaults: today (the injected clock), 19:30, 2 people.
    expect(find.text('2 people'), findsOneWidget);
    expect(find.textContaining('7:30'), findsOneWidget);
    expect(find.textContaining('Nov 28'), findsOneWidget);
    // Never an availability, hold or confirmation claim.
    for (final claim in ['available', 'confirmed', 'booked', 'held']) {
      expect(find.textContaining(RegExp('\\b$claim\\b', caseSensitive: false)), findsNothing, reason: claim);
    }

    await fillExample(tester);
    expect(find.text('4 people'), findsOneWidget);
    await tapIn(tester, 'plan-table-opentable');
    await tapIn(tester, 'plan-table-google');
    await tapIn(tester, 'plan-table-apple');
    expect(launched.map((u) => u.toString()), [exampleOpenTable, exampleGoogle, exampleApple]);
    // The chat stays on the device: every value in every link is something typed or picked in the planner.
    const typed = {'4', '2026-11-28T19:30:00', 'Italian Chicago', '1', 'moderately priced Italian restaurants in Chicago'};
    for (final u in launched) {
      for (final v in u.queryParameters.values) {
        expect(typed, contains(v), reason: u.toString());
      }
    }
    expect(app.state.activeThread!.messages.firstWhere((m) => m.isUser).text, 'Help me prepare for a date.');

    // Links are announced as links that leave the app.
    final h2 = tester.ensureSemantics();
    await tester.pump();
    final link = tester.getSemantics(find.byKey(const ValueKey('plan-table-opentable')));
    expect(link.label, 'Search OpenTable. Opens OpenTable outside DateWise.');
    expect(link.flagsCollection.isLink, isTrue);
    h2.dispose();
  }, variant: ios);

  testWidgets('ES: Spanish label, planner and search words', (tester) async {
    final app = await pumpApp(tester, prefs: spanishPrefs());
    await openDatePlan(tester, app);
    expect(find.text('Buscar mesa'), findsOneWidget);
    await openSheet(tester);
    expect(find.text('Planea tu mesa'), findsOneWidget);
    expect(find.textContaining('DateWise no puede ver la disponibilidad ni reservar.'), findsOneWidget);
    expect(find.text('2 personas'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('plan-table-area')), 'Polanco');
    await tester.enterText(find.byKey(const ValueKey('plan-table-cuisine')), 'italiana');
    await tapIn(tester, 'plan-table-budget-2');
    await tapIn(tester, 'plan-table-google');
    expect(launched.single.queryParameters['query'], 'restaurantes italiana de precio medio en Polanco');
  }, variant: ios);

  testWidgets('Android (and the web): OpenTable and Google Maps, no Apple Maps', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs());
    await openDatePlan(tester, app);
    expect(PlanTableSheet.appleMapsAvailable, isFalse);
    await openSheet(tester);
    expect(find.byKey(const ValueKey('plan-table-opentable')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-table-google')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-table-apple')), findsNothing);
    await fillExample(tester);
    await tapIn(tester, 'plan-table-opentable');
    await tapIn(tester, 'plan-table-google');
    expect(launched.map((u) => u.toString()), [exampleOpenTable, exampleGoogle]);
  }, variant: android);

  testWidgets('a failed launch says so in the sheet', (tester) async {
    PlanTableSheet.launch = (uri) async => false;
    final app = await pumpApp(tester, prefs: onboardedPrefs());
    await openDatePlan(tester, app);
    await openSheet(tester);
    await tapIn(tester, 'plan-table-opentable');
    expect(find.text('Could not open www.opentable.com'), findsOneWidget);
  }, variant: ios);

  testWidgets('party size stays within 1 to 20', (tester) async {
    final app = await pumpApp(tester, prefs: onboardedPrefs());
    await openDatePlan(tester, app);
    await openSheet(tester);
    await tapIn(tester, 'plan-table-fewer');
    expect(find.text('1 person'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('plan-table-fewer'))).onPressed, isNull);
    for (var i = 0; i < 25; i++) {
      await tapIn(tester, 'plan-table-more');
    }
    expect(find.text('20 people'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('plan-table-more'))).onPressed, isNull);
    await tapIn(tester, 'plan-table-opentable');
    expect(launched.single.queryParameters['covers'], '20');
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

  for (final (lang, prefs) in [('EN', onboardedPrefs()), ('ES', spanishPrefs())]) {
    testWidgets('$lang: button and planner fit at text scale 2.0 on the smallest phone', (tester) async {
      final app = await pumpApp(tester, size: const Size(375, 667), scale: 2.0, prefs: prefs);
      await openDatePlan(tester, app);
      final button = find.byKey(const ValueKey('find-table'));
      await tester.ensureVisible(button);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      expect(tester.getRect(button).right, lessThanOrEqualTo(375));

      await openSheet(tester);
      expect(tester.takeException(), isNull);
      for (final k in ['plan-table-area', 'plan-table-budget-4', 'plan-table-date', 'plan-table-time', 'plan-table-more', 'plan-table-opentable', 'plan-table-apple']) {
        final f = find.byKey(ValueKey(k));
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: k);
        final r = tester.getRect(f);
        expect(r.left, greaterThanOrEqualTo(0), reason: k);
        expect(r.right, lessThanOrEqualTo(375), reason: k);
        expect(r.height, greaterThanOrEqualTo(44), reason: k);
      }
      await tapIn(tester, 'plan-table-opentable');
      expect(launched.single.host, 'www.opentable.com');
    }, variant: ios);
  }

  testWidgets('voice conversation: the button is under the reply and the planner launches OpenTable with the party, date and time', (tester) async {
    setSurface(tester, const Size(390, 844), 1.0);
    // 21:10: the default becomes the next half hour, 21:30.
    PlanTableSheet.now = () => DateTime(2026, 11, 27, 21, 10);
    final app = await makeState(prefs: onboardedPrefs());
    await tester.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat), speech: _Speech()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-caption')), findsOneWidget, reason: 'in the voice conversation');

    // A spoken request reaches the coach as the user's message.
    unawaited(app.state.sendMessage('Can you book us a table for Friday?'));
    await tester.pump();
    await settleReply(tester, app.state);
    await openSheet(tester);
    expect(find.byKey(const ValueKey('voice-caption')), findsOneWidget, reason: 'still in voice mode under the sheet');
    expect(find.textContaining('9:30'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('plan-table-area')), 'Chicago');
    await tapIn(tester, 'plan-table-more');
    await tapIn(tester, 'plan-table-more');
    await tapIn(tester, 'plan-table-more');
    await tapIn(tester, 'plan-table-opentable');
    final u = launched.single;
    expect(u.host, 'www.opentable.com');
    expect(u.queryParameters, {'covers': '5', 'dateTime': '2026-11-27T21:30:00', 'term': 'Chicago'});
    expect(u.toString(), isNot(contains('Friday')), reason: 'nothing from the conversation');
  }, variant: ios);

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
