import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/coach_clips.dart';
import 'package:datewise_ai/models/coach.dart';

void main() {
  test('every coach has an approved reference clip in the coach\'s own language', () {
    for (final coach in Coaches.all) {
      final clip = CoachClips.referenceFor(coach.id);
      expect(clip, isNotNull, reason: '${coach.id} has no reference clip');
      expect(clip!.language, coach.language, reason: '${coach.id} clip language must match the coach');
    }
  });

  test('Ava\'s reference is the approved ten-second clip; Spanish coaches are Spanish', () {
    expect(CoachClips.referenceFor('ava')!.seconds, 10.0);
    expect(CoachClips.referenceFor('diego')!.language, CoachLanguage.es);
    expect(CoachClips.referenceFor('sofia')!.language, CoachLanguage.es);
    expect(CoachClips.referenceFor('ethan')!.language, CoachLanguage.en);
  });

  test('every clip file is bundled with the app and declared in pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/coach_clips/'));
    for (final clip in CoachClips.all) {
      expect(File(clip.asset).existsSync(), isTrue, reason: '${clip.asset} is missing');
    }
    expect(File(CoachClips.posterAsset).existsSync(), isTrue);
  });

  test('no clip is played twice: the Spanish clips are used at normal speed', () {
    // The 15% slowdown is already baked into the approved Spanish MP4s; the player never changes rate.
    final player = File('lib/widgets/coach_clip_player.dart').readAsStringSync();
    expect(player.contains('setPlaybackSpeed'), isFalse);
  });
}
