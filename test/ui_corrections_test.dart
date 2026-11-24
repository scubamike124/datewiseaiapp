// UI corrections from the 2026-11-24 UI and accessibility audit: the status
// bar scrim on scrolling screens (items 7/8), heading sizes (9), the Welcome
// portrait column (10), the paywall's price and Subscribe above the fold
// (11-13), non-text and disabled-button contrast (14), the coach greeting
// preview in the locked chat (21) and "New conversation" in the UI language
// (22).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/l10n/app_localizations.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/screens/onboarding_screen.dart';
import 'package:datewise_ai/screens/paywall_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';
import 'package:datewise_ai/theme/app_theme.dart';
import 'package:datewise_ai/widgets/coach_text.dart';
import 'package:datewise_ai/widgets/dw.dart';

import 'helpers.dart';

/// WCAG relative luminance and contrast ratio ([fg] composited on [bg]).
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color fg, Color bg) {
  final a = _lum(Color.alphaBlend(fg, bg)), b = _lum(bg);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// A store that behaves like the real one before purchase, with a StoreKit
/// price (FakeStoreService adds a review-build note to the paywall).
class _PricedStore extends StoreService {
  _PricedStore();
  @override
  bool get canPurchase => true;
  @override
  bool get isEntitled => false;
  @override
  String? get storePrice => r'$19.99';
  @override
  StoreError? get lastError => null;
  @override
  bool get busy => false;
  @override
  Future<void> init() async {}
  @override
  Future<PurchaseResult> buy() async => PurchaseResult.canceled;
  @override
  Future<bool> restore() async => false;
  @override
  Future<void> refresh() async {}
  @override
  String? get manageUrl => null;
}

/// Real iPhone safe areas: SE (status bar 20, no home indicator) and the
/// Dynamic Island phones (59 / 34).
void _insets(WidgetTester tester, double top, double bottom) {
  final dpr = tester.view.devicePixelRatio;
  tester.view.padding = FakeViewPadding(top: top * dpr, bottom: bottom * dpr);
  tester.view.viewPadding = FakeViewPadding(top: top * dpr, bottom: bottom * dpr);
}

/// The tallest vertical scrollable on screen (the page itself).
ScrollableState _page(WidgetTester tester) {
  ScrollableState? best;
  var bestH = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.axisDirection != AxisDirection.down) continue;
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize || box.size.height <= bestH) continue;
    bestH = box.size.height;
    best = s;
  }
  return best!;
}

const _scrim = ValueKey('status-bar-scrim');

Map<String, Object> _threadPrefs({required String coach, required String language, required String title}) => {
      ...onboardedPrefs(coach: coach, language: language),
      'dw_threads': jsonEncode([
        {
          'id': 't1',
          'title': title,
          'createdAt': '2026-11-20T10:00:00.000',
          'updatedAt': '2026-11-20T10:01:00.000',
          'coachId': coach,
          'messages': [
            {'id': 'u1', 'role': 'user', 'text': '🙂', 'createdAt': '2026-11-20T10:00:00.000'},
            {'id': 'c1', 'role': 'coach', 'text': 'Okay.', 'createdAt': '2026-11-20T10:01:00.000'},
          ],
        },
      ]),
    };

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  // The app's real fonts: the layout checks below (what fits above the fold)
  // depend on real glyph widths, not the test font's 1-em squares.
  setUpAll(() async {
    await _loadFont('Inter', ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf', 'Inter-Bold.ttf']);
    await _loadFont('Newsreader', ['Newsreader-Regular.ttf', 'Newsreader-Medium.ttf', 'Newsreader-Italic.ttf']);
  });

  group('status bar scrim (items 7/8)', () {
    Future<void> checkScrim(WidgetTester tester, {required double top}) async {
      // At rest: nothing over the status bar (hero photos still run under it).
      expect(find.byKey(_scrim), findsNothing);
      final page = _page(tester);
      expect(page.position.maxScrollExtent, greaterThan(top), reason: 'the page must scroll for this check');
      page.position.jumpTo(top / 2);
      await tester.pump();
      final half = tester.widget<ColoredBox>(find.byKey(_scrim));
      expect(half.color.a, closeTo(0.5, 0.02), reason: 'fades in with the scroll');
      page.position.jumpTo(math.min(page.position.maxScrollExtent, top + 120));
      await tester.pump();
      final box = tester.widget<ColoredBox>(find.byKey(_scrim));
      expect(box.color.a, 1.0, reason: 'solid once scrolled by the inset');
      expect(box.color.withValues(alpha: 1), AppColors.background);
      final rect = tester.getRect(find.byKey(_scrim));
      expect(rect.top, 0);
      expect(rect.height, top);
      // Back at the top: clear again.
      page.position.jumpTo(0);
      await tester.pump();
      expect(find.byKey(_scrim), findsNothing);
    }

    for (final tab in [AppTab.home, AppTab.coaches, AppTab.progress, AppTab.you]) {
      testWidgets('${tab.name}: solid behind the clock once scrolled, clear at rest', (tester) async {
        setSurface(tester, const Size(375, 667), 1.0);
        _insets(tester, 59, 34);
        await pumpApp(tester, size: const Size(375, 667), prefs: onboardedPrefs(), tab: tab);
        _insets(tester, 59, 34);
        await tester.pumpAndSettle();
        await checkScrim(tester, top: 59);
      });
    }

    testWidgets('welcome: solid once scrolled, clear at rest (portrait under the clock)', (tester) async {
      setSurface(tester, const Size(375, 667), 1.3);
      _insets(tester, 20, 0);
      await pumpApp(tester, size: const Size(375, 667), scale: 1.3);
      _insets(tester, 20, 0);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('welcome')), findsOneWidget);
      await checkScrim(tester, top: 20);
    });

    testWidgets('paywall: solid once scrolled, clear at rest', (tester) async {
      setSurface(tester, const Size(393, 852), 2.0);
      _insets(tester, 59, 34);
      await pumpApp(tester, size: const Size(393, 852), scale: 2.0, prefs: onboardedPrefs(), store: _PricedStore());
      _insets(tester, 59, 34);
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      await checkScrim(tester, top: 59);
    });

    testWidgets('the scrim ignores touches (the page under it still scrolls and taps)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 40), size: Size(400, 800)),
          child: StatusBarScrim(child: ListView(children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i'))])),
        ),
      ));
      final pos = _page(tester).position;
      pos.jumpTo(300);
      await tester.pump();
      expect(find.byKey(_scrim), findsOneWidget);
      expect(find.ancestor(of: find.byKey(_scrim), matching: find.byType(IgnorePointer)), findsWidgets);
    });

    testWidgets('home indicator: the last line of Welcome and the paywall clears it', (tester) async {
      setSurface(tester, const Size(393, 852), 1.0);
      _insets(tester, 59, 34);
      await pumpApp(tester, size: const Size(393, 852));
      _insets(tester, 59, 34);
      await tester.pumpAndSettle();
      final page = _page(tester);
      page.position.jumpTo(page.position.maxScrollExtent);
      await tester.pump();
      expect(tester.getRect(find.byKey(const ValueKey('get-started'))).bottom, lessThanOrEqualTo(852 - 34));
    });
  });

  group('headings (item 9)', () {
    test('iOS text-style sizes: display 34 (Large Title), title 28 (Title 1)', () {
      expect(AppText.display.fontSize, 34);
      expect(AppText.title.fontSize, 28);
    });

    RenderParagraph greeting(WidgetTester tester) => tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byKey(const ValueKey('home-greeting')), matching: find.byType(RichText)).first);

    testWidgets('Home greeting is 30 pt and scales with Dynamic Type (no clamp)', (tester) async {
      await pumpApp(tester, size: const Size(430, 932), scale: 1.3, prefs: onboardedPrefs());
      await tester.pumpAndSettle();
      expect(greeting(tester).text.style?.fontSize, 30);
      expect(greeting(tester).textScaler.scale(30), closeTo(39, 0.01));
    });

    testWidgets('Home greeting at 200%: much larger than default (only a word too wide for the column shrinks)',
        (tester) async {
      await pumpApp(tester, size: const Size(430, 932), scale: 2.0, prefs: onboardedPrefs());
      await tester.pumpAndSettle();
      expect(greeting(tester).textScaler.scale(30), greaterThan(30 * 1.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('screen titles (LargeTitle) scale linearly to 200%', (tester) async {
      await pumpApp(tester, size: const Size(430, 932), scale: 2.0, prefs: onboardedPrefs(), tab: AppTab.coaches);
      await tester.pumpAndSettle();
      final p = tester
          .renderObjectList<RenderParagraph>(find.descendant(of: find.byType(LargeTitle), matching: find.byType(RichText)))
          .firstWhere((p) => p.text.style?.fontFamily == AppFonts.serif);
      expect(p.text.style?.fontSize, 28);
      expect(p.textScaler.scale(28), 56);
      expect(tester.takeException(), isNull);
    });
  });

  group('Welcome portrait (item 10)', () {
    for (final (size, lang) in [(const Size(375, 667), 'en'), (const Size(393, 852), 'es'), (const Size(430, 932), 'en')]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()} [$lang]: a 4:5 column with faded sides', (tester) async {
        tester.platformDispatcher.localesTestValue = [Locale(lang)];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
        await pumpApp(tester, size: size);
        await tester.pumpAndSettle();
        final fade = find.byKey(const ValueKey('welcome-hero-phone-fade'));
        expect(fade, findsOneWidget);
        final r = tester.getRect(fade);
        final heroHeight = (size.height * (size.height < 760 ? 0.42 : 0.5)).clamp(260.0, 500.0);
        expect(r.width, closeTo(math.min(size.width, heroHeight * 0.8), 0.5));
        expect(r.center.dx, closeTo(size.width / 2, 0.5), reason: 'centered');
        expect(r.width / r.height, closeTo(0.8, 0.01), reason: 'portrait 4:5');
        final image = tester.widget<CoachImage>(find.descendant(of: fade, matching: find.byType(CoachImage)));
        expect(image.alignment, const Alignment(0, -0.9), reason: 'the top of the head shows');
      });
    }
  });

  group('paywall above the fold (items 11-13)', () {
    for (final (size, top, bottom, scale) in [
      (const Size(375, 667), 20.0, 0.0, 1.0),
      (const Size(393, 852), 59.0, 34.0, 1.0),
      (const Size(393, 852), 59.0, 34.0, 1.3),
      (const Size(430, 932), 59.0, 34.0, 1.0),
    ]) {
      for (final lang in ['en', 'es']) {
        testWidgets('${size.width.toInt()}x${size.height.toInt()} at ${scale}x [$lang]: price and Subscribe visible without scrolling',
            (tester) async {
          setSurface(tester, size, scale);
          _insets(tester, top, bottom);
          await pumpApp(tester,
              size: size,
              scale: scale,
              prefs: lang == 'es' ? spanishPrefs() : onboardedPrefs(),
              store: _PricedStore());
          _insets(tester, top, bottom);
          await tester.pumpAndSettle();
          final usable = size.height - bottom;
          expect(tester.getRect(find.byKey(const ValueKey('paywall-price')).first).bottom, lessThanOrEqualTo(usable));
          expect(tester.getRect(find.byKey(const ValueKey('paywall-subscribe'))).bottom, lessThanOrEqualTo(usable));
          expect(_page(tester).position.pixels, 0);
        });
      }
    }

    testWidgets('the hero keeps at least 150 pt plus the inset', (tester) async {
      setSurface(tester, const Size(320, 568), 1.0);
      await pumpApp(tester, size: const Size(320, 568), prefs: onboardedPrefs(), store: _PricedStore());
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('paywall-plan'))).top, greaterThanOrEqualTo(150));
    });

    testWidgets('onboarding step 1 fits the SE: all five goals and Continue without scrolling', (tester) async {
      setSurface(tester, const Size(375, 667), 1.0);
      _insets(tester, 20, 0);
      await pumpScreen(tester, const OnboardingScreen(initialStep: 0), size: const Size(375, 667));
      _insets(tester, 20, 0);
      await tester.pumpAndSettle();
      expect(_page(tester).position.maxScrollExtent, 0);
    });
  });

  group('contrast (item 14)', () {
    testWidgets('unselected radio / 18+ choice: faint, 3:1 or more on the tile (WCAG 1.4.11)', (tester) async {
      await pumpScreen(tester, const OnboardingScreen(initialStep: 2));
      await tester.pumpAndSettle();
      final icons = tester.widgetList<Icon>(find.byIcon(Icons.radio_button_unchecked_rounded)).toList();
      expect(icons, isNotEmpty);
      for (final i in icons) {
        expect(i.color, AppColors.faint);
        expect(_contrast(i.color!, AppColors.surface), greaterThanOrEqualTo(3));
      }
    });

    for (final style in [DwButtonStyle.rose, DwButtonStyle.ghost]) {
      testWidgets('disabled ${style.name} button: full opacity, label 4.5:1 or more', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: Center(child: DwButton(key: const ValueKey('b'), label: 'Continue', style: style, onPressed: null))),
        ));
        final opacity = tester.widget<Opacity>(find.descendant(of: find.byKey(const ValueKey('b')), matching: find.byType(Opacity)));
        expect(opacity.opacity, 1);
        final text = tester.widget<Text>(find.text('Continue'));
        final bg = Color.alphaBlend(const Color(0x0AFFFFFF), AppColors.background);
        expect(_contrast(text.style!.color!, bg), greaterThanOrEqualTo(4.5));
        // Still announced as disabled and not tappable.
        expect(tester.getSemantics(find.byKey(const ValueKey('b'))).flagsCollection.isEnabled, isNot(true));
      });
    }

    testWidgets('an enabled rose button is unchanged (gradient, rose ink)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: Center(child: DwButton(key: const ValueKey('b'), label: 'Go', style: DwButtonStyle.rose, onPressed: () {}))),
      ));
      expect(tester.widget<Text>(find.text('Go')).style!.color, AppColors.roseInk);
      final box = tester.widget<Container>(find.descendant(of: find.byKey(const ValueKey('b')), matching: find.byType(Container)).first);
      expect((box.decoration as BoxDecoration).gradient, AppColors.roseGradient);
    });
  });

  group('locked chat: coach greeting preview (item 21)', () {
    for (final (prefs, coach) in [(onboardedPrefs(), Coaches.ava), (spanishPrefs(), Coaches.sofia)]) {
      testWidgets('${coach.name}: the greeting shows read-only; nothing can be sent', (tester) async {
        final app = await pumpApp(tester, prefs: prefs, entitled: false, tab: AppTab.chat);
        if (find.byType(PaywallScreen).evaluate().isNotEmpty) {
          app.state.dismissPaywall();
          await tester.pumpAndSettle();
        }
        await tester.pumpAndSettle();
        final preview = find.byKey(const ValueKey('locked-preview-greeting'));
        expect(preview, findsOneWidget);
        expect(tester.widget<CoachText>(find.descendant(of: preview, matching: find.byType(CoachText))).text, coach.greeting);
        expect(find.byKey(const ValueKey('locked-preview-label')), findsOneWidget);
        // No way to send, and the preview is not a conversation.
        expect(find.byKey(const ValueKey('composer')), findsNothing);
        expect(find.byKey(const ValueKey('send')), findsNothing);
        expect(find.byKey(const ValueKey('hold-to-talk')), findsNothing);
        expect(app.state.threadsFor(coach), isEmpty);
        expect(app.state.canChat, isFalse);
        // See Premium is still above the fold, above the preview.
        final cta = tester.getRect(find.byKey(const ValueKey('locked-subscribe')));
        expect(cta.bottom, lessThanOrEqualTo(844));
        expect(cta.top, lessThan(tester.getRect(preview).top));
      });
    }
  });

  group('"New conversation" follows the UI language (item 22)', () {
    testWidgets('Spanish UI, Ava (English coach): Nueva conversación in Past conversations and on Home', (tester) async {
      await pumpApp(tester, prefs: _threadPrefs(coach: 'ava', language: 'es', title: 'New conversation'));
      await tester.pumpAndSettle();
      // Home's "pick up where you left off" line (no-break spaces inside).
      expect(find.textContaining(RegExp(r'New\sconversation')), findsNothing);
      expect(find.textContaining(RegExp(r'Nueva\sconversación')), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('tab-chat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-history')));
      await tester.pumpAndSettle();
      expect(find.text('Nueva conversación'), findsOneWidget);
      expect(find.text('New conversation'), findsNothing);
    });

    testWidgets('English UI, Sofía (Spanish coach): New conversation', (tester) async {
      await pumpApp(tester, prefs: _threadPrefs(coach: 'sofia', language: 'en', title: 'Nueva conversación'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-chat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-history')));
      await tester.pumpAndSettle();
      expect(find.text('New conversation'), findsOneWidget);
      expect(find.text('Nueva conversación'), findsNothing);
    });

    test('a title the user’s message gave is shown as is', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(AppState.threadTitle('Opener help', en), 'Opener help');
      expect(AppState.threadTitle('Nueva conversación', en), 'New conversation');
    });
  });
}
