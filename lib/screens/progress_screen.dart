import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dw.dart';
import '../l10n/l10n.dart';

/// Honest, local progress: plan items done, conversations, days-used streak.
/// Counts only; no scores or invented percentages.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final coach = state.selectedCoach;
    final plan = state.plan;
    final top = MediaQuery.paddingOf(context).top;
    final streak = state.streakDays;
    final l = context.l10n;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, top + 16, 16, 28),
      child: ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: LargeTitle(title: l.progressTitle, subtitle: l.progressSubtitle),
            ),
            const SizedBox(height: 18),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _Stat(
                      key: const ValueKey('stat-conversations'),
                      value: '${state.conversationCount}',
                      label: l.statConversations(state.conversationCount),
                      icon: Icons.chat_bubble_outline_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      key: const ValueKey('stat-streak'),
                      value: '$streak',
                      label: l.statStreak(streak),
                      icon: Icons.local_fire_department_outlined,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            DwCard(
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, color: AppColors.gold, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      state.daysUsed == 0 ? l.noDaysYet(coach.name) : l.daysTotal(state.daysUsed),
                      style: const TextStyle(fontSize: 14.5, height: 1.4, color: AppColors.text),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (plan != null)
              DwCard(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Wraps onto two lines at large text sizes.
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(l.weekPlanTitle.toUpperCase(), style: AppText.eyebrow.copyWith(fontSize: 13)),
                        Text(l.planCount(plan.doneCount, plan.items.length),
                            key: const ValueKey('plan-count'), style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (var i = 0; i < plan.items.length; i++) ...[
                      if (i > 0) const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              plan.items[i].done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              color: plan.items[i].done ? AppColors.ok : AppColors.line2,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(l.planItemTitle(plan.items[i].goal, coach),
                                  style: TextStyle(fontSize: 15, height: 1.3, color: plan.items[i].done ? AppColors.textMuted : AppColors.text)),
                            ),
                            const SizedBox(width: 8),
                            Text(plan.items[i].done ? l.planDone : l.planNotYet, style: const TextStyle(fontSize: 13, color: AppColors.faint)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Text(
              l.progressFootnote,
              textAlign: TextAlign.center,
              style: AppText.small,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: DwCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.gold, size: 22),
            const SizedBox(height: 10),
            Text(value, style: AppText.display.copyWith(fontSize: 40, height: 1)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
