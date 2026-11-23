// The voice stage keeps every coach's mouth in view: about 55% down the
// portrait and above the caption fade, on iPhone, at 2.0 text and on iPad.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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

  for (final coach in Coaches.all) {
    test('${coach.name}: mouth at 40-65% of the stage and the lower lip above the fade', () {
      final m = AvatarManifest.parse(coach.id, File('assets/avatar/${coach.id}/manifest.json').readAsStringSync());
      expect(m.mouth, isNotNull);
      final image = Size(m.width.toDouble(), m.height.toDouble());
      for (final e in layouts.entries) {
        final (w, large) = e.value;
        final h = CoachStageAvatar.stageHeight(w, largeText: large);
        final src = AvatarPainter.sourceRect(image, Size(w, h), m.mouth, coach.heroFocus);
        final mouth = (m.mouth!.dy - src.top) / src.height;
        final lowerLip = (m.mouth!.dy + 0.25 * m.mouthWidth! - src.top) / src.height;
        expect(mouth, inInclusiveRange(0.40, 0.65), reason: '${e.key}: mouth at $mouth');
        expect(lowerLip, lessThan(CoachStageAvatar.fadeStart), reason: '${e.key}: lower lip at $lowerLip');
        // The whole box stays inside the portrait (no empty edges).
        expect(src.left >= -1e-6 && src.top >= -1e-6, isTrue);
        expect(src.right <= image.width + 1e-6 && src.bottom <= image.height + 1e-6, isTrue);
        expect(src.width / src.height, closeTo(w / h, 1e-6));
      }
    });
  }

  test('the stage height follows its width, within limits', () {
    expect(CoachStageAvatar.stageHeight(369, largeText: false), closeTo(184.5, 0.01));
    expect(CoachStageAvatar.stageHeight(616, largeText: false), 240);
    expect(CoachStageAvatar.stageHeight(280, largeText: false), 150);
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
}
