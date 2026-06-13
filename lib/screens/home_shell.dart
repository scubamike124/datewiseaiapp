import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_flags.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'account_screen.dart';
import 'auth_screen.dart';
import 'chat_screen.dart';
import 'plans_screen.dart';
import 'settings_screen.dart';

/// AppBar gear that opens [SettingsScreen]. Shared by the Account-tab states.
List<Widget> _settingsActions(BuildContext context) => [
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        tooltip: 'Settings',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
    ];

/// Native mobile home: a bottom-tab shell (Coach / Plans / Account) that hosts
/// the app's real screens. This replaces the marketing landing page as the
/// post-onboarding destination on mobile, giving the Android app a true native
/// feel instead of a scrolling website. (Web is unaffected — it still opens on
/// the LandingScreen via the kIsWeb branch in app.dart.)
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  /// Tab to open on first build (0 = Coach, 1 = Plans, 2 = Account).
  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialIndex;

  void _goToTab(int i) {
    if (_index == i) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    // During the free launch the Plans tab is hidden (everything is unlocked).
    // Build the tabs and nav destinations from the same conditional so the
    // positional indices stay consistent (Coach is always 0).
    final showPlans = !AppFlags.freeLaunch;

    final tabs = <Widget>[
      const ChatScreen(),
      if (showPlans) PlansScreen(onSelected: () => _goToTab(0)),
      _AccountTab(onChangePlan: showPlans ? () => _goToTab(1) : null),
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.forum_outlined),
        selectedIcon: Icon(Icons.forum, color: AppColors.primary),
        label: 'Coach',
      ),
      if (showPlans)
        const NavigationDestination(
          icon: Icon(Icons.workspace_premium_outlined),
          selectedIcon:
              Icon(Icons.workspace_premium, color: AppColors.primary),
          label: 'Plans',
        ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person, color: AppColors.primary),
        label: 'Account',
      ),
    ];

    // Android back: if we're not on the Coach tab, go there first instead of
    // leaving the app — the expected native behavior for a tabbed app.
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) _goToTab(0);
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: tabs),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goToTab,
          backgroundColor: Colors.white,
          indicatorColor: AppColors.primary.withValues(alpha: 0.12),
          surfaceTintColor: Colors.transparent,
          destinations: destinations,
        ),
      ),
    );
  }
}

/// Account tab. Adapts to whether accounts are enabled and whether the user is
/// signed in, reusing [AccountScreen] for the full signed-in experience.
class _AccountTab extends StatelessWidget {
  const _AccountTab({required this.onChangePlan});

  /// Switches the shell to the Plans tab. Null when the Plans tab is hidden
  /// (free launch) — plan-change affordances are then suppressed.
  final VoidCallback? onChangePlan;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.authEnabled) {
      if (state.isSignedIn) {
        return AccountScreen(embedded: true, onChangePlan: onChangePlan);
      }
      return _SignInPrompt(onChangePlan: onChangePlan);
    }
    return _GuestAccount(onChangePlan: onChangePlan);
  }
}

/// Shown on the Account tab when accounts are enabled but the user is signed
/// out. Authenticating rebuilds the tab into the full [AccountScreen].
class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.onChangePlan});
  final VoidCallback? onChangePlan;

  Future<void> _auth(BuildContext context, {required bool signUp}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AuthScreen(
          startInSignUp: signUp,
          reason: 'Sign in to sync your plan and manage your account.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Account'),
        actions: _settingsActions(context),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  gradient: AppColors.romanticGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Your DateWise account',
                  style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Sign in to sync your plan across devices and manage your '
                'profile.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _auth(context, signUp: true),
                  child: const Text('Create account'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _auth(context, signUp: false),
                  child: const Text('Log in'),
                ),
              ),
              if (onChangePlan != null) ...[
                const SizedBox(height: AppSpacing.lg),
                TextButton(
                  onPressed: onChangePlan,
                  child: const Text('See plans'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown on the Account tab when accounts are switched off (no Supabase
/// backend): a lightweight summary with the current plan and a privacy note.
class _GuestAccount extends StatelessWidget {
  const _GuestAccount({required this.onChangePlan});
  final VoidCallback? onChangePlan;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final tierInfo = state.tierInfo;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Account'),
        actions: _settingsActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Plan summary + "Change" — hidden during the free launch, when the
          // Plans tab is gone and there is no plan to change.
          if (onChangePlan != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_outlined,
                      color: tierInfo.accentColor),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Current plan',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: AppColors.textMuted)),
                        Text(tierInfo.name, style: theme.textTheme.titleMedium),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onChangePlan,
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Private by design — your chats and photos stay on this '
                  'device.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
