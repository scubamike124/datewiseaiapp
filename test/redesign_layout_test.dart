// Every main screen of the midnight redesign builds without a layout overflow
// on a small phone, a large phone and a desktop browser, and on the small
// phone with large accessibility text. No goldens: a RenderFlex overflow (or
// any other build/layout error) is reported by takeException.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/content/legal_text.dart';
import 'package:datewise_ai/screens/auth_screen.dart';
import 'package:datewise_ai/screens/chat_screen.dart';
import 'package:datewise_ai/screens/coach_picker_screen.dart';
import 'package:datewise_ai/screens/home_shell.dart';
import 'package:datewise_ai/screens/intro_screen.dart';
import 'package:datewise_ai/screens/landing_screen.dart';
import 'package:datewise_ai/screens/legal_screen.dart';
import 'package:datewise_ai/screens/onboarding_screen.dart';
import 'package:datewise_ai/screens/plans_screen.dart';
import 'package:datewise_ai/screens/settings_screen.dart';
import 'package:datewise_ai/services/mock_ai_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/state/app_state.dart';
import 'package:datewise_ai/theme/app_theme.dart';

const _sizes = {
  'phone 375x667': (Size(375, 667), 1.0),
  'phone 430x932': (Size(430, 932), 1.0),
  'desktop 1280x800': (Size(1280, 800), 1.0),
  'phone 375x667 @1.3x text': (Size(375, 667), 1.3),
};

/// Screens, each with the saved preferences it starts from.
final Map<String, (Widget Function(), Map<String, Object>)> _screens = {
  'landing': (() => const LandingScreen(), {}),
  'intro': (() => const IntroScreen(), {}),
  'onboarding': (() => const OnboardingScreen(), {}),
  'auth': (() => const AuthScreen(), {}),
  'coach picker (first run)': (() => const ChatScreen(), {}),
  'coach picker (switch)': (
    () => const CoachPickerScreen(),
    {'dw_coach': 'mateo'},
  ),
  'chat with Mateo': (() => const ChatScreen(), {'dw_coach': 'mateo'}),
  'home shell': (() => const HomeShell(), {'dw_coach': 'emily'}),
  'account tab': (
    () => const HomeShell(initialIndex: 1),
    {'dw_coach': 'emily'},
  ),
  'settings': (() => const SettingsScreen(), {}),
  'legal': (
    () => const LegalScreen(title: 'Privacy Policy', content: kPrivacyPolicy),
    {},
  ),
  'plans': (() => const PlansScreen(), {}),
};

Future<void> _pump(
  WidgetTester tester,
  Widget Function() screen,
  Map<String, Object> prefs,
  Size size,
  double scale,
) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  if (scale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  SharedPreferences.setMockInitialValues(prefs);
  final state = AppState(
    storage: await StorageService.create(),
    ai: MockAIService(),
  );
  if (prefs.containsKey('dw_coach')) {
    await state.selectCoach(prefs['dw_coach']! as String);
  }
  await mockNetworkImagesFor(() async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: AppTheme.dark, home: screen()),
      ),
    );
    // Let entry animations (fade/slide-in, reveals) finish.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
  });
}

void main() {
  for (final screen in _screens.entries) {
    for (final size in _sizes.entries) {
      testWidgets('${screen.key} fits ${size.key}', (tester) async {
        final (build, prefs) = screen.value;
        final (s, scale) = size.value;
        await _pump(tester, build, prefs, s, scale);
        final error = tester.takeException();
        expect(
          error,
          isNull,
          reason:
              '${screen.key} on ${size.key}: ${error is FlutterError ? error.toStringDeep() : error}',
        );
      });
    }
  }

  testWidgets('the coach avatar glows while Mateo replies, then settles', (
    tester,
  ) async {
    await _pump(
      tester,
      () => const ChatScreen(),
      {'dw_coach': 'mateo'},
      const Size(430, 932),
      1.0,
    );
    final state = tester.element(find.byType(ChatScreen)).read<AppState>();
    await tester.tap(find.text('Planea una primera cita'));
    await tester.pump();
    expect(state.isResponding, isTrue);
    for (var i = 0; i < 400 && state.isResponding; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
    expect(state.isResponding, isFalse);
    expect(state.activeThread!.messages.last.text, contains('lugar público'));
    expect(tester.takeException(), isNull);
  });
}
