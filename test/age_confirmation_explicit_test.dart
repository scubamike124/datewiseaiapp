// Onboarding's 18+ step needs an explicit choice: "I am 18 or older" starts
// unselected, Continue stays disabled until the user taps it, tapping it
// again unselects it, and onboarding cannot complete without it (in English
// and Spanish). Nothing about the age is pre-selected or implied.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/widgets/dw.dart';

import 'helpers.dart';

Future<void> _toAgeStep(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const ValueKey('get-started')));
  await t.tap(find.byKey(const ValueKey('get-started')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('goal-profile')));
  await t.pump();
  for (var i = 0; i < 2; i++) {
    final next = find.byKey(const ValueKey('onboarding-continue'));
    await t.ensureVisible(next);
    await t.tap(next);
    await t.pumpAndSettle();
  }
}

VoidCallback? _continue(WidgetTester t) => t.widget<DwButton>(find.byKey(const ValueKey('onboarding-continue'))).onPressed;

/// What the tile reports to VoiceOver as selected, and its check icon.
bool _selected(WidgetTester t) {
  final tile = find.byKey(const ValueKey('age-confirm'));
  final sem = t.widget<Semantics>(find.descendant(of: tile, matching: find.byType(Semantics)).first);
  final checked = find.descendant(of: tile, matching: find.byIcon(Icons.check_circle_rounded)).evaluate().isNotEmpty;
  expect(sem.properties.selected, checked, reason: 'semantics and icon agree');
  return checked;
}

void main() {
  for (final (lang, confirm) in [('en', 'I am 18 or older'), ('es', 'Tengo 18 años o más')]) {
    testWidgets('[$lang] "$confirm" starts unselected; Continue needs the explicit tap', (t) async {
      if (lang == 'es') {
        t.platformDispatcher.localesTestValue = const [Locale('es', 'MX')];
        addTearDown(t.platformDispatcher.clearLocalesTestValue);
      }
      await pumpApp(t, entitled: false);
      await _toAgeStep(t);
      expect(find.text(confirm), findsOneWidget);
      expect(_selected(t), isFalse, reason: 'not pre-selected');
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
      expect(_continue(t), isNull, reason: 'Continue is disabled until the user confirms');

      // Tapping Continue does nothing: still on the age step.
      await t.tap(find.byKey(const ValueKey('onboarding-continue')), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('age-confirm')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('age-confirm')));
      await t.pump();
      expect(_selected(t), isTrue);
      expect(_continue(t), isNotNull);

      // Tapping it again withdraws the confirmation.
      await t.tap(find.byKey(const ValueKey('age-confirm')));
      await t.pump();
      expect(_selected(t), isFalse);
      expect(_continue(t), isNull);
    });
  }

  test('onboarding cannot complete without the explicit 18+ confirmation', () async {
    final app = await makeState(entitled: false);
    final ok = await app.state.completeOnboarding(
      goals: const [CoachingGoal.profile],
      language: CoachLanguage.en,
      coachId: 'ava',
      adultConfirmed: false,
    );
    expect(ok, isFalse);
    expect(app.state.onboarded, isFalse);
  });
}
