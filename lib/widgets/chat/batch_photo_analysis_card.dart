import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/batch_photo_analysis.dart';
import '../../models/photo_analysis.dart';
import '../../theme/app_theme.dart';

/// Rich card for a multi-photo "rank & compare" result: a recommendation banner
/// plus each photo (best→worst) with a medal, thumbnail, score, verdict, and a
/// one-line reason.
class BatchPhotoAnalysisCard extends StatelessWidget {
  const BatchPhotoAnalysisCard({super.key, required this.analysis});

  final BatchPhotoAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ranked = analysis.ranked;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.raised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recommendation banner.
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: AppColors.romanticGradient,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    analysis.recommendation,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < ranked.length; i++) ...[
            if (i > 0) const Divider(height: AppSpacing.md * 2),
            _RankedRow(photo: ranked[i], thumbnails: analysis.thumbnails),
          ],
        ],
      ),
    );
  }
}

class _RankedRow extends StatelessWidget {
  const _RankedRow({required this.photo, required this.thumbnails});

  final RankedPhoto photo;
  final List<String> thumbnails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasThumb =
        photo.imageIndex >= 0 && photo.imageIndex < thumbnails.length;
    final verdictColor = _verdictColor(photo.verdict);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thumbnail with a rank badge.
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child:
                  hasThumb
                      ? Image.memory(
                        base64Decode(thumbnails[photo.imageIndex]),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      )
                      : Container(
                        width: 64,
                        height: 64,
                        color: AppColors.background,
                        child: const Icon(
                          Icons.image_outlined,
                          color: AppColors.textMuted,
                        ),
                      ),
            ),
            Positioned(top: -6, left: -6, child: _RankBadge(rank: photo.rank)),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        // Score, verdict, and reason.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Photo ${photo.imageIndex + 1}',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${photo.overallScore}/10',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: verdictColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      photo.verdict.label,
                      style: TextStyle(
                        color: verdictColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                photo.headline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (photo.why.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  photo.why,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Color _verdictColor(PhotoVerdict verdict) {
    switch (verdict) {
      case PhotoVerdict.keep:
        return AppColors.success;
      case PhotoVerdict.reshoot:
        return AppColors.warning;
      case PhotoVerdict.delete:
        return AppColors.danger;
    }
  }
}

/// Medal for the top three, a plain number after that.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    const medals = {
      1: Color(0xFFE7B416),
      2: Color(0xFF9AA3AD),
      3: Color(0xFFB97A3A),
    };
    final color = medals[rank] ?? AppColors.raised;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          // Dark ink on the light medal colours; light on the plain badge.
          color: medals.containsKey(rank) ? AppColors.onAccent : AppColors.text,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}
