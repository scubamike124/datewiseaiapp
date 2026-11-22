import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/ai_service.dart';
import 'services/auth_service.dart';
import 'services/storage_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Native polish (mobile only): draw behind the system bars and tint them to
  // match the app's midnight theme, so the Android app reads as a real native app
  // rather than a web viewport. Skipped on web.
  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: AppColors.cardBorder,
    ));
  }

  // Optional accounts backend. No-op unless Supabase is configured
  // (see lib/services/supabase_config.dart).
  await AuthService.initialize();

  final storage = await StorageService.create();
  final ai = AIServiceFactory.create();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(storage: storage, ai: ai, auth: AuthService()),
      child: const DateWiseApp(),
    ),
  );
}
