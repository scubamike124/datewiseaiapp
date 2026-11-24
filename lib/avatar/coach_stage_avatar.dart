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

  /// The window is 4:5 (width : height): tall enough for the whole face,
  /// from the hair above the forehead to the chin, in a small tile.
  static const double windowAspect = 0.8;

  /// The avatar window's size in a stage card [cardWidth] wide: about a third
  /// of the card (112-160 pt wide), never taller than 24% of the screen
  /// ([screenHeight]) or shorter than 120 pt, so a small phone keeps room for
  /// the conversation. The face is framed the same at every size.
  static Size windowSize(double cardWidth, {double screenHeight = double.infinity}) {
    var w = (cardWidth * 0.36).clamp(112.0, 160.0);
    var h = w / windowAspect;
    final cap = screenHeight * 0.24;
    if (h > cap) h = cap < 120 ? 120 : cap;
    w = h * windowAspect;
    return Size(w, h);
  }

  /// The portrait is laid out [portraitOverscan] times taller than the
  /// window, from the top, and the bottom is clipped. The painter puts the
  /// mouth at 55% of the portrait's height, so this lands it at about 66% of
  /// the window, with the hair, forehead, brows and eyes above it and the
  /// chin and lower lip inside the bottom edge. Patches are painted inside
  /// the portrait, so blink and gaze stay aligned.
  static const double portraitOverscan = 1.2;

  /// The overscan for the window.
  static double overscanFor({required bool largeText}) => portraitOverscan;

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
    final avatar = TalkingAvatar(
      coach: coach,
      mood: mood,
      lipSync: lipSync,
      label: label,
      stillLabel: l.coachPortraitStill(coach.name),
    );
    final k = overscanFor(largeText: MediaQuery.textScalerOf(context).scale(1) > 1.3);
    if (k == 1.0) return avatar;
    return LayoutBuilder(
      builder: (context, box) {
        if (!box.hasBoundedHeight || !box.hasBoundedWidth) return avatar;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: box.maxWidth,
            maxWidth: box.maxWidth,
            minHeight: box.maxHeight * k,
            maxHeight: box.maxHeight * k,
            child: avatar,
          ),
        );
      },
    );
  }
}
