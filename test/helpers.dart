import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/l10n/l10n.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/mock_ai_service.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/services/voice_service.dart';
import 'package:datewise_ai/state/app_state.dart';
import 'package:datewise_ai/theme/app_theme.dart';

/// Logical sizes every screen must fit: iPhone SE, iPhone 15/16,
/// iPhone Pro Max, and a desktop browser window.
const sizes = {
  '375x667': Size(375, 667),
  '390x844': Size(390, 844),
  '430x932': Size(430, 932),
  '1280x800': Size(1280, 800),
};

const textScales = [1.0, 1.3];

/// Prefs for a user who finished onboarding with Ava (or [coach], in
/// [language]: the UI language follows it).
Map<String, Object> onboardedPrefs({String coach = 'ava', String language = 'en'}) => {
      'dw_onboarded': true,
      'dw_coach': coach,
      'dw_profile': '{"goals":["profile","conversations","dates"],"language":"$language"}',
    };

/// Same, in Spanish with Sofía.
Map<String, Object> spanishPrefs() => onboardedPrefs(coach: 'sofia', language: 'es');

const localizationsDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class TestApp {
  TestApp(this.state, this.store, this.storage);
  final AppState state;
  final StoreService store;
  final StorageService storage;
}

void setSurface(WidgetTester tester, Size size, double scale) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<TestApp> makeState({
  Map<String, Object> prefs = const {},
  bool entitled = true,
  StoreService? store,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storage = await StorageService.create();
  final s = store ?? FakeStoreService(entitled: entitled);
  final state = AppState(storage: storage, ai: MockAIService(), store: s);
  return TestApp(state, s, storage);
}

Widget wrap(TestApp app, Widget child, {SpeechService? speech, VoiceService? voice}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<StoreService>.value(value: app.store),
        ChangeNotifierProvider<AppState>.value(value: app.state),
        Provider<VoiceService>.value(value: voice ?? NoVoiceService()),
        Provider<SpeechService>.value(value: speech ?? NoSpeechService()),
      ],
      child: child,
    );

/// Pumps the whole app (root gate included).
Future<TestApp> pumpApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1.0,
  Map<String, Object> prefs = const {},
  bool entitled = true,
  StoreService? store,
  AppTab tab = AppTab.home,
  SpeechService? speech,
  VoiceService? voice,
}) async {
  setSurface(tester, size, scale);
  final app = await makeState(prefs: prefs, entitled: entitled, store: store);
  await tester.pumpWidget(wrap(app, DateWiseApp(initialTab: tab), speech: speech, voice: voice));
  await tester.pump();
  return app;
}

/// Pumps a single screen in the app theme (with a shell controller).
Future<TestApp> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(390, 844),
  double scale = 1.0,
  Map<String, Object> prefs = const {},
  bool entitled = true,
  StoreService? store,
  Locale locale = const Locale('en'),
}) async {
  setSurface(tester, size, scale);
  final app = await makeState(prefs: prefs, entitled: entitled, store: store);
  await tester.pumpWidget(wrap(
    app,
    ChangeNotifierProvider(
      create: (_) => ShellController(),
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: locale,
        supportedLocales: AppLocales.supported,
        localizationsDelegates: localizationsDelegates,
        home: screen,
      ),
    ),
  ));
  await tester.pump();
  return app;
}

/// Lets the offline coach finish streaming (22 ms per word).
Future<void> settleReply(WidgetTester tester, AppState state) async {
  for (var i = 0; i < 600 && state.isResponding; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  await tester.pump(const Duration(milliseconds: 300));
}
