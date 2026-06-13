import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'screens/landing_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

/// Root widget. On mobile the app opens on a branded splash, then shows a
/// one-time intro walkthrough on first launch (returning users skip straight to
/// the landing page). On web — the SEO/marketing surface — it opens directly on
/// the landing page. From the landing/home page the user enters coaching via
/// "Start coaching" or by choosing a plan.
class DateWiseApp extends StatelessWidget {
  const DateWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DateWise AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: kIsWeb ? const LandingScreen() : const SplashScreen(),
    );
  }
}
