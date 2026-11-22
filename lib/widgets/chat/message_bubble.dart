import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../models/coach.dart';
import '../coach/coach_avatar.dart';
import '../common/premium.dart';
import '../../theme/app_theme.dart';
import 'analyzing_card.dart';
import 'batch_photo_analysis_card.dart';
import 'coach_text.dart';
import 'photo_analysis_card.dart';

/// One chat row: user messages right-aligned in a violet gradient bubble,
/// coach messages left-aligned in a glass bubble with the coach avatar and rich
/// (markdown/photo-card) content.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.coach});

  final ChatMessage message;

  /// Whose message this is (the conversation's coach). Null keeps the
  /// original DateWise mark.
  final Coach? coach;

  @override
  Widget build(BuildContext context) {
    return message.isUser ? _buildUser(context) : _buildCoach(context);
  }

  Widget _buildUser(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 6,
        horizontal: AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                gradient: AppColors.romanticGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (message.imageBase64s != null)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: message.text.isEmpty ? 0 : AppSpacing.sm,
                      ),
                      child: _imageGrid(message.imageBase64s!),
                    )
                  else if (message.imageBase64 != null)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: message.text.isEmpty ? 0 : AppSpacing.sm,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Image.memory(
                          base64Decode(message.imageBase64!),
                          width: 200,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) => const SizedBox(
                                width: 200,
                                height: 120,
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.white,
                                ),
                              ),
                        ),
                      ),
                    ),
                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A compact grid of the user's attached photos (rank & compare uploads).
  Widget _imageGrid(List<String> images) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 218),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final b64 in images)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.memory(
                base64Decode(b64),
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, __, ___) => const SizedBox(
                      width: 100,
                      height: 100,
                      child: Icon(Icons.broken_image, color: Colors.white),
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCoach(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 6,
        horizontal: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (coach != null)
            CoachAvatar(coach: coach!, radius: 16, glowing: message.isStreaming)
          else
            const GradientIcon(icon: Icons.auto_awesome, size: 32, glow: false),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.94),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.isAnalyzing)
                    const AnalyzingCard()
                  else if (message.text.isNotEmpty)
                    CoachText(message.text)
                  else if (message.isStreaming)
                    const _TypingDots(),
                  if (message.isStreaming && message.text.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: _TypingDots(),
                    ),
                  if (message.analysis != null)
                    PhotoAnalysisCard(analysis: message.analysis!),
                  if (message.batchAnalysis != null)
                    BatchPhotoAnalysisCard(analysis: message.batchAnalysis!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final t = (_controller.value + i * 0.2) % 1.0;
              final opacity = (0.3 + 0.7 * (1 - (t - 0.5).abs() * 2)).clamp(
                0.3,
                1.0,
              );
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Opacity(
                  opacity: opacity,
                  child: const CircleAvatar(
                    radius: 3,
                    backgroundColor: AppColors.primaryLight,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
