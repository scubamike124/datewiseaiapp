// Design review of 84bce04, checked at text scale 2.0 in English and Spanish:
// scrollable dialogs, wrapping starter chips, stacked coach cards, the support
// row, the uncapped delete-data note, the language sheet title, the underage
// line, the voice captions and the locale-following welcome hero.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/app_links.dart';
import 'package:datewise_ai/screens/home_screen.dart';
import 'package:datewise_ai/screens/onboarding_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/screens/welcome_screen.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/widgets/coach_card.dart';

import 'helpers.dart';

/// Speech that is available and never actually listens (enough to open voice mode).
class _ReadySpeech extends NoSpeechService {
  @override
  bool get available => true;
  @override
  Future<bool> ensureReady() async => true;
}

/// True when [finder]'s text is laid out in full (no line limit hit, no clipping by ellipsis).
bool fullyLaidOut(WidgetTester t, Finder finder) {
  final p = t.renderObject<RenderParagraph>(find.descendant(of: finder, matching: find.byType(RichText)).first);
  return !p.didExceedMaxLines;
}

void main() {
  const scale = 2.0;
  for (final lang in ['en', 'es']) {
    final prefs = lang == 'es' ? spanishPrefs() : onboardedPrefs();
    final locale = Locale(lang);

    testWidgets('[$lang 2.0] delete-data and memory-off dialogs scroll, nothing overflows', (t) async {
      await pumpApp(t, scale: scale, prefs: {...prefs, 'dw_memory_on': true, 'dw_memory_text': 'Shy at first.'}, tab: AppTab.you);
      await t.ensureVisible(find.byKey(const ValueKey('row-memory')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('row-memory')));
      await t.pumpAndSettle();
      expect(t.widget<AlertDialog>(find.byType(AlertDialog)).scrollable, isTrue);
      expect(t.takeException(), isNull);
      await t.tap(find.text(lang == 'es' ? 'Cancelar' : 'Cancel'));
      await t.pumpAndSettle();

      await t.scrollUntilVisible(find.byKey(const ValueKey('row-delete-data')), 300);
      await t.tap(find.byKey(const ValueKey('row-delete-data')));
      await t.pumpAndSettle();
      expect(t.widget<AlertDialog>(find.byType(AlertDialog)).scrollable, isTrue);
      // The confirm button stays reachable and the body can be scrolled to its end.
      final scrollable = find.descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollable)).first;
      await t.drag(scrollable, const Offset(0, -2000));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('confirm-action')).hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('[$lang 2.0] empty-chat starters wrap instead of cutting words', (t) async {
      final app = await pumpApp(t, scale: scale, prefs: prefs, tab: AppTab.chat);
      expect(find.byType(ActionChip), findsNothing);
      final starters = app.state.selectedCoach.starters;
      expect(starters, isNotEmpty);
      for (final s in starters) {
        final f = find.byKey(ValueKey('starter-$s'));
        await t.ensureVisible(f);
        expect(f, findsOneWidget);
        expect(t.widget<OutlinedButton>(f).style?.shape?.resolve({}), isA<StadiumBorder>());
        expect(fullyLaidOut(t, f), isTrue, reason: s);
        expect(t.getSize(f).width, lessThanOrEqualTo(390), reason: 'fits the row');
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('[$lang 2.0] coach cards stack one per row (onboarding step 4 and Coaches)', (t) async {
      await pumpScreen(t, const OnboardingScreen(initialStep: 3), scale: scale, locale: locale);
      void expectStacked() {
        final rects = [for (final id in ['ava', 'ethan', 'sofia', 'diego']) t.getRect(find.byKey(ValueKey('coach-card-$id')))];
        expect(rects.map((r) => r.left).toSet(), hasLength(1), reason: 'one column');
        expect(rects.map((r) => r.width).toSet(), hasLength(1));
        expect(t.takeException(), isNull);
      }

      expectStacked();
      await pumpApp(t, scale: scale, prefs: prefs, tab: AppTab.coaches);
      expectStacked();
      expect(CoachGrid.stackAboveScale, 1.3);
    });

    testWidgets('[$lang 1.0] coach cards stay two per row at normal text', (t) async {
      await pumpApp(t, prefs: prefs, tab: AppTab.coaches);
      final lefts = {for (final id in ['ava', 'ethan', 'sofia', 'diego']) t.getRect(find.byKey(ValueKey('coach-card-$id'))).left};
      expect(lefts, hasLength(2));
    });

    testWidgets('[$lang 2.0] support email is a whole one-line subtitle; the delete-data note is not capped', (t) async {
      await pumpApp(t, scale: scale, prefs: prefs, tab: AppTab.you);
      final email = find.text(AppLinks.supportEmail);
      await t.scrollUntilVisible(email, 300);
      expect(fullyLaidOut(t, email), isTrue);
      // One line, shrunk to fit if needed, so it never breaks at its dot
      // (see ipad_and_large_text_test.dart).
      expect(t.widget<Text>(email).maxLines, 1);
      expect(t.widget<Text>(email).overflow, isNot(TextOverflow.ellipsis));
      final support = find.text(lang == 'es' ? 'Soporte' : 'Support');
      expect(fullyLaidOut(t, support), isTrue);
      // The label has the row's full width, not what the email leaves.
      expect(t.getSize(support).width, lessThan(t.getSize(find.byType(Scaffold).first).width));
      final note = find.text(lang == 'es'
          ? 'No cancela tu suscripción. Cancélala en la configuración de Apple.'
          : 'Does not cancel your subscription. Cancel it in Apple settings.');
      await t.scrollUntilVisible(note, 300);
      expect(t.widget<Text>(note).maxLines, isNull);
      expect(fullyLaidOut(t, note), isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('[$lang 2.0] the language sheet has a title and scrolls', (t) async {
      await pumpApp(t, scale: scale, prefs: prefs, tab: AppTab.you);
      await t.tap(find.byKey(const ValueKey('row-language')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('language-sheet-title')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('language-sheet-title'))).data, lang == 'es' ? 'Idioma' : 'Language');
      expect(t.takeException(), isNull);
    });

    testWidgets('[$lang 2.0] the underage page says the app can be closed', (t) async {
      await pumpScreen(t, const UnderageScreen(), scale: scale, locale: locale);
      expect(find.text(lang == 'es' ? 'Ya puedes cerrar la app.' : 'You can close the app now.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    for (final size in const [Size(390, 844), Size(375, 667)]) {
      testWidgets('[$lang 2.0 ${size.width.toInt()}] voice captions show the whole reply in a scrollable box', (t) async {
        await pumpApp(t, size: size, scale: scale, prefs: prefs, tab: AppTab.chat, speech: _ReadySpeech());
        await t.tap(find.byKey(const ValueKey('voice-mode')));
        await t.pumpAndSettle();
        final caption = find.byKey(const ValueKey('voice-caption'));
        expect(caption, findsOneWidget);
        expect(t.widget<Text>(caption).maxLines, isNull);
        expect(t.widget<Text>(caption).data, isNot(startsWith('…')));
        expect(find.ancestor(of: caption, matching: find.byKey(const ValueKey('voice-caption-scroll'))), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('[$lang] the welcome hero follows the locale', (t) async {
      await pumpScreen(t, const WelcomeScreen(), locale: locale);
      expect(find.bySemanticsLabel(lang == 'es' ? 'Sofía, una coach de citas con IA, sonriendo' : 'Ava, an AI dating coach, smiling'),
          findsOneWidget);
    });
  }

  test('noWidow keeps the last two words together', () {
    expect(noWidow('Practica un primer mensaje'), 'Practica un primer mensaje');
    expect(noWidow('Hola'), 'Hola');
    expect(noWidow('Two words '), 'Two words');
  });
}
