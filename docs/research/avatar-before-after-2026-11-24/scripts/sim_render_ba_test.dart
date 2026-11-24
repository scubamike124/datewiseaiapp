// QA SIMULATION renderer (not part of the repo). Draws the talking avatar with
// the app's own code (AvatarFrames, AvatarAnimator, LipSyncDriver on the native
// audio path = loudness, AvatarPainter) at the iPhone voice-stage size
// (390 x 195 pt at 3x = 1170 x 585 px), with listening / thinking / idle /
// speaking moods taken from a dialogue timeline.
//
//   QA_JOBS=<dir> QA_OUT=<dir> flutter test <this file>
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/avatar_animator.dart';
import 'package:datewise_ai/avatar/avatar_frames.dart';
import 'package:datewise_ai/avatar/coach_stage_avatar.dart';
import 'package:datewise_ai/avatar/lip_sync.dart';
import 'package:datewise_ai/avatar/talking_avatar.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/services/voice_service.dart';
import 'package:datewise_ai/theme/app_theme.dart';

void main() {
  final jobsDir = Platform.environment['QA_JOBS'];
  final outDir = Platform.environment['QA_OUT'];
  const fps = 30;
  const dpr = 3.0;
  // iPhone 15 (393 pt) voice stage = screen minus 12 pt padding each side.
  const stageW = 369.0;
  final stageH = CoachStageAvatar.stageHeight(stageW, largeText: false);
  // Portrait overscan: 1.0 = before, 1.2 = after (CoachStageAvatar.portraitOverscan on the candidate).
  final k = double.parse(Platform.environment['QA_K'] ?? '1.0');

  testWidgets('qa simulation render', (tester) async {
    if (jobsDir == null || outDir == null) return;
    final only = Platform.environment['QA_ONLY'];
    final jobs = Directory(jobsDir).listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    await tester.runAsync(() async {
      for (final jf in jobs) {
        final name = jf.uri.pathSegments.last.replaceAll('.json', '');
        if (only != null && !name.startsWith(only)) continue;
        final job = jsonDecode(jf.readAsStringSync()) as Map<String, dynamic>;
        final coach = Coaches.all.firstWhere((c) => c.id == job['coach']);
        final lang = CoachLanguage.fromCode(job['language'] as String);
        final frames = (await AvatarFrames.load(coach))!;
        final animator = AvatarAnimator(seed: 12345);
        final pose = ValueNotifier(AvatarPose.still);
        final painter = AvatarPainter(frames, pose, coach.heroFocus);
        final profile = CoachVoiceProfile.of(coach);
        final dir = Directory('$outDir/$name')..createSync(recursive: true);
        final duration = (job['duration'] as num).toDouble();
        final segs = (job['segments'] as List).cast<Map<String, dynamic>>();
        final total = (duration * fps).round();
        final pxW = (stageW * dpr).round(), pxH = (stageH * dpr).round();
        var clock = Duration.zero;
        LipSyncDriver? driver;
        Map<String, dynamic>? driverSeg;
        final log = <Map<String, Object?>>[];
        for (var f = 0; f < total; f++) {
          final t = f / fps;
          clock = Duration(microseconds: (t * 1e6).round());
          var mood = AvatarMood.idle;
          Map<String, dynamic>? cur;
          for (final s in segs) {
            if (t >= (s['start'] as num) && t < (s['end'] as num)) cur = s;
          }
          if (cur != null && cur['mood'] == 'speaking') {
            if (!identical(cur, driverSeg)) {
              driver?.end();
              driverSeg = cur;
              driver = LipSyncDriver(clock: () => clock);
              driver.begin(cur['text'] as String, lang, rate: profile.rate);
              driver.started();
              driver.addLevels(0, (cur['levels_hop'] as num).toDouble(), [for (final v in cur['levels'] as List) (v as num).toDouble()]);
              driver.audioComplete();
            }
          } else if (driver != null) {
            driver.end();
            driver = null;
            driverSeg = null;
          }
          if (cur != null) {
            mood = switch (cur['mood']) {
              'listening' => AvatarMood.listening,
              'thinking' => AvatarMood.thinking,
              'speaking' => (driver?.active ?? false) ? AvatarMood.speaking : AvatarMood.idle,
              _ => AvatarMood.idle,
            };
          }
          final speaking = mood == AvatarMood.speaking;
          final mouth = speaking ? driver!.sample() : VisemeSample.rest;
          final jaw = speaking ? driver!.jaw() : 0.0;
          final p = animator.frame(t, mood, mouth, available: frames.images.keys.toSet(), jaw: jaw);
          pose.value = p;
          log.add({
            't': t,
            'mood': mood.name,
            'mouth': mouth.viseme.name,
            'jaw': jaw,
            'layers': [for (final l in p.layers) '${l.patch}@${l.opacity.toStringAsFixed(2)}'],
            'dx': p.dx,
            'dy': p.dy,
            'rot': p.rotation,
          });
          final rec = ui.PictureRecorder();
          final canvas = Canvas(rec);
          canvas.scale(dpr);
          canvas.clipRect(Rect.fromLTWH(0, 0, stageW, stageH));
          painter.paint(canvas, Size(stageW, stageH * k));
          final fade = Rect.fromLTWH(0, stageH * CoachStageAvatar.fadeStart, stageW, stageH * (1 - CoachStageAvatar.fadeStart));
          canvas.drawRect(fade, Paint()..shader = ui.Gradient.linear(fade.topCenter, fade.bottomCenter, [AppColors.surface.withValues(alpha: 0), AppColors.surface]));
          final img = await rec.endRecording().toImage(pxW, pxH);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/f${f.toString().padLeft(5, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
          img.dispose();
        }
        File('$outDir/$name.log.json').writeAsStringSync(jsonEncode({'stage': [stageW, stageH, dpr, k], 'frames': log}));
        // ignore: avoid_print
        print('$name: $total frames ${pxW}x$pxH');
      }
    });
  }, timeout: const Timeout(Duration(minutes: 90)));
}
