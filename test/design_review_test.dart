// Design-review fixes: chat header, typographic quotes, language badges,
// Progress stats, the 18+ step and the paywall link row.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/screens/coaches_screen.dart';
import 'package:datewise_ai/screens/onboarding_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/widgets/coach_text.dart';
import 'package:datewise_ai/widgets/dw.dart';

import 'helpers.dart';

void main() {
  test('coach replies use curly quotes and apostrophes, like the suggestion chips', () {
    expect(CoachText.smartQuotes('Skip "hey". Try: "What\'s the best trail you\'ve done?"'),
        'Skip “hey”. Try: “What’s the best trail you’ve done?”');
    expect(CoachText.smartQuotes('**"Bold quote"**'), '**“Bold quote”**');
    expect(CoachText.smartQuotes('ejemplo: "¿cuál es tu ruta?"'), 'ejemplo: “¿cuál es tu ruta?”');
  });

  testWidgets('the chat header is opaque with a hairline', (tester) async {
    await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.chat);
    await tester.pumpAndSettle();
    final box = tester.widget<DecoratedBox>(find.byKey(const ValueKey('chat-header')));
    final d = box.decoration as BoxDecoration;
    expect(d.color!.a, 1.0);
    expect((d.border as Border).bottom.width, greaterThan(0));
  });

  testWidgets('language badges read English / Español in both UI languages', (tester) async {
    await pumpScreen(tester, const CoachesScreen(), size: const Size(390, 1400));
    expect(find.text('English'), findsNWidgets(2));
    expect(find.text('Español'), findsNWidgets(2));
    expect(find.text('Spanish'), findsNothing);
  });

  testWidgets('Progress shows four distinct stats', (tester) async {
    await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.progress);
    for (final k in ['stat-conversations', 'stat-streak', 'stat-days', 'stat-plan']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    expect(find.textContaining('in total'), findsNothing);
  });

  testWidgets('18+ step: Continue and a real secondary button for under 18', (tester) async {
    await pumpScreen(tester, const OnboardingScreen(initialStep: 2));
    expect(find.byKey(const ValueKey('age-under')), findsOneWidget);
    expect(tester.widget<DwButton>(find.byKey(const ValueKey('age-under'))).style, DwButtonStyle.ghost);
    final cont = tester.getTopLeft(find.byKey(const ValueKey('onboarding-continue')));
    final under = tester.getTopLeft(find.byKey(const ValueKey('age-under')));
    expect(cont.dy, lessThan(under.dy));
    expect(cont.dy, lessThan(500), reason: 'kept with the question, not at the bottom of an empty screen');
  });

  testWidgets('paywall: Restore, Terms and Privacy sit above the disclosure', (tester) async {
    await pumpApp(tester, prefs: onboardedPrefs(), store: FakeStoreService());
    final links = tester.getTopLeft(find.byKey(const ValueKey('paywall-restore')));
    final disclosure = tester.getTopLeft(find.byKey(const ValueKey('paywall-disclosure')));
    expect(links.dy, lessThan(disclosure.dy));
  });
}
