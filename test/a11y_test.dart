// Accessibility: text contrast of the design tokens, labels on icon-only
// buttons and portraits, 44pt tap targets, Dynamic Type at 2.0 on the main
// screens (English and Spanish), and Reduce Motion.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/screens/paywall_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/theme/app_theme.dart';
import 'package:datewise_ai/widgets/dw.dart';

import 'helpers.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055) * _pow24((v + 0.055) / 1.055);
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

// x^2.4 = x^2 * x^0.4
double _pow24(double x) => _pow(x, 0.4);
double _pow(double x, double e) => x <= 0 ? 0 : _exp(e * _ln(x));
double _ln(double x) {
  // ln via series around 1 after range reduction (x in (0, 1]).
  var k = 0;
  while (x < 0.5) {
    x *= 2;
    k++;
  }
  final y = (x - 1) / (x + 1);
  var sum = 0.0, term = y;
  for (var n = 1; n < 60; n += 2) {
    sum += term / n;
    term *= y * y;
  }
  return 2 * sum - k * 0.6931471805599453;
}

double _exp(double x) {
  var sum = 1.0, term = 1.0;
  for (var n = 1; n < 40; n++) {
    term *= x / n;
    sum += term;
  }
  return sum;
}

/// WCAG contrast ratio of [fg] over [bg] (alpha of [fg] composited on [bg]).
double contrast(Color fg, Color bg) {
  final f = Color.alphaBlend(fg, bg);
  final a = _lum(f), b = _lum(bg);
  final hi = a > b ? a : b, lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('text contrast (WCAG AA, 4.5:1 for body text)', () {
    test('the helper matches known values', () {
      expect(contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(21, 0.01));
      expect(contrast(const Color(0xFF777777), const Color(0xFFFFFFFF)), closeTo(4.48, 0.02));
    });

    // Every text color on every surface it is used on.
    final pairs = <String, (Color, Color)>{
      'text on background': (AppColors.text, AppColors.background),
      'text on surface': (AppColors.text, AppColors.surface),
      'text on surface2 (coach bubble)': (AppColors.text, AppColors.surface2),
      'text on card': (AppColors.text, AppColors.cardDeep),
      'muted on background': (AppColors.textMuted, AppColors.background),
      'muted on surface': (AppColors.textMuted, AppColors.surface),
      'muted on surface2': (AppColors.textMuted, AppColors.surface2),
      'muted on card': (AppColors.textMuted, AppColors.cardDeep),
      'faint (small) on background': (AppColors.faint, AppColors.background),
      'faint (small) on surface': (AppColors.faint, AppColors.surface),
      'faint (small) on surface2 (sheets, dialogs)': (AppColors.faint, AppColors.surface2),
      'gold eyebrow on background': (AppColors.gold, AppColors.background),
      'gold on surface': (AppColors.gold, AppColors.surface),
      'gold ink on gold button': (AppColors.goldInk, AppColors.gold2),
      'rose ink on rose button (top)': (AppColors.roseInk, AppColors.roseTop),
      'rose ink on rose button (middle)': (AppColors.roseInk, Color.lerp(AppColors.roseTop, AppColors.roseBottom, 0.5)!),
      'rose ink on rose button (bottom)': (AppColors.roseInk, AppColors.roseBottom),
      'rose error text on background': (AppColors.rose, AppColors.background),
      'danger on surface': (AppColors.danger, AppColors.surface),
      'user bubble text': (const Color(0xFFF6E6D2), const Color(0xFF3A2A1F)),
      'language pill': (const Color(0xFF2A1A1F), const Color(0xEBFFF8F2)),
      'glass chip text': (AppColors.text, const Color(0x9E120C0E)),
    };
    for (final e in pairs.entries) {
      test(e.key, () {
        final (fg, bg) = e.value;
        // Translucent backgrounds are composited on the page background.
        final solidBg = Color.alphaBlend(bg, AppColors.background);
        expect(contrast(fg, solidBg), greaterThanOrEqualTo(4.5), reason: e.key);
      });
    }
  });

  group('labels and tap targets', () {
    Future<void> checkGuidelines(WidgetTester tester) async {
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    }

    testWidgets('home', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, prefs: onboardedPrefs());
      await checkGuidelines(tester);
      expect(find.bySemanticsLabel('Portrait of Ava, AI coach'), findsWidgets);
      handle.dispose();
    });

    testWidgets('chat', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.chat);
      await tester.tap(find.byKey(const ValueKey('starter-Give me a strong opener')));
      await tester.pump();
      await settleReply(tester, app.state);
      await checkGuidelines(tester);
      expect(find.bySemanticsLabel('Send'), findsOneWidget);
      expect(find.bySemanticsLabel('Conversation options'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Copy Playful reply')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('coaches', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.coaches);
      await checkGuidelines(tester);
      for (final n in ['Ava', 'Ethan', 'Sofía', 'Diego']) {
        expect(find.bySemanticsLabel('Portrait of $n, AI coach'), findsOneWidget, reason: n);
      }
      handle.dispose();
    });

    testWidgets('paywall', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, PaywallScreen(onClose: () {}), entitled: false, prefs: onboardedPrefs());
      await checkGuidelines(tester);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('settings', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.you);
      await checkGuidelines(tester);
      handle.dispose();
    });

    testWidgets('every CircleIconButton has a label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.chat);
      for (final b in tester.widgetList<CircleIconButton>(find.byType(CircleIconButton))) {
        expect(b.tooltip.trim(), isNotEmpty);
      }
      handle.dispose();
    });
  });

  group('Dynamic Type at 2.0 (no overflow, nothing clipped by an exception)', () {
    final cases = <String, Future<void> Function(WidgetTester, Size, Map<String, Object>)>{
      'home': (t, size, prefs) async {
        await pumpApp(t, size: size, scale: 2.0, prefs: prefs);
      },
      'chat': (t, size, prefs) async {
        final app = await pumpApp(t, size: size, scale: 2.0, prefs: prefs, tab: AppTab.chat);
        await t.enterText(find.byKey(const ValueKey('composer')), 'Give me a strong opener');
        await t.tap(find.byKey(const ValueKey('send')));
        await t.pump();
        await settleReply(t, app.state);
      },
      'paywall': (t, size, prefs) async {
        await pumpApp(t, size: size, scale: 2.0, prefs: prefs, entitled: false);
        expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
        await t.scrollUntilVisible(find.byKey(const ValueKey('paywall-restore')), 300);
      },
      'settings': (t, size, prefs) async {
        await pumpApp(t, size: size, scale: 2.0, prefs: prefs, tab: AppTab.you);
        await t.scrollUntilVisible(find.byKey(const ValueKey('row-delete-data')), 300);
      },
      'coaches': (t, size, prefs) async {
        await pumpApp(t, size: size, scale: 2.0, prefs: prefs, tab: AppTab.coaches);
      },
      'progress': (t, size, prefs) async {
        await pumpApp(t, size: size, scale: 2.0, prefs: prefs, tab: AppTab.progress);
      },
    };
    for (final c in cases.entries) {
      for (final lang in ['en', 'es']) {
        for (final size in const [Size(375, 667), Size(390, 844)]) {
          testWidgets('${c.key} ($lang) at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
            await c.value(tester, size, lang == 'es' ? spanishPrefs() : onboardedPrefs());
            await tester.pump(const Duration(milliseconds: 500));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('Reduce Motion', () {
    testWidgets('animations jump instead of animating', (tester) async {
      await pumpApp(tester, prefs: onboardedPrefs());
      final ctx = tester.element(find.byType(HomeShell));
      expect(reduceMotion(ctx), isFalse);
      expect(motion(ctx, const Duration(milliseconds: 300)), const Duration(milliseconds: 300));
    });

    testWidgets('with Reduce Motion on, the speaking glow and plan checks do not animate', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true, reduceMotion: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpApp(tester, prefs: onboardedPrefs());
      final ctx = tester.element(find.byType(HomeShell));
      expect(reduceMotion(ctx), isTrue);
      expect(motion(ctx, const Duration(milliseconds: 300)), Duration.zero);
      for (final a in tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer))) {
        expect(a.duration, Duration.zero);
      }
      // Chat header avatar (the speaking glow).
      await tester.tap(find.byKey(const ValueKey('tab-chat')));
      await tester.pump();
      final avatar = find.descendant(of: find.byType(CoachAvatar), matching: find.byType(AnimatedContainer));
      expect(tester.widgetList<AnimatedContainer>(avatar).every((a) => a.duration == Duration.zero), isTrue);
    });
  });

  testWidgets('the 2.0 checks really render at 2.0', (tester) async {
    await pumpApp(tester, scale: 2.0, prefs: onboardedPrefs());
    final ctx = tester.element(find.byType(HomeShell));
    expect(MediaQuery.textScalerOf(ctx).scale(10), 20);
    expect(RendererBinding.instance.renderViews, isNotEmpty);
  });
}
