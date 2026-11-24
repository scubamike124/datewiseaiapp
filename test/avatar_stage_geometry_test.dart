// The avatar window keeps every coach's whole face in view: hair and
// forehead, brows, eyes, mouth and chin, on every phone, at 2.0 text and on
// iPad. (The real screen's geometry is in voice_conversation_test.dart.)

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/avatar_animator.dart' show AvatarPose;
import 'package:datewise_ai/avatar/avatar_frames.dart';
import 'package:datewise_ai/avatar/coach_stage_avatar.dart';
import 'package:datewise_ai/avatar/talking_avatar.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/widgets/dw.dart' show kContentMaxWidth;

void main() {
  // Stage card width: the screen (capped at kContentMaxWidth) minus the 12 pt margins.
  double card(double screen) => (screen < kContentMaxWidth ? screen : kContentMaxWidth) - 24;
  // name: (screen width, screen height).
  const phones = {
    'iPhone SE': (375.0, 667.0),
    'iPhone 12 mini': (360.0, 780.0),
    'iPhone 15': (393.0, 852.0),
    'iPhone 15 Pro Max': (430.0, 932.0),
    'iPad': (1024.0, 1366.0),
  };
  const browMargin = 0.1;

  for (final coach in Coaches.all) {
    final manifest = AvatarManifest.parse(coach.id, File('assets/avatar/${coach.id}/manifest.json').readAsStringSync());
    final image = Size(manifest.width.toDouble(), manifest.height.toDouble());
    final eyes = manifest.patches['gaze']!.rect;

    for (final e in phones.entries) {
      test('${coach.name} on ${e.key}: hair and forehead, brows, eyes, mouth and chin are inside the window', () {
        final win = CoachStageAvatar.windowSize(card(e.value.$1), screenHeight: e.value.$2);
        final box = Size(win.width, win.height * CoachStageAvatar.overscanFor(largeText: false));
        final src = AvatarPainter.sourceRect(image, box, manifest.mouth, coach.heroFocus);
        final z = AvatarPainter.coverZoom(box);
        double y(double v) => box.height / 2 + ((v - src.top) / src.height * box.height - box.height / 2) * z;
        final mouth = y(manifest.mouth!.dy);
        final chin = y(manifest.mouth!.dy + 0.65 * manifest.mouthWidth!) + AvatarPose.maxDy;
        final brows = y(eyes.top - browMargin * eyes.height) - AvatarPose.maxDy;
        final why = '${e.key}: window ${win.width}x${win.height}, brows $brows, eyes ${y(eyes.top)}-${y(eyes.bottom)}, mouth $mouth, chin $chin';
        expect(mouth / win.height, inInclusiveRange(0.5, 0.75), reason: why);
        expect(chin, lessThanOrEqualTo(win.height), reason: why);
        expect(brows, greaterThan(win.height * 0.15), reason: 'a band of hair and forehead above the brows: $why');
        expect(y(eyes.bottom), lessThan(mouth), reason: why);
      });
    }
  }

  test('the avatar window is 4:5, about a third of the card, within limits', () {
    expect(CoachStageAvatar.windowSize(369).width / CoachStageAvatar.windowSize(369).height, closeTo(0.8, 1e-9));
    expect(CoachStageAvatar.windowSize(369).width, closeTo(132.84, 0.01));
    expect(CoachStageAvatar.windowSize(2000).width, 160, reason: 'iPad: no larger than 160 pt wide');
    expect(CoachStageAvatar.windowSize(200).width, 112, reason: 'never narrower than 112 pt');
  });

  test('a short screen shrinks the window to 24% of its height, never below 120 pt', () {
    expect(CoachStageAvatar.windowSize(351, screenHeight: 667).height, closeTo(157.95, 0.01), reason: 'SE: under the cap');
    expect(CoachStageAvatar.windowSize(351, screenHeight: 600).height, closeTo(600 * 0.24, 0.01));
    expect(CoachStageAvatar.windowSize(351, screenHeight: 393).height, 120, reason: 'landscape phone: the 120 pt floor');
    expect(CoachStageAvatar.windowSize(369, screenHeight: 852).height, closeTo(166.05, 0.01), reason: 'iPhone 15: not shrunk');
  });

  test('a mouth at or beyond the portrait edge falls back to the focus crop (no empty rect)', () {
    const image = Size(1000, 1200);
    const box = Size(390, 195);
    for (final dy in [0.0, -5.0, 1200.0, 1300.0, 0.2, 1199.9]) {
      final r = AvatarPainter.sourceRect(image, box, Offset(500, dy), Alignment.center);
      expect(r.width, greaterThan(1), reason: 'dy=$dy');
      expect(r.height, greaterThan(1), reason: 'dy=$dy');
      expect(r.left >= 0 && r.top >= 0 && r.right <= image.width + 1e-6 && r.bottom <= image.height + 1e-6, isTrue, reason: 'dy=$dy');
    }
  });
}
