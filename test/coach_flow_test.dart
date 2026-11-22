// The coach experience end to end, on the real screens with the offline coach:
// first-run picker, Spanish and English conversations, switching coach, and
// the layout at iPhone and iPad sizes (a RenderFlex overflow fails the test).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/screens/chat_screen.dart';
import 'package:datewise_ai/services/mock_ai_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/state/app_state.dart';
import 'package:datewise_ai/theme/app_theme.dart';

/// Logical screen sizes (points) of the devices the app must fit.
const phones = {
  'iPhone SE': Size(375, 667),
  'iPhone 15': Size(393, 852),
  'iPhone 15 Pro Max': Size(430, 932),
  'iPad mini': Size(744, 1133),
};

Future<AppState> pumpChat(WidgetTester tester, {Size size = const Size(393, 852), Map<String, Object> prefs = const {}}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final state = AppState(storage: await StorageService.create(), ai: MockAIService());
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(theme: AppTheme.light, home: const ChatScreen()),
    ),
  );
  await tester.pump();
  return state;
}

/// Lets the offline coach finish streaming (22 ms per word).
Future<void> settleReply(WidgetTester tester, AppState state) async {
  for (var i = 0; i < 400 && state.isResponding; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('first run: the coach picker shows the English coaches, then the Spanish ones', (tester) async {
    await pumpChat(tester);
    expect(find.text('Choose your coach'), findsOneWidget);
    expect(find.text('Emily'), findsOneWidget);
    expect(find.text('James'), findsOneWidget);
    expect(find.text('Isabella'), findsNothing);

    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();
    expect(find.text('Isabella'), findsOneWidget);
    expect(find.text('Mateo'), findsOneWidget);
    expect(find.text('Hablar con Mateo'), findsOneWidget);
  });

  testWidgets('choosing Mateo opens a Spanish conversation and he replies in Spanish', (tester) async {
    final state = await pumpChat(tester);
    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hablar con Mateo'));
    await tester.pumpAndSettle();

    expect(state.activeCoach, Coaches.mateo);
    expect(find.text('con Mateo · Español'), findsOneWidget);
    expect(find.text(Coaches.mateo.welcomeTitle), findsOneWidget);
    expect(find.text('Planea una primera cita'), findsOneWidget, reason: 'starters in Spanish');
    expect(find.text('Escríbele a Mateo…'), findsOneWidget, reason: 'message box in Spanish');

    await tester.ensureVisible(find.text('Planea una primera cita'));
    await tester.tap(find.text('Planea una primera cita'));
    await tester.pump();
    await settleReply(tester, state);
    final reply = state.activeThread!.messages.last;
    expect(reply.isUser, isFalse);
    expect(reply.text, contains('lugar público'));
  });

  testWidgets('choosing Emily opens an English conversation; switching to James keeps both apart', (tester) async {
    final state = await pumpChat(tester);
    await tester.tap(find.text('Talk to Emily'));
    await tester.pumpAndSettle();
    expect(find.text('with Emily · English'), findsOneWidget);
    expect(find.text('Rewrite my dating bio'), findsOneWidget);
    expect(find.text('Message Emily…'), findsOneWidget);

    await tester.ensureVisible(find.text('Rewrite my dating bio'));
    await tester.tap(find.text('Rewrite my dating bio'));
    await tester.pump();
    await settleReply(tester, state);
    expect(state.activeThread!.messages.last.isUser, isFalse);
    final emilyThread = state.activeThread!.id;

    // Switch coach from the chat header.
    await tester.tap(find.byKey(const ValueKey('switch-coach')));
    await tester.pumpAndSettle();
    expect(find.text('Choose your coach'), findsOneWidget);
    await tester.tap(find.text('Talk to James'));
    await tester.pumpAndSettle();

    expect(find.text('with James · English'), findsOneWidget);
    expect(state.activeCoach, Coaches.james);
    expect(state.threads.any((t) => t.id == emilyThread && t.coachId == 'emily'), isTrue,
        reason: "Emily's conversation is kept");
  });

  testWidgets('a returning user who already chose a coach goes straight to the chat', (tester) async {
    await pumpChat(tester, prefs: {'dw_coach': 'isabella'});
    expect(find.text('Choose your coach'), findsNothing);
    expect(find.byType(TextField), findsOneWidget, reason: 'the chat composer is shown');
  });

  for (final entry in phones.entries) {
    testWidgets('fits ${entry.key} (${entry.value.width.toInt()}x${entry.value.height.toInt()}): picker and Spanish chat', (tester) async {
      final state = await pumpChat(tester, size: entry.value);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Español'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Hablar con Isabella'));
      await tester.tap(find.text('Hablar con Isabella'));
      await tester.pumpAndSettle();
      expect(find.text('Reescribe mi biografía'), findsOneWidget);
      await tester.ensureVisible(find.text('Mi pareja dejó de escribirme'));
      await tester.tap(find.text('Mi pareja dejó de escribirme'));
      await tester.pump();
      await settleReply(tester, state);
      expect(state.activeThread!.messages.last.text, contains('mensaje ligero'));
      expect(tester.takeException(), isNull, reason: 'no layout overflow on ${entry.key}');
    });
  }

  // Smallest supported phone with large accessibility text: the welcome,
  // starters and composer must fit (they scroll) for every coach.
  for (final coach in Coaches.all) {
    testWidgets('fits 320x568 at text scale 1.3 with ${coach.name}', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpChat(tester, size: const Size(320, 568), prefs: {'dw_coach': coach.id});
      final state = tester.element(find.byType(ChatScreen)).read<AppState>();
      await state.selectCoach(coach.id);
      await tester.pumpAndSettle();
      expect(find.text(coach.welcomeTitle), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow for ${coach.name}');
    });
  }
}
