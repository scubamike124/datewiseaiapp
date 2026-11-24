import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/l10n.dart';
import 'screens/onboarding_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/shell.dart';
import 'screens/welcome_screen.dart';
import 'services/store_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'models/coach.dart';

/// Root widget: dark "Evening" theme, English/Spanish localization and the
/// top-level gate. The UI language is the user's choice (onboarding or
/// You › Language); before they choose, the device language (es* → Spanish).
class DateWiseApp extends StatefulWidget {
  const DateWiseApp({super.key, this.initialTab = AppTab.home, this.reviewHome});
  final AppTab initialTab;

  /// Review builds only: a screen shown instead of the welcome screen.
  final Widget? reviewHome;

  @override
  State<DateWiseApp> createState() => _DateWiseAppState();
}

class _DateWiseAppState extends State<DateWiseApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Re-check the subscription whenever the app returns to the foreground:
    // a subscription canceled or expired meanwhile locks chat again.
    _lifecycle = AppLifecycleListener(onResume: () => context.read<StoreService>().refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chosen = context.select<AppState, CoachLanguage?>((s) => s.chosenLanguage);
    return MaterialApp(
      onGenerateTitle: (ctx) => ctx.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      locale: chosen == null ? null : AppLocales.of(chosen),
      supportedLocales: AppLocales.supported,
      localeListResolutionCallback: (locales, _) => AppLocales.resolve(locales),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RootGate(initialTab: widget.initialTab, reviewHome: widget.reviewHome),
    );
  }
}

/// New users see the welcome + onboarding; then the paywall (before the
/// first chat); then the five-tab app. A user who closes the paywall can use
/// Home, Coaches, Progress and You, but chat stays locked until subscribed.
/// Someone who said they are under 18 only ever sees the "adults only" page.
class RootGate extends StatelessWidget {
  const RootGate({super.key, this.initialTab = AppTab.home, this.reviewHome});
  final AppTab initialTab;
  final Widget? reviewHome;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final store = context.watch<StoreService>();
    if (state.underageBlocked) return const UnderageScreen();
    if (!state.onboarded) return reviewHome ?? const WelcomeScreen();
    if (!store.ready) return const Scaffold(backgroundColor: AppColors.background);
    if (!store.isEntitled && !state.paywallDismissed) {
      return PaywallScreen(onClose: state.dismissPaywall);
    }
    // Back from a paywall that interrupted the chat: straight to the chat,
    // where the user's draft is waiting.
    // Likewise right after onboarding, whose last button is "Chat with <coach>".
    return HomeShell(initialTab: state.hasDraft || state.openChatFirst ? AppTab.chat : initialTab);
  }
}
