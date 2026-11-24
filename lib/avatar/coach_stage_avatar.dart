import 'dart:math' as math;

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

  /// Height of the voice stage's portrait for a stage [width]: 0.6 of the
  /// width (so the face keeps its size on wide screens and the brows fit),
  /// within 150-250 pt; shorter at large text (130-170 pt), which leaves
  /// room for the captions.
  static double stageHeight(double width, {required bool largeText}) =>
      largeText ? (width / 2.6).clamp(130.0, 170.0) : (width * 0.6).clamp(150.0, 250.0);

  /// The portrait box of the voice stage. It is never taller than the stage
  /// was before the framing change (half the width, 150-240 pt), so the
  /// conversation below keeps at least the room it had; on a short screen it
  /// is also at most 26% of the height ([screenHeight]), and at large text
  /// it is [stageHeight]'s shorter height, within 18% of the screen. When it
  /// is shorter than [stageHeight] at normal text, the box is narrowed in
  /// step (and centered), so the face is framed exactly as at normal text,
  /// just smaller: brows, eyes, mouth and chin stay in view at any size.
  static Size portraitSize(double width, {required bool largeText, double screenHeight = double.infinity}) {
    final full = stageHeight(width, largeText: false);
    double h;
    if (largeText) {
      h = stageHeight(width, largeText: true);
      if (screenHeight.isFinite) h = (screenHeight * 0.18 - 2).clamp(100.0, h);
    } else {
      h = math.min(full, (width / 2.0).clamp(150.0, 240.0));
      if (screenHeight.isFinite) h = (screenHeight * 0.26).clamp(130.0, h);
    }
    return Size(width * h / full, h);
  }

  /// The portrait is laid out [portraitOverscan] times taller than the
  /// stage, from the top, and the bottom is clipped. The painter puts the
  /// mouth at 55% of the portrait's height, so this lands it at about 66%
  /// of the stage and shows the brows above the eyes. The chin and the
  /// lower lip stay above the caption fade. Patches are painted inside the
  /// portrait, so blink and gaze stay aligned. Not used at large text,
  /// whose stage is shorter but is framed the same way.
  static const double portraitOverscan = 1.2;

  /// The overscan for the stage at this text size.
  static double overscanFor({required bool largeText}) => portraitOverscan;

  /// Where the caption fade starts (fraction of the stage height): below
  /// the chin, so the mouth is never faded.
  static const double fadeStart = 0.85;

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
