// ignore_for_file: invalid_use_of_visible_for_testing_member
// Renders the voice stage's portrait before/after the framing change at 3x,
// for every coach and the iPhone SE, 15 and 15 Pro Max stage widths.
//
//   AVATAR_FRAMING_OUT=<dir> flutter test tool/avatar/render_framing_test.dart
//
// "before" is the 2:1 stage with the portrait box as tall as the stage;
// "after" is what the app draws now (CoachStageAvatar.portraitSize and
// portraitOverscan). Both use the app's own AvatarPainter and fade.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/avatar_animator.dart';
import 'package:datewise_ai/avatar/avatar_frames.dart';
import 'package:datewise_ai/avatar/coach_stage_avatar.dart';
import 'package:datewise_ai/avatar/talking_avatar.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/theme/app_theme.dart';

void main() {
  final outDir = Platform.environment['AVATAR_FRAMING_OUT'];
  const scale = 3.0;
  // name: (screen width, screen height).
  const screens = {'se': (375.0, 667.0), 'iphone15': (393.0, 852.0), 'promax': (430.0, 932.0)};

  Future<void> render(Coach coach, String file, double w, double h, double k, {bool fade = true}) async {
    final frames = (await AvatarFrames.load(coach))!;
    final painter = AvatarPainter(frames, ValueNotifier(AvatarPose.still), coach.heroFocus);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(scale);
    c.clipRect(Rect.fromLTWH(0, 0, w, h));
    painter.paint(c, Size(w, h * k));
    const fadeStart = 0.85; // the old stage's caption fade
    final fadeRect = Rect.fromLTWH(0, h * fadeStart, w, h * (1 - fadeStart));
    if (fade) {
      c.drawRect(
      fadeRect,
      Paint()
        ..shader = ui.Gradient.linear(fadeRect.topCenter, fadeRect.bottomCenter, [AppColors.surface.withValues(alpha: 0), AppColors.surface]),
      );
    }
    final img = await rec.endRecording().toImage((w * scale).round(), (h * scale).round());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$file').writeAsBytesSync(png!.buffer.asUint8List());
  }

  testWidgets('render framing before/after', (tester) async {
    if (outDir == null) return;
    Directory(outDir).createSync(recursive: true);
    await tester.runAsync(() async {
      for (final coach in Coaches.all) {
        for (final s in screens.entries) {
          final w = s.value.$1 - 24;
          await render(coach, '${coach.id}-${s.key}-before.png', w, (w / 2.0).clamp(150.0, 240.0), 1.0);
          // The 4:5 avatar window of the conversation screen (no fade).
          final p = CoachStageAvatar.windowSize(w, screenHeight: s.value.$2);
          await render(coach, '${coach.id}-${s.key}-after.png', p.width, p.height, CoachStageAvatar.overscanFor(largeText: false), fade: false);
        }
      }
    });
  });
}
