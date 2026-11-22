import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/paywall_screen.dart';
import 'screens/shell.dart';
import 'screens/welcome_screen.dart';
import 'services/store_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// Root widget: dark "Evening" theme and the top-level gate.
class DateWiseApp extends StatelessWidget {
  const DateWiseApp({super.key, this.initialTab = AppTab.home});
  final AppTab initialTab;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DateWise AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: RootGate(initialTab: initialTab),
    );
  }
}

/// New users see the welcome + onboarding; then the paywall (before the
/// first chat); then the five-tab app. A user who closes the paywall can use
/// Home, Coaches, Progress and You, but chat stays locked until subscribed.
class RootGate extends StatelessWidget {
  const RootGate({super.key, this.initialTab = AppTab.home});
  final AppTab initialTab;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final store = context.watch<StoreService>();
    if (!state.onboarded) return const WelcomeScreen();
    if (!store.ready) return const Scaffold(backgroundColor: AppColors.background);
    if (!store.isEntitled && !state.paywallDismissed) {
      return PaywallScreen(onClose: state.dismissPaywall);
    }
    return HomeShell(initialTab: initialTab);
  }
}
