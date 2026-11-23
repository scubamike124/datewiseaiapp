// iPad 13" layout (1032x1376 points) and the large-text cosmetics from the
// last design review (text scale 2.0): the support email never breaks at its
// dot, the memory-off dialog's buttons stack with one-line labels, and the
// chat header subtitle stays on one line.
//
// The real Inter and Newsreader fonts are loaded, so line breaks match the
// app (the default test font is much wider than Inter).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/app_links.dart';
import 'package:datewise_ai/screens/chat_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/screens/welcome_screen.dart';
import 'package:datewise_ai/widgets/coach_card.dart';
import 'package:datewise_ai/widgets/dw.dart';

import 'helpers.dart';

const ipad13 = Size(1032, 1376);

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File('assets/fonts/$f').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Number of laid-out lines of the paragraph under [finder].
int lineCount(WidgetTester t, Finder finder) {
  final p = t.renderObject<RenderParagraph>(find.descendant(of: finder, matching: find.byType(RichText)).first);
  final len = p.text.toPlainText().length;
  final boxes = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  return boxes.map((b) => b.top.round()).toSet().length;
}

void main() {
  setUpAll(() async {
    await _loadFont('Inter', ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf', 'Inter-Bold.ttf']);
    await _loadFont('Newsreader', ['Newsreader-Regular.ttf', 'Newsreader-Medium.ttf', 'Newsreader-Italic.ttf']);
  });

  group('large text (2.0)', () {
    for (final lang in ['en', 'es']) {
      final prefs = lang == 'es' ? spanishPrefs() : onboardedPrefs();
      for (final size in const [Size(375, 667), Size(390, 844)]) {
        final tag = '[$lang ${size.width.toInt()} 2.0]';

        testWidgets('$tag the support email stays on one line, whole and inside the row', (t) async {
          await pumpApp(t, size: size, scale: 2.0, prefs: prefs, tab: AppTab.you);
          final email = find.text(AppLinks.supportEmail);
          await t.scrollUntilVisible(email, 300);
          expect(find.ancestor(of: email, matching: find.byKey(const ValueKey('row-subtitle-fitted'))), findsOneWidget);
          expect(lineCount(t, email), 1);
          final rect = t.getRect(email);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(t.takeException(), isNull);
        });

        testWidgets('$tag memory-off dialog: buttons stack, labels on one line', (t) async {
          await pumpApp(t, size: size, scale: 2.0, prefs: {...prefs, 'dw_memory_on': true, 'dw_memory_text': 'Shy.'}, tab: AppTab.you);
          await t.tap(find.byKey(const ValueKey('row-memory')));
          await t.pumpAndSettle();
          expect(find.byKey(const ValueKey('confirm-actions-stacked')), findsOneWidget);
          final action = find.byKey(const ValueKey('confirm-action'));
          final cancel = find.byKey(const ValueKey('confirm-cancel'));
          expect(find.descendant(of: action, matching: find.text(lang == 'es' ? 'Desactivar y borrar' : 'Turn off & delete')), findsOneWidget);
          expect(lineCount(t, action), 1);
          expect(lineCount(t, cancel), 1);
          // Action first, then Cancel, each the dialog's full width.
          expect(t.getRect(action).top, lessThan(t.getRect(cancel).top));
          expect(t.getSize(action).width, t.getSize(cancel).width);
          expect(t.takeException(), isNull);
        });

        testWidgets('$tag chat header subtitle is one line with a capped size', (t) async {
          await pumpApp(t, size: size, scale: 2.0, prefs: prefs, tab: AppTab.chat);
          final label = find.byKey(const ValueKey('ai-label'));
          expect(lineCount(t, label), 1);
          final text = t.widget<Text>(label);
          expect(text.maxLines, 1);
          expect(text.overflow, TextOverflow.ellipsis);
          final scaler = MediaQuery.textScalerOf(t.element(label));
          expect(scaler.scale(1), lessThanOrEqualTo(kHeaderSubtitleMaxScale));
          // The full text, with "AI", is what VoiceOver reads.
          expect(text.data, contains(lang == 'es' ? 'IA' : 'AI'));
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('dialogs keep side-by-side buttons at normal text', (t) async {
      await pumpApp(t, scale: 1.0, prefs: {...onboardedPrefs(), 'dw_memory_on': true, 'dw_memory_text': 'Shy.'}, tab: AppTab.you);
      await t.tap(find.byKey(const ValueKey('row-memory')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('confirm-actions-stacked')), findsNothing);
      final action = t.getRect(find.byKey(const ValueKey('confirm-action')));
      final cancel = t.getRect(find.byKey(const ValueKey('confirm-cancel')));
      expect(action.top, cancel.top);
      expect(action.left, greaterThan(cancel.left));
    });
  });

  group('iPad 13" (1032x1376)', () {
    for (final lang in ['en', 'es']) {
      final prefs = lang == 'es' ? spanishPrefs() : onboardedPrefs();
      final locale = Locale(lang);

      testWidgets('[$lang] Coaches: a wide grid with tall portraits, not a phone strip', (t) async {
        await pumpApp(t, size: ipad13, prefs: prefs, tab: AppTab.coaches);
        await t.pumpAndSettle();
        final cards = [for (final id in ['ava', 'ethan', 'sofia', 'diego']) t.getRect(find.byKey(ValueKey('coach-card-$id')))];
        final left = cards.map((r) => r.left).reduce((a, b) => a < b ? a : b);
        final right = cards.map((r) => r.right).reduce((a, b) => a > b ? a : b);
        expect(right - left, greaterThan(kContentMaxWidth));
        expect(right - left, lessThanOrEqualTo(kWideContentMaxWidth));
        expect((left + right) / 2, closeTo(ipad13.width / 2, 1), reason: 'centered');
        // 2x2, every card wider than tall would look stretched: they stay portrait-ish.
        for (final r in cards) {
          expect(r.height, greaterThan(r.width * 0.9));
        }
        expect(t.takeException(), isNull);
      });

      testWidgets('[$lang] Home: wider column and a larger hero', (t) async {
        await pumpApp(t, size: ipad13, prefs: prefs);
        await t.pumpAndSettle();
        final plan = t.getRect(find.byKey(const ValueKey('plan-0')));
        expect(plan.width, greaterThan(kContentMaxWidth - 80));
        expect(plan.width, lessThanOrEqualTo(kWideContentMaxWidth));
        final talk = t.getRect(find.byKey(const ValueKey('home-talk')));
        expect(talk.top, greaterThan(180), reason: 'the hero has room on iPad');
        expect(t.takeException(), isNull);
      });

      testWidgets('[$lang] You and Chat keep a readable column', (t) async {
        await pumpApp(t, size: ipad13, prefs: prefs, tab: AppTab.you);
        await t.pumpAndSettle();
        final row = t.getRect(find.byKey(const ValueKey('row-language')));
        expect(row.width, lessThanOrEqualTo(kContentMaxWidth));
        expect(row.center.dx, closeTo(ipad13.width / 2, 1));

        await t.tap(find.byKey(const ValueKey('tab-chat')).first, warnIfMissed: false);
        await t.pumpAndSettle();
        final field = find.byType(TextField);
        if (field.evaluate().isNotEmpty) {
          expect(t.getSize(field.first).width, lessThanOrEqualTo(kContentMaxWidth));
        }
        expect(t.takeException(), isNull);
      });

      testWidgets('[$lang] Welcome: taller portrait, content in the column', (t) async {
        await pumpScreen(t, const WelcomeScreen(), size: ipad13, locale: locale);
        await t.pumpAndSettle();
        final button = t.getRect(find.byKey(const ValueKey('get-started')));
        expect(button.width, lessThanOrEqualTo(kContentMaxWidth));
        expect(button.top, greaterThan(600), reason: 'the portrait grows on iPad');
        expect(button.bottom, lessThan(ipad13.height), reason: 'the button is still on screen');
        expect(find.byKey(const ValueKey('welcome-hero-side-fade')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('phones: portrait-shaped card photos (1.2 x the card width), no tablet layout', (t) async {
      await pumpApp(t, size: const Size(430, 932), prefs: onboardedPrefs(), tab: AppTab.coaches);
      await t.pumpAndSettle();
      expect(isTabletLayout(t.element(find.byType(HomeShell))), isFalse);
      final card = find.byKey(const ValueKey('coach-card-ava'));
      final photo = find.descendant(of: card, matching: find.byType(AspectRatio)).first;
      // The head, from the top of the hair to the smile, sits above the fade:
      // the photo is taller than wide (it was a fixed 150 pt strip).
      expect(t.getSize(photo).height, closeTo(t.getSize(photo).width * 1.2, 0.5));
      expect(t.getSize(photo).width, greaterThan(t.getSize(card).width - 4), reason: 'full card width');
      expect(t.getSize(photo).height, greaterThan(150));
    });

    testWidgets('iPad: square card photos', (t) async {
      await pumpApp(t, size: ipad13, prefs: onboardedPrefs(), tab: AppTab.coaches);
      await t.pumpAndSettle();
      for (final id in ['ava', 'ethan', 'sofia', 'diego']) {
        final photo = t.getSize(find.byKey(ValueKey('coach-photo-$id')));
        expect(photo.height, closeTo(photo.width, 0.5), reason: id);
        expect(photo.width, greaterThan(300));
      }
    });

    testWidgets('phone landscape: lower card photos (0.8 x the card width)', (t) async {
      await pumpApp(t, size: const Size(844, 390), prefs: onboardedPrefs(), tab: AppTab.coaches);
      await t.pumpAndSettle();
      final photo = t.getSize(find.byKey(const ValueKey('coach-photo-ava')));
      expect(photo.height, closeTo(photo.width * 0.8, 0.5));
      expect(t.takeException(), isNull);
    });

    for (final scale in const [1.4, 2.0]) {
      testWidgets('stacked cards at text scale $scale: a 120 pt photo strip, not a full-width portrait', (t) async {
        await pumpApp(t, size: const Size(375, 667), scale: scale, prefs: onboardedPrefs(), tab: AppTab.coaches);
        await t.pumpAndSettle();
        expect(scale, greaterThan(CoachGrid.stackAboveScale));
        for (final id in ['ava', 'ethan', 'sofia', 'diego']) {
          final photo = find.byKey(ValueKey('coach-photo-$id'));
          await t.scrollUntilVisible(photo, 200);
          expect(t.getSize(photo).height, 120, reason: id);
          final img = t.widget<Image>(find.descendant(of: photo, matching: find.byType(Image)));
          expect(img.alignment, CoachCard.stripAlignment, reason: 'the strip sits on the face, not the hair');
        }
        expect(t.takeException(), isNull);
      });
    }

    for (final scale in const [1.0, 2.0]) {
      testWidgets('375x667 at $scale: the last card\'s button clears the tab bar after scrolling', (t) async {
        await pumpApp(t, size: const Size(375, 667), scale: scale, prefs: onboardedPrefs(), tab: AppTab.coaches);
        await t.pumpAndSettle();
        final buttons = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('chat-'));
        expect(buttons, findsNWidgets(4));
        await t.drag(find.byType(Scrollable).first, const Offset(0, -6000));
        await t.pumpAndSettle();
        final rects = [for (final e in buttons.evaluate()) t.getRect(find.byWidget(e.widget))];
        final last = rects.reduce((a, b) => a.bottom > b.bottom ? a : b);
        final tabBar = t.getRect(find.byType(DwTabBar));
        expect(last.bottom, lessThanOrEqualTo(tabBar.top), reason: 'whole button above the tab bar');
        expect(last.top, greaterThan(0));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('phone welcome hero has no side fade', (t) async {
      await pumpScreen(t, const WelcomeScreen(), size: const Size(430, 932));
      expect(find.byKey(const ValueKey('welcome-hero-side-fade')), findsNothing);
    });
  });
}
