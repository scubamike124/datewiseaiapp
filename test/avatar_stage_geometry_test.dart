// The voice stage keeps every coach's brows, eyes and mouth in view: the
// mouth about 66% down the stage and above the caption fade, on iPhone, at 2.0 text and on iPad.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/avatar_animator.dart' show AvatarPose;
import 'package:datewise_ai/avatar/avatar_frames.dart';
import 'package:datewise_ai/avatar/coach_stage_avatar.dart';
import 'package:datewise_ai/avatar/talking_avatar.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/widgets/dw.dart';

import 'helpers.dart';

/// Speech that is available and does nothing (opens voice mode).
class _Speech implements SpeechService {
  @override
  bool get available => true;
  @override
  bool get permissionDenied => false;
  @override
  bool get canOpenSettings => false;
  @override
  Future<void> openSettings() async {}
  @override
  Future<bool> ensureReady() async => true;
  @override
  Future<void> recheckPermission() async {}
  @override
  Future<SpeechStart> start({
    required String localeId,
    List<String> fallbackLocales = const [],
    required void Function(String words) onWords,
    void Function()? onUnsupported,
    void Function(String words)? onEnded,
  }) async =>
      SpeechStart.started;
  @override
  Future<String> stop() async => '';
  @override
  Future<void> cancel() async {}
}

void main() {
  // Stage widths: the screen (capped at kContentMaxWidth) minus the
  // stage's 12 pt margins on each side.
  double stageWidth(double screen) => (screen < kContentMaxWidth ? screen : kContentMaxWidth) - 24;
  final layouts = {
    'iPhone SE': (stageWidth(375), false),
    'iPhone 16': (stageWidth(393), false),
    'iPhone 16 at 2.0 text': (stageWidth(393), true),
    'iPhone SE at 2.0 text': (stageWidth(375), true),
    'iPad': (stageWidth(1024), false),
    'iPad at 2.0 text': (stageWidth(1024), true),
  };

  // iPhone SE, iPhone 15 and iPhone 15 Pro Max screen widths (pt).
  // name: (screen width, screen height).
  const phones = {
    'iPhone SE': (375.0, 667.0),
    'iPhone 12 mini': (360.0, 780.0),
    'iPhone 15': (393.0, 852.0),
    'iPhone 15 Pro Max': (430.0, 932.0),
  };
  // The brow's reach above the eye patch's top, as a fraction of its height.
  const browMargin = 0.1;

  for (final coach in Coaches.all) {
    test('${coach.name}: mouth at 40-70% of the stage and the lower lip above the fade', () {
      final m = AvatarManifest.parse(coach.id, File('assets/avatar/${coach.id}/manifest.json').readAsStringSync());
      expect(m.mouth, isNotNull);
      final image = Size(m.width.toDouble(), m.height.toDouble());
      for (final e in layouts.entries) {
        final (w, large) = e.value;
        final p = CoachStageAvatar.portraitSize(w, largeText: large);
        final h = p.height;
        final k = CoachStageAvatar.overscanFor(largeText: large);
        final src = AvatarPainter.sourceRect(image, Size(p.width, h * k), m.mouth, coach.heroFocus);
        // Fractions of the visible stage (the portrait box is k times taller).
        final mouth = (m.mouth!.dy - src.top) / src.height * k;
        final lowerLip = (m.mouth!.dy + 0.25 * m.mouthWidth! - src.top) / src.height * k;
        expect(mouth, inInclusiveRange(0.40, 0.70), reason: '${e.key}: mouth at $mouth');
        expect(lowerLip, lessThan(CoachStageAvatar.fadeStart), reason: '${e.key}: lower lip at $lowerLip');
        // The whole box stays inside the portrait (no empty edges).
        expect(src.left >= -1e-6 && src.top >= -1e-6, isTrue);
        expect(src.right <= image.width + 1e-6 && src.bottom <= image.height + 1e-6, isTrue);
        expect(src.width / src.height, closeTo(p.width / (h * k), 1e-6));
      }
    });

    test('${coach.name}: the brows, eyes and chin are inside the stage at text 1.0, 1.5 and 2.0 and on every phone', () {
      final manifest = AvatarManifest.parse(coach.id, File('assets/avatar/${coach.id}/manifest.json').readAsStringSync());
      final image = Size(manifest.width.toDouble(), manifest.height.toDouble());
      final eyes = manifest.patches['gaze']!.rect;
      expect(manifest.patches['gaze']!.region, AvatarRegion.eyes);
      for (final e in phones.entries) {
        for (final scale in const [1.0, 1.5, 2.0]) {
          final w = stageWidth(e.value.$1);
          final p = CoachStageAvatar.portraitSize(w, largeText: scale > 1.3, screenHeight: e.value.$2);
          final h = p.height;
          final box = Size(p.width, h * CoachStageAvatar.overscanFor(largeText: scale > 1.3));
          final src = AvatarPainter.sourceRect(image, box, manifest.mouth, coach.heroFocus);
          // Portrait y -> stage y (pt), as the painter draws it: the zoom
          // about the portrait box's center and the largest head motion.
          final z = AvatarPainter.coverZoom(box);
          double stageY(double y) => box.height / 2 + ((y - src.top) / src.height * box.height - box.height / 2) * z;
          final brow = stageY(eyes.top - browMargin * eyes.height) - AvatarPose.maxDy;
          final chin = stageY(manifest.mouth!.dy + 0.65 * manifest.mouthWidth!) + AvatarPose.maxDy;
          final why = '${e.key} x$scale';
          expect(brow, greaterThanOrEqualTo(-2), reason: '$why: brow at ${(brow / h * 100).toStringAsFixed(1)}% of the stage');
          expect(chin, lessThan(h), reason: '$why: chin at ${(chin / h * 100).toStringAsFixed(1)}%');
          // The eye patch (blink and gaze) is wholly visible.
          expect(stageY(eyes.top), greaterThan(0), reason: why);
          expect(stageY(eyes.bottom), lessThan(h * CoachStageAvatar.fadeStart), reason: why);
        }
      }
    });
  }

  test('the portrait box keeps the normal-text proportions, and is never taller than the old stage', () {
    for (final w in [351.0, 369.0, 406.0, 616.0]) {
      final full = CoachStageAvatar.stageHeight(w, largeText: false);
      for (final screen in [375.0, 667.0, 780.0, 852.0, 932.0, 1366.0]) {
        for (final large in [false, true]) {
          final p = CoachStageAvatar.portraitSize(w, largeText: large, screenHeight: screen);
          expect(p.width, lessThanOrEqualTo(w));
          expect(p.height / p.width, closeTo(full / w, 1e-9), reason: 'w=$w screen=$screen large=$large');
          // Before the framing change the stage was half the width, 150-240 pt:
          // the conversation keeps at least that room.
          if (!large) expect(p.height, lessThanOrEqualTo((w / 2).clamp(150.0, 240.0) + 1e-9));
        }
      }
    }
    // iPhone SE: 26% of the screen; the others: the old stage height.
    expect(CoachStageAvatar.portraitSize(351, largeText: false, screenHeight: 667).height, closeTo(667 * 0.26, 0.01));
    expect(CoachStageAvatar.portraitSize(369, largeText: false, screenHeight: 852).height, closeTo(184.5, 0.01));
    expect(CoachStageAvatar.portraitSize(336, largeText: false, screenHeight: 780).height, closeTo(168, 0.01));
    // Large text on a short screen stays within the old 18% cap, face whole.
    expect(CoachStageAvatar.portraitSize(351, largeText: true, screenHeight: 667).height + 2, lessThanOrEqualTo(667 * 0.18 + 1e-9));
  });

  test('the stage height follows its width, within limits', () {
    expect(CoachStageAvatar.stageHeight(369, largeText: false), closeTo(221.4, 0.01));
    expect(CoachStageAvatar.stageHeight(616, largeText: false), 250);
    expect(CoachStageAvatar.stageHeight(200, largeText: false), 150);
    expect(CoachStageAvatar.stageHeight(369, largeText: true), inInclusiveRange(130, 170));
    expect(CoachStageAvatar.fadeStart, greaterThanOrEqualTo(0.85));
  });

  for (final (name, size, scale) in const [
    ('iPhone', Size(390, 844), 1.0),
    ('iPhone at 2.0 text', Size(390, 844), 2.0),
    ('iPad', Size(1024, 1366), 1.0),
  ]) {
    testWidgets('$name: the real voice stage has the width-based height and the low fade', (t) async {
      await pumpApp(t, size: size, scale: scale, prefs: onboardedPrefs(), tab: AppTab.chat, speech: _Speech());
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('voice-mode')));
      await t.pumpAndSettle();
      final box = t.getSize(find.byType(CoachStageAvatar));
      final stage = (size.width < kContentMaxWidth ? size.width : kContentMaxWidth) - 26;
      final want = CoachStageAvatar.portraitSize(stage, largeText: scale > 1.3, screenHeight: size.height);
      expect(box.height, closeTo(want.height, 0.5));
      expect(box.width, closeTo(want.width, 0.5));
      final fade = t.widget<FadeToBackground>(find.byType(FadeToBackground).last);
      expect(fade.stops.first, CoachStageAvatar.fadeStart);
      expect(t.takeException(), isNull);
    });
  }

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
