// Every screen at iPhone SE, iPhone 15/16, Pro Max, iPad 13" and desktop sizes, at
// text scale 1.0 and 1.3 (Dynamic Type). Any RenderFlex overflow or other
// layout exception fails the test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/content/legal_text.dart';
import 'package:datewise_ai/screens/legal_screen.dart';
import 'package:datewise_ai/screens/onboarding_screen.dart';
import 'package:datewise_ai/screens/paywall_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/screens/welcome_screen.dart';
import 'package:datewise_ai/services/store_service.dart';

import 'helpers.dart';

typedef Pump = Future<void> Function(WidgetTester tester, Size size, double scale);

final Map<String, Pump> screens = {
  'welcome': (t, size, scale) async {
    await pumpScreen(t, const WelcomeScreen(), size: size, scale: scale);
    expect(find.text('Get started'), findsOneWidget);
  },
  'onboarding goals': (t, size, scale) async {
    await pumpScreen(t, const OnboardingScreen(), size: size, scale: scale);
    expect(find.text('What would you like help\u00a0with?'), findsOneWidget);
  },
  'onboarding language': (t, size, scale) async {
    await pumpScreen(t, const OnboardingScreen(initialStep: 1), size: size, scale: scale);
    expect(find.text('Español'), findsOneWidget);
  },
  'onboarding 18+': (t, size, scale) async {
    await pumpScreen(t, const OnboardingScreen(initialStep: 2), size: size, scale: scale);
    expect(find.text('I am 18 or older'), findsOneWidget);
  },
  'onboarding coach': (t, size, scale) async {
    await pumpScreen(t, const OnboardingScreen(initialStep: 3), size: size, scale: scale);
    expect(find.text('Chat with Ava'), findsOneWidget);
  },
  'paywall': (t, size, scale) async {
    await pumpScreen(t, PaywallScreen(onClose: () {}), size: size, scale: scale, entitled: false, prefs: onboardedPrefs());
    expect(find.byKey(const ValueKey('paywall-subscribe')), findsOneWidget);
  },
  'paywall (web, no purchases)': (t, size, scale) async {
    await pumpScreen(t, PaywallScreen(onClose: () {}),
        size: size, scale: scale, store: UnsupportedStoreService(), prefs: onboardedPrefs());
    expect(find.byKey(const ValueKey('paywall-web')), findsOneWidget);
  },
  'home': (t, size, scale) async {
    await pumpApp(t, size: size, scale: scale, prefs: onboardedPrefs());
    expect(find.text('YOUR PLAN THIS WEEK'), findsOneWidget);
  },
  'coaches': (t, size, scale) async {
    await pumpApp(t, size: size, scale: scale, prefs: onboardedPrefs(), tab: AppTab.coaches);
    expect(find.text('Chat with Sofía'), findsOneWidget);
  },
  'chat with a conversation': (t, size, scale) async {
    final app = await pumpApp(t, size: size, scale: scale, prefs: onboardedPrefs(), tab: AppTab.chat);
    await t.tap(find.byKey(const ValueKey('starter-Give me a strong opener')));
    await t.pump();
    await settleReply(t, app.state);
    expect(app.state.activeThread!.messages.last.isUser, isFalse);
    expect(find.byKey(const ValueKey('option-Playful')), findsOneWidget);
  },
  'chat locked (no subscription)': (t, size, scale) async {
    await pumpApp(t, size: size, scale: scale, prefs: onboardedPrefs(), tab: AppTab.chat, entitled: false);
    // The root shows the paywall first; close it to reach the locked chat.
    await t.tap(find.byKey(const ValueKey('paywall-close')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('locked-subscribe')), findsOneWidget);
  },
  'progress': (t, size, scale) async {
    await pumpApp(t, size: size, scale: scale, prefs: onboardedPrefs(), tab: AppTab.progress);
    expect(find.byKey(const ValueKey('plan-count')), findsOneWidget);
  },
  'you (settings)': (t, size, scale) async {
    await pumpApp(t, size: size, scale: scale, prefs: {...onboardedPrefs(), 'dw_memory_text': 'Shy at first, on Hinge.'}, tab: AppTab.you);
    expect(find.text('Coach memory'), findsWidgets);
  },
  'privacy policy': (t, size, scale) async {
    await pumpScreen(t, LegalScreen(title: 'Privacy Policy', content: kPrivacyPolicy), size: size, scale: scale);
    expect(find.text('Privacy Policy'), findsOneWidget);
  },
};

void main() {
  for (final screen in screens.entries) {
    group(screen.key, () {
      for (final size in sizes.entries) {
        for (final scale in textScales) {
          testWidgets('fits ${size.key} at text scale $scale', (tester) async {
            await screen.value(tester, size.value, scale);
            await tester.pump(const Duration(milliseconds: 500));
            expect(tester.takeException(), isNull, reason: '${screen.key} overflows at ${size.key} x$scale');
          });
        }
      }
    });
  }
}
