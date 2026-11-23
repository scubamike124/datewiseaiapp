// Full-app QA sweep (v2), onboarding: "I am under 18" asks for confirmation
// before it locks the app for good (Cancel changes nothing), and the system
// back gesture goes to the previous step instead of leaving onboarding.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> _toStep(WidgetTester t, int step) async {
  await t.ensureVisible(find.byKey(const ValueKey('get-started')));
  await t.tap(find.byKey(const ValueKey('get-started')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('goal-profile')));
  await t.pump();
  for (var i = 0; i < step; i++) {
    final next = find.byKey(const ValueKey('onboarding-continue'));
    await t.ensureVisible(next);
    await t.tap(next);
    await t.pumpAndSettle();
  }
}

void main() {
  for (final (lang, title, action) in [
    ('en', 'Are you under 18?', "Yes, I'm under 18"),
    ('es', '¿Tienes menos de 18 años?', 'Sí, tengo menos de\u00a018'),
  ]) {
    testWidgets('[$lang] "I am under 18" asks first; Cancel keeps onboarding, confirming locks the app', (t) async {
      if (lang == 'es') {
        t.platformDispatcher.localesTestValue = const [Locale('es', 'MX')];
        addTearDown(t.platformDispatcher.clearLocalesTestValue);
      }
      final app = await pumpApp(t, entitled: false);
      await _toStep(t, 2);
      await t.tap(find.byKey(const ValueKey('age-under')));
      await t.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text(action), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('confirm-cancel')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('underage')), findsNothing);
      expect(find.byKey(const ValueKey('age-confirm')), findsOneWidget, reason: 'still on the 18+ step');
      expect(app.state.underageBlocked, isFalse);
      expect(app.storage.underage, isFalse, reason: 'nothing saved on Cancel');

      await t.tap(find.byKey(const ValueKey('age-under')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('confirm-action')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('underage')), findsOneWidget);
      expect(app.storage.underage, isTrue);
    });
  }

  testWidgets('system back goes to the previous step (choices kept); on step 1 it leaves onboarding', (t) async {
    await pumpApp(t, entitled: false);
    await _toStep(t, 2);
    expect(find.byKey(const ValueKey('onboarding-2')), findsOneWidget);

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-1')), findsOneWidget);

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-0')), findsOneWidget);
    // The goal chosen earlier is still selected (Continue is enabled).
    final cont = find.byKey(const ValueKey('onboarding-continue'));
    expect((t.widget(cont) as dynamic).onPressed, isNotNull);

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('welcome')), findsOneWidget);
  });
}
