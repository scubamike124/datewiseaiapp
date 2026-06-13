import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Animated placeholder shown while a photo is being analysed. It mimics the
/// real [PhotoAnalysisCard] with a shimmering skeleton, and cycles through a
/// set of status steps so the (multi-second) wait feels lively and intentional
/// rather than frozen.
class AnalyzingCard extends StatefulWidget {
  const AnalyzingCard({super.key});

  @override
  State<AnalyzingCard> createState() => _AnalyzingCardState();
}

class _AnalyzingCardState extends State<AnalyzingCard>
    with TickerProviderStateMixin {
  // Each step is shown for ~1.1s, then it loops.
  static const List<(String, IconData)> _steps = [
    ('Reading the lighting', Icons.wb_sunny_outlined),
    ('Studying your expression', Icons.sentiment_satisfied_alt_outlined),
    ('Sizing up the outfit', Icons.checkroom_outlined),
    ('Checking framing & composition', Icons.crop_outlined),
    ('Scoring the overall vibe', Icons.auto_awesome_outlined),
  ];

  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  late final AnimationController _stepper = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 1100 * _steps.length),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    _stepper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score badge + headline skeleton.
          Row(
            children: [
              _shimmerBox(width: 56, height: 56, radius: AppRadius.md),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(width: 84, height: 18, radius: AppRadius.pill),
                    const SizedBox(height: 10),
                    _shimmerBox(
                        width: double.infinity, height: 12, radius: AppRadius.pill),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Dimension-bar skeletons.
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: _shimmerBox(
                  width: double.infinity, height: 8, radius: AppRadius.pill),
            ),
          const SizedBox(height: AppSpacing.md),
          // Rotating status step.
          AnimatedBuilder(
            animation: _stepper,
            builder: (context, _) {
              final idx = (_stepper.value * _steps.length)
                  .floor()
                  .clamp(0, _steps.length - 1);
              final (label, icon) = _steps[idx];
              return Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      gradient: AppColors.romanticGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 15),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        '$label…',
                        key: ValueKey(idx),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// A grey block with a highlight that sweeps across it (the shimmer).
  Widget _shimmerBox({
    required double width,
    required double height,
    double radius = 8,
  }) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              colors: const [
                Color(0xFFE8E1D2),
                Color(0xFFF7F2E8),
                Color(0xFFE8E1D2),
              ],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideGradient(_shimmer.value),
            ),
          ),
        );
      },
    );
  }
}

/// Slides a gradient horizontally from left (-1) to right (+1) as [t] goes 0→1.
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
  }
}
