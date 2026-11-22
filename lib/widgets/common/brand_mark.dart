import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The DateWise AI wordmark: a glowing violet heart glyph + name, with "AI"
/// in rose gold.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false, this.onLight = false});

  final bool compact;

  /// Legacy flag from the light theme (white text on a dark band). The theme
  /// is dark everywhere now, so both values render the same light wordmark.
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    const color = AppColors.text;
    // Scales down as a whole rather than overflowing in a tight header or
    // with large accessibility text.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: AppColors.romanticGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.45),
                  blurRadius: 14,
                ),
              ],
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: AppSpacing.sm),
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'DateWise',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: color,
                      letterSpacing: -0.3,
                    ),
                  ),
                  TextSpan(
                    text: ' AI',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: AppColors.accent,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
