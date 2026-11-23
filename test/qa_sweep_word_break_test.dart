// Full-app QA sweep (v2), words breaking mid-word: the Welcome value tiles,
// the Home quick actions, the Progress plan rows and the onboarding goal
// tiles never split a word across lines (iPhone SE and iPhone 15, EN and ES,
// text scale 1.0 and 2.0); the Welcome coach chip stays inside the screen;
// the Welcome footnote and the ES age title break between phrases, never
// inside a word or before a lone period.
//
// The real Inter and Newsreader fonts are loaded, so line breaks match the
// app (the default test font is much wider than Inter).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/screens/onboarding_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/screens/welcome_screen.dart';
import 'package:datewise_ai/widgets/dw.dart';

import 'helpers.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
  }
  await loader.load();
}

final _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _onlyPunct = RegExp(r'^[\s.,;:!?¿¡·…)\]»”"]+$');

/// Problems in the paragraphs under [finder]: a line break between two
/// letters, a line holding only punctuation, or a single word (words are
/// split at breaking spaces only) wider than the paragraph's width.
List<String> wordProblems(WidgetTester t, Finder finder) {
  final out = <String>[];
  for (final e in find.descendant(of: finder, matching: find.byType(RichText), matchRoot: true).evaluate()) {
    final p = e.renderObject;
    if (p is! RenderParagraph || !p.hasSize) continue;
    final s = p.text.toPlainText();
    final lines = <String>[];
    double? prevTop;
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final boxes = p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
      if (boxes.isEmpty) {
        buf.write(s[i]);
        continue;
      }
      final top = boxes.first.top;
      if (prevTop != null && top > prevTop + 1) {
        if (_letter.hasMatch(s[i - 1]) && _letter.hasMatch(s[i])) {
          out.add('"$s" breaks inside a word at "${s.substring(0, i)}|${s.substring(i)}"');
        }
        lines.add(buf.toString());
        buf.clear();
      }
      buf.write(s[i]);
      prevTop = top;
    }
    lines.add(buf.toString());
    for (final line in lines) {
      if (_onlyPunct.hasMatch(line)) out.add('"$s" has a line with only "$line"');
    }
    // Every word's own width, with the paragraph's style and text scale.
    final style = (p.text as TextSpan).style ?? const TextStyle();
    for (final word in s.split(RegExp(r'[ \n\t]+'))) {
      if (word.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
        textScaler: p.textScaler,
      )..layout();
      if (tp.width > p.size.width + 0.5) {
        out.add('"$word" (${tp.width.toStringAsFixed(1)}) is wider than its box (${p.size.width.toStringAsFixed(1)}) in "$s"');
      }
    }
  }
  return out;
}

/// The lines [finder]'s first paragraph is laid out in, as shown.
List<String> paragraphLines(WidgetTester t, Finder finder) {
  final p = t.renderObject<RenderParagraph>(find.descendant(of: finder, matching: find.byType(RichText), matchRoot: true).first);
  final s = p.text.toPlainText();
  final lines = <String>[];
  final buf = StringBuffer();
  double? prevTop;
  for (var i = 0; i < s.length; i++) {
    final boxes = p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isNotEmpty) {
      if (prevTop != null && boxes.first.top > prevTop + 1) {
        lines.add(buf.toString().trim());
        buf.clear();
      }
      prevTop = boxes.first.top;
    }
    buf.write(s[i]);
  }
  lines.add(buf.toString().trim());
  return lines;
}

void main() {
  setUpAll(() async {
    await _loadFont('Inter', ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf', 'Inter-Bold.ttf']);
    await _loadFont('Newsreader', ['Newsreader-Regular.ttf', 'Newsreader-Medium.ttf', 'Newsreader-Italic.ttf']);
  });

  const se = Size(375, 667);
  const i15 = Size(390, 844);

  for (final lang in ['en', 'es']) {
    final locale = Locale(lang);
    final prefs = lang == 'es' ? spanishPrefs() : onboardedPrefs();
    for (final size in const [se, i15]) {
      for (final scale in const [1.0, 2.0]) {
        final tag = '[$lang ${size.width.toInt()} ${scale}x]';

        testWidgets('$tag Welcome: value tiles, footnote and coach chip', (t) async {
          await pumpScreen(t, const WelcomeScreen(), size: size, scale: scale, locale: locale);
          await t.pumpAndSettle();
          for (var i = 0; i < 3; i++) {
            final tile = find.byKey(ValueKey('welcome-value-$i'));
            await t.ensureVisible(tile);
            await t.pumpAndSettle();
            expect(wordProblems(t, tile), isEmpty);
          }
          final foot = find.byKey(const ValueKey('welcome-footnote'));
          await t.ensureVisible(foot);
          await t.pumpAndSettle();
          expect(wordProblems(t, foot), isEmpty);
          // Above 1.3 the tiles stack, one per row.
          final a = t.getRect(find.byKey(const ValueKey('welcome-value-0')));
          final b = t.getRect(find.byKey(const ValueKey('welcome-value-1')));
          expect(b.top > a.bottom - 1, scale > 1.3, reason: 'stacked only at large text');

          await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
          await t.pumpAndSettle();
          final chip = find.byKey(const ValueKey('welcome-chip'));
          expect(t.getRect(chip).right, lessThanOrEqualTo(size.width - 19), reason: 'the chip is not cut off');
          expect(wordProblems(t, chip).where((p) => p.contains('wider than')), isEmpty);
          expect(t.takeException(), isNull);
        });

        testWidgets('$tag Home: quick-action tiles', (t) async {
          await pumpApp(t, size: size, scale: scale, prefs: prefs);
          await t.pumpAndSettle();
          for (final id in ['practice', 'profile', 'date', 'reply']) {
            final tile = find.byKey(ValueKey('tile-$id'));
            await t.ensureVisible(tile);
            await t.pumpAndSettle();
            expect(wordProblems(t, tile), isEmpty, reason: id);
          }
          final a = t.getRect(find.byKey(const ValueKey('tile-practice')));
          final b = t.getRect(find.byKey(const ValueKey('tile-profile')));
          expect(b.top > a.bottom - 1, scale > 1.3, reason: 'one column only at large text');
          expect(t.takeException(), isNull);
        });

        testWidgets('$tag Progress: plan rows', (t) async {
          await pumpApp(t, size: size, scale: scale, prefs: prefs, tab: AppTab.progress);
          await t.pumpAndSettle();
          for (var i = 0; i < 3; i++) {
            final row = find.byKey(ValueKey('progress-plan-$i'));
            await t.ensureVisible(row);
            await t.pumpAndSettle();
            expect(wordProblems(t, row), isEmpty);
          }
          expect(t.takeException(), isNull);
        });

        testWidgets('$tag Onboarding: goal tiles and the age title', (t) async {
          await pumpScreen(t, const OnboardingScreen(), size: size, scale: scale, locale: locale);
          await t.pumpAndSettle();
          for (final g in ['conversations', 'profile', 'dates', 'confidence', 'relationship']) {
            final tile = find.byKey(ValueKey('goal-$g'));
            await t.ensureVisible(tile);
            await t.pumpAndSettle();
            expect(wordProblems(t, tile), isEmpty, reason: g);
          }
          await t.pumpWidget(const SizedBox());
          await pumpScreen(t, const OnboardingScreen(initialStep: 2), size: size, scale: scale, locale: locale);
          await t.pumpAndSettle();
          expect(wordProblems(t, find.byType(LargeTitle)), isEmpty);
          expect(t.takeException(), isNull);
        });
      }
    }
  }

  // ES under-18 copy on iPhone SE and iPhone 15, at 1.0 and 2.0: the
  // adults-only title never leaves "." alone on a line, and the dialog's
  // "Sí, tengo menos de 18" never leaves "18" alone.
  for (final size in const [se, i15]) {
    for (final scale in const [1.0, 2.0]) {
      final tag = '[es ${size.width.toInt()} ${scale}x]';

      testWidgets('$tag the adults-only title breaks between words only', (t) async {
        await pumpApp(t, size: size, scale: scale, prefs: {...spanishPrefs(), 'dw_underage': true});
        await t.pumpAndSettle();
        final title = find.descendant(of: find.byKey(const ValueKey('underage')), matching: find.byType(LargeTitle));
        expect(title, findsOneWidget);
        final text = find.descendant(of: title, matching: find.byType(Text)).first;
        expect(t.widget<Text>(text).data, startsWith('Lo sentimos'));
        final lines = paragraphLines(t, text);
        expect(lines.where((l) => !_letter.hasMatch(l)), isEmpty, reason: '$lines');
        expect(wordProblems(t, text), isEmpty);
      });

      testWidgets('$tag "Sí, tengo menos de 18" keeps "de 18" together', (t) async {
        await pumpScreen(t, const OnboardingScreen(initialStep: 2),
            size: size, scale: scale, prefs: spanishPrefs(), locale: const Locale('es'));
        await t.pumpAndSettle();
        final under = find.byKey(const ValueKey('age-under'));
        await t.ensureVisible(under);
        await t.pumpAndSettle();
        await t.tap(under);
        await t.pumpAndSettle();
        final action = find.byKey(const ValueKey('confirm-action'));
        final lines = paragraphLines(t, find.descendant(of: action, matching: find.byType(Text)));
        expect(lines.where((l) => RegExp(r'^\d+$').hasMatch(l)), isEmpty, reason: '$lines');
        expect(lines.last, endsWith('de\u00a018'), reason: '$lines');
      });
    }
  }
}
