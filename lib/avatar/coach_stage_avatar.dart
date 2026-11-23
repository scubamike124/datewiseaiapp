import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';
import '../models/coach.dart';
import 'avatar_animator.dart';
import 'lip_sync.dart';
import 'talking_avatar.dart';

export 'avatar_animator.dart' show AvatarMood;

/// The voice stage's coach: a [TalkingAvatar] with localized labels.
class CoachStageAvatar extends StatelessWidget {
  const CoachStageAvatar({super.key, required this.coach, required this.mood, this.lipSync});

  final Coach coach;
  final AvatarMood mood;
  final LipSyncDriver? lipSync;

  /// The mood for the chat screen's state.
  static AvatarMood moodFor({required bool speaking, required bool listening, required bool responding}) =>
      speaking
          ? AvatarMood.speaking
          : listening
              ? AvatarMood.listening
              : responding
                  ? AvatarMood.thinking
                  : AvatarMood.idle;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final label = switch (mood) {
      AvatarMood.speaking => l.avatarSpeaking(coach.name),
      AvatarMood.listening => l.avatarListening(coach.name),
      AvatarMood.thinking => l.avatarThinking(coach.name),
      AvatarMood.idle => l.avatarAnimated(coach.name),
    };
    return TalkingAvatar(
      coach: coach,
      mood: mood,
      lipSync: lipSync,
      label: label,
      stillLabel: l.coachPortraitStill(coach.name),
    );
  }
}
