// Large text (l10n QA): pumps key screens at text scale 2.0 in English and
// Spanish. Fails on overflow exceptions and on text that ignores the text
// scale (coach replies used plain RichText, L10N D1; the DateWise wordmark
// is a logo and keeps its size on purpose), and checks that the Progress
// stat tiles stack instead of squeezing two per row. Words broken across
// lines are only printed for review: the test font's square glyphs are far
// wider than the real fonts, so it over-reports them. Run with DW_AUDIT=1
// to print them.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/content/legal_text.dart';
import 'package:datewise_ai/screens/legal_screen.dart';
import 'package:datewise_ai/screens/onboarding_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/screens/welcome_screen.dart';

import 'helpers.dart';

final _letter = RegExp(r'[A-Za-zÁÉÍÓÚáéíóúÑñü]');

/// Texts on screen where a line break falls between two letters.
List<String> brokenWords(WidgetTester tester) {
  final out = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject;
    if (p is! RenderParagraph || !p.hasSize || !p.attached) continue;
    final s = p.text.toPlainText();
    if (s.length > 400) continue;
    double? prevTop;
    for (var i = 0; i < s.length; i++) {
      final boxes = p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
      if (boxes.isEmpty) continue;
      final top = boxes.first.top;
      if (prevTop != null && top > prevTop + 1 && i > 0 && _letter.hasMatch(s[i - 1]) && _letter.hasMatch(s[i])) {
        out.add('"${s.replaceAll('\n', ' ')}" broken at "${s.substring(0, i)}|${s.substring(i)}"');
        break;
      }
      prevTop = top;
    }
  }
  return out;
}

/// RichText widgets that ignore the ambient text scale (the wordmark logo
/// excepted).
List<String> unscaled(WidgetTester tester) => [
      for (final w in tester.widgetList<RichText>(find.byType(RichText)))
        if (w.textScaler == TextScaler.noScaling &&
            w.text.toPlainText().trim().length > 3 &&
            w.text.toPlainText() != 'DateWise')
          w.text.toPlainText().replaceAll('\n', ' ').substring(0, w.text.toPlainText().length.clamp(0, 50)),
    ];

Future<void> report(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 500));
  final ex = tester.takeException();
  final broken = brokenWords(tester);
  final noScale = unscaled(tester);
  if (broken.isNotEmpty && Platform.environment['DW_AUDIT'] == '1') {
    // ignore: avoid_print
    print('AUDIT $name | BROKEN WORDS (review): ${broken.join(' || ')}');
  }
  expect(ex, isNull, reason: name);
  expect(noScale.toSet(), isEmpty, reason: '$name: text that ignores the text scale');
}

void main() {
  const scale = 2.0;
  for (final size in const [Size(375, 667), Size(390, 844)]) {
    final sz = '${size.width.toInt()}x${size.height.toInt()}';
    for (final lang in ['en', 'es']) {
      final locale = Locale(lang);
      final prefs = lang == 'es' ? spanishPrefs() : onboardedPrefs();

      testWidgets('welcome $lang $sz', (t) async {
        await pumpScreen(t, const WelcomeScreen(), size: size, scale: scale, locale: locale);
        await report(t, 'welcome $lang $sz');
      });
      for (var step = 0; step < 4; step++) {
        testWidgets('onboarding ${step + 1} $lang $sz', (t) async {
          await pumpScreen(t, OnboardingScreen(initialStep: step), size: size, scale: scale, locale: locale);
          await report(t, 'onboarding ${step + 1} $lang $sz');
        });
      }
      testWidgets('underage $lang $sz', (t) async {
        await pumpScreen(t, const OnboardingScreen(initialStep: 2), size: size, scale: scale, locale: locale);
        await t.ensureVisible(find.byKey(const ValueKey('age-under')));
        await t.pumpAndSettle(const Duration(milliseconds: 100));
        await t.tap(find.byKey(const ValueKey('age-under')));
        await t.pumpAndSettle(const Duration(milliseconds: 100));
        await report(t, 'underage confirm $lang $sz');
        await t.tap(find.byKey(const ValueKey('confirm-action')));
        await t.pumpAndSettle(const Duration(milliseconds: 100));
        final cont = find.byKey(const ValueKey('onboarding-continue'));
        if (cont.evaluate().isNotEmpty) {
          await t.ensureVisible(cont);
          await t.tap(cont);
          await t.pumpAndSettle(const Duration(milliseconds: 100));
        }
        await report(t, 'underage $lang $sz');
      });
      testWidgets('paywall $lang $sz', (t) async {
        await pumpApp(t, size: size, scale: scale, prefs: prefs, entitled: false);
        await report(t, 'paywall $lang $sz');
      });
      testWidgets('home $lang $sz', (t) async {
        await pumpApp(t, size: size, scale: scale, prefs: prefs);
        await report(t, 'home $lang $sz');
      });
      testWidgets('coaches $lang $sz', (t) async {
        await pumpApp(t, size: size, scale: scale, prefs: prefs, tab: AppTab.coaches);
        await report(t, 'coaches $lang $sz');
      });
      testWidgets('chat reply $lang $sz', (t) async {
        final app = await pumpApp(t, size: size, scale: scale, prefs: prefs, tab: AppTab.chat);
        await t.enterText(find.byKey(const ValueKey('composer')), lang == 'es' ? 'Dame un buen primer mensaje' : 'Give me a strong opener');
        await t.tap(find.byKey(const ValueKey('send')));
        await t.pump();
        await settleReply(t, app.state);
        await report(t, 'chat reply $lang $sz');
      });
      testWidgets('progress $lang $sz', (t) async {
        await pumpApp(t, size: size, scale: scale, prefs: prefs, tab: AppTab.progress);
        await report(t, 'progress $lang $sz');
        // Above 1.3 the stat tiles stack: one per row, full width.
        final a = t.getRect(find.byKey(const ValueKey('stat-conversations')));
        final b = t.getRect(find.byKey(const ValueKey('stat-streak')));
        expect(b.left, a.left, reason: 'stacked, not side by side');
        expect(b.top, greaterThan(a.bottom - 1));
      });
      testWidgets('settings $lang $sz', (t) async {
        await pumpApp(t, size: size, scale: scale, prefs: prefs, tab: AppTab.you);
        await report(t, 'settings top $lang $sz');
        await t.scrollUntilVisible(find.byKey(const ValueKey('row-delete-data')), 300);
        await report(t, 'settings bottom $lang $sz');
        await t.tap(find.byKey(const ValueKey('row-delete-data')));
        await t.pumpAndSettle(const Duration(milliseconds: 100));
        await report(t, 'delete-data dialog $lang $sz');
      });
      testWidgets('memory sheet $lang $sz', (t) async {
        await pumpApp(t, size: size, scale: scale, prefs: prefs, tab: AppTab.you);
        await t.tap(find.byKey(const ValueKey('row-memory-edit')));
        await t.pumpAndSettle(const Duration(milliseconds: 100));
        await report(t, 'memory sheet $lang $sz');
      });
      testWidgets('language sheet $lang $sz', (t) async {
        await pumpApp(t, size: size, scale: scale, prefs: prefs, tab: AppTab.you);
        await t.tap(find.byKey(const ValueKey('row-language')));
        await t.pumpAndSettle(const Duration(milliseconds: 100));
        await report(t, 'language sheet $lang $sz');
      });
      testWidgets('legal $lang $sz', (t) async {
        await pumpScreen(t, const LegalScreen.doc(LegalDoc.terms), size: size, scale: scale, locale: locale);
        expect(kTermsOfService, isNotEmpty);
        await report(t, 'legal terms $lang $sz');
      });
    }
  }
}
