import 'package:flutter/material.dart';

import '../../models/tier.dart';
import '../../theme/app_theme.dart';

/// Compact subscription card for the native Plans screen. Shows the price and
/// three key perks by default; tapping "See all features" expands the rest. The
/// recommended tier (`info.highlight`) gets a "MOST POPULAR" ribbon and an
/// emphasised border.
class PlanCard extends StatefulWidget {
  const PlanCard({
    super.key,
    required this.info,
    required this.selected,
    required this.onSelect,
  });

  final TierInfo info;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;
    final popular = info.highlight;
    final perks = info.highlights;
    final shown = _expanded ? perks : perks.take(3).toList();

    final borderColor = widget.selected
        ? AppColors.primary
        : popular
            ? AppColors.primary
            : AppColors.cardBorder;

    return Container(
      margin: const EdgeInsets.only(top: 10), // room for the ribbon
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: popular ? AppColors.flameTint : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: borderColor, width: popular ? 2 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + price row.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(info.name,
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          Text(info.tagline,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(info.priceLabel,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(' /wk',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Perks.
                ...shown.map(_perk),
                if (perks.length > 3)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                    child: Text(_expanded
                        ? 'Show less'
                        : 'See all ${perks.length} features'),
                  ),
                const SizedBox(height: AppSpacing.sm),

                // CTA.
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: widget.selected
                      ? OutlinedButton(
                          onPressed: null,
                          child: const Text('Your current plan'),
                        )
                      : popular
                          ? ElevatedButton(
                              onPressed: widget.onSelect,
                              child: Text('Choose ${info.name}'),
                            )
                          : OutlinedButton(
                              onPressed: widget.onSelect,
                              child: Text('Choose ${info.name}'),
                            ),
                ),
              ],
            ),
          ),

          // "MOST POPULAR" ribbon.
          if (popular)
            Positioned(
              top: -10,
              left: AppSpacing.lg,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  gradient: AppColors.romanticGradient,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Text(
                  'MOST POPULAR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _perk(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13.5, height: 1.3)),
          ),
        ],
      ),
    );
  }
}
