import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'dev/review_mode.dart';
import 'screens/shell.dart';
import 'services/ai_service.dart';
import 'services/mock_ai_service.dart';
import 'services/speech_service.dart';
import 'services/storage_service.dart';
import 'services/store_service.dart';
import 'services/voice_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF120C0E),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  final storage = await StorageService.create();
  final review = ReviewMode.requestedScreen();
  final ai = ReviewMode.aiFor(review) ?? (ReviewMode.mockAI ? MockAIService() : AIServiceFactory.create());
  final store = createStoreService();
  final voice = await DeviceVoiceService.create();
  final speech = DeviceSpeechService.create();
  final state = AppState(storage: storage, ai: ai, store: store);
  store.init();

  var initialTab = AppTab.home;
  if (review != null) {
    await storage.clearAll();
    await state.deleteMyData();
    initialTab = await ReviewMode.seed(review, state, store);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StoreService>.value(value: store),
        ChangeNotifierProvider<AppState>.value(value: state),
        Provider<VoiceService>.value(value: voice),
        Provider<SpeechService>.value(value: speech),
      ],
      child: DateWiseApp(initialTab: initialTab, reviewHome: ReviewMode.home(review)),
    ),
  );
}
