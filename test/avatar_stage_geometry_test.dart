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
  const phones = {'iPhone SE': 375.0, 'iPhone 15': 393.0, 'iPhone 15 Pro Max': 430.0};
  // The brow's reach above the eye patch's top, as a fraction of its height.
  const browMargin = 0.1;

  for (final coach in Coaches.all) {
    test('${coach.name}: mouth at 40-70% of the stage and the lower lip above the fade', () {
      final m = AvatarManifest.parse(coach.id, File('assets/avatar/${coach.id}/manifest.json').readAsStringSync());
      expect(m.mouth, isNotNull);
      final image = Size(m.width.toDouble(), m.height.toDouble());
      for (final e in layouts.entries) {
        final (w, large) = e.value;
        final h = CoachStageAvatar.stageHeight(w, largeText: large);
        final k = CoachStageAvatar.overscanFor(largeText: large);
        final src = AvatarPainter.sourceRect(image, Size(w, h * k), m.mouth, coach.heroFocus);
        // Fractions of the visible stage (the portrait box is k times taller).
        final mouth = (m.mouth!.dy - src.top) / src.height * k;
        final lowerLip = (m.mouth!.dy + 0.25 * m.mouthWidth! - src.top) / src.height * k;
        expect(mouth, inInclusiveRange(0.40, 0.70), reason: '${e.key}: mouth at $mouth');
        expect(lowerLip, lessThan(CoachStageAvatar.fadeStart), reason: '${e.key}: lower lip at $lowerLip');
        // The whole box stays inside the portrait (no empty edges).
        expect(src.left >= -1e-6 && src.top >= -1e-6, isTrue);
        expect(src.right <= image.width + 1e-6 && src.bottom <= image.height + 1e-6, isTrue);
        expect(src.width / src.height, closeTo(w / (h * k), 1e-6));
      }
    });

    test('${coach.name}: the brows (top of the eye patch less a margin) and the chin are inside the stage', () {
      final manifest = AvatarManifest.parse(coach.id, File('assets/avatar/${coach.id}/manifest.json').readAsStringSync());
      final image = Size(manifest.width.toDouble(), manifest.height.toDouble());
      final eyes = manifest.patches['gaze']!.rect;
      expect(manifest.patches['gaze']!.region, AvatarRegion.eyes);
      for (final e in phones.entries) {
        final w = stageWidth(e.value);
        final h = CoachStageAvatar.stageHeight(w, largeText: false);
        final k = CoachStageAvatar.overscanFor(largeText: false);
        final box = Size(w, h * k);
        final src = AvatarPainter.sourceRect(image, box, manifest.mouth, coach.heroFocus);
        // Portrait y -> stage y (pt), as the painter draws it: the zoom
        // about the portrait box's center and the largest head motion.
        final z = AvatarPainter.coverZoom(box);
        double stageY(double y) => box.height / 2 + ((y - src.top) / src.height * box.height - box.height / 2) * z;
        final brow = stageY(eyes.top - browMargin * eyes.height) - AvatarPose.maxDy;
        final chin = stageY(manifest.mouth!.dy + 0.65 * manifest.mouthWidth!) + AvatarPose.maxDy;
        expect(brow, greaterThanOrEqualTo(0), reason: '${e.key}: brow at ${(brow / h * 100).toStringAsFixed(1)}% of the stage');
        expect(chin, lessThan(h), reason: '${e.key}: chin at ${(chin / h * 100).toStringAsFixed(1)}%');
        // The eye patch (blink and gaze) is wholly visible.
        expect(stageY(eyes.top), greaterThan(0));
        expect(stageY(eyes.bottom), lessThan(h * CoachStageAvatar.fadeStart));
      }
    });
  }

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
      final portrait = find.ancestor(of: find.byType(CoachStageAvatar), matching: find.byType(SizedBox)).first;
      final box = t.getSize(portrait);
      expect(box.height, closeTo(CoachStageAvatar.stageHeight(box.width, largeText: scale > 1.3), 0.5));
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
