import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tier.dart';
import '../services/purchase_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/plans/plan_card.dart';
import 'auth_screen.dart';

/// Native plans/pricing screen for mobile: compact [PlanCard]s with the
/// recommended tier highlighted. Choosing a plan runs through [PurchaseService]
/// (a hook for real Play Billing later), prompting sign-in first when accounts
/// are enabled.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key, this.onSelected});

  /// Called after a plan is successfully selected (e.g. to jump back to Coach).
  final VoidCallback? onSelected;

  static const PurchaseService _purchases = MockPurchaseService();

  Future<void> _select(BuildContext context, SubscriptionTier tier) async {
    final state = context.read<AppState>();

    // When accounts are enabled, subscribing requires an account first.
    if (state.authEnabled && !state.isSignedIn) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AuthScreen(
            reason:
                'Create an account to subscribe to ${TierInfo.of(tier).name}.',
          ),
        ),
      );
      if (ok != true || !context.mounted) return;
    }

    // Billing seam: today the mock succeeds immediately; real Play Billing
    // slots in here without changing the rest of this flow.
    bool purchased;
    try {
      purchased = await _purchases.buy(tier);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB91C1C),
          content: const Text('Purchase could not be completed.'),
        ),
      );
      return;
    }
    if (!purchased || !context.mounted) return;

    await state.selectTier(tier);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.raised,
        content: Text("You're on the ${TierInfo.of(tier).name} plan."),
      ),
    );
    onSelected?.call();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final current = state.tier;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Plans')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          Text(
            'Choose your magnetism',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            'Weekly plans · cancel anytime',
            textAlign: TextAlign.center,
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final info in TierInfo.all)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: PlanCard(
                info: info,
                selected: current == info.tier,
                onSelect: () => _select(context, info.tier),
              ),
            ),
          Text(
            'Subscriptions are billed through your app store. '
            'Manage or cancel in your store settings.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
