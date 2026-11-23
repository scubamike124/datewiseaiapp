// ignore_for_file: invalid_use_of_visible_for_testing_member
// Offline demo renderer: draws the talking avatar with the app's own code
// (AvatarFrames, AvatarAnimator, VisemeTimeline, AvatarPainter) into PNG
// frames, for muxing with the demo audio. Not part of `flutter test`'s
// default run (it lives under tool/ and needs AVATAR_DEMO_JOBS).
//
//   AVATAR_DEMO_JOBS=<dir with *.json jobs> AVATAR_DEMO_OUT=<dir> \
//     flutter test tool/avatar/render_demo_test.dart
//
// A job (tool/avatar/README.md) has the coach, language, text, audio length
// and per-word start/end times (what iOS reports through word callbacks).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/avatar_animator.dart';
import 'package:datewise_ai/avatar/avatar_frames.dart';
import 'package:datewise_ai/avatar/lip_sync.dart';
import 'package:datewise_ai/avatar/talking_avatar.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/services/voice_service.dart';

void main() {
  final jobsDir = Platform.environment['AVATAR_DEMO_JOBS'];
  final outDir = Platform.environment['AVATAR_DEMO_OUT'];
  const fps = 30;
  const w = 960, h = 540;
  const lead = 0.8, tail = 0.8;

  testWidgets('render avatar demo frames', (tester) async {
    if (jobsDir == null || outDir == null) return;
    final jobs = Directory(jobsDir).listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final only = Platform.environment['AVATAR_DEMO_ONLY'];
    await tester.runAsync(() async {
      for (final jf in jobs) {
        final job = jsonDecode(jf.readAsStringSync()) as Map<String, dynamic>;
        final name = jf.uri.pathSegments.last.replaceAll('.json', '');
        if (only != null && !name.startsWith(only)) continue;
        final coach = Coaches.all.firstWhere((c) => c.id == job['coach']);
        final lang = CoachLanguage.fromCode(job['language'] as String);
        final text = job['text'] as String;
        final words = [
          for (final x in job['words'] as List)
            ((x['charStart'] as num).toInt(), (x['charEnd'] as num).toInt(), (x['start'] as num).toDouble(), (x['end'] as num).toDouble()),
        ];
        final timeline = VisemeTimeline.fromTimedWords(text, lang, words);
        final planned = VisemeTimeline.plan(text, lang, rate: 0.5);
        final frames = (await AvatarFrames.load(coach))!;
        final animator = AvatarAnimator(seed: name.hashCode);
        final pose = ValueNotifier(AvatarPose.still);
        final painter = AvatarPainter(frames, pose, coach.heroFocus);
        final dir = Directory('$outDir/$name')..createSync(recursive: true);
        final duration = (job['duration'] as num).toDouble();
        final total = ((lead + duration + tail) * fps).ceil();
        final sw = Stopwatch()..start();
        var paintMicros = 0;
        // The app's own LipSyncDriver on a simulated clock, fed like the app:
        //  audio   = the native audio path on iOS 15/16 (loudness only),
        //  markers = the native audio path on iOS 17 (loudness + word markers),
        //  words   = the flutter_tts fallback (word-start events, no loudness).
        final mode = Platform.environment['AVATAR_DEMO_MODE'] ?? 'audio';
        // Measurement runs only need the shown shapes, not the images.
        final noPng = Platform.environment['AVATAR_DEMO_NO_PNG'] != null;
        var clock = Duration.zero;
        final driver = LipSyncDriver(clock: () => clock);
        final profile = CoachVoiceProfile.of(coach);
        driver.begin(text, lang, rate: profile.rate);
        var started = false;
        var nextWord = 0;
        final shown = <List<Object>>[]; // [audio time, shape, jaw] per frame
        for (var f = 0; f < total; f++) {
          final t = f / fps;
          final st = t - lead;
          clock = Duration(microseconds: (st * 1e6).round());
          if (!started && st >= 0) {
            driver.started();
            started = true;
            if (mode != 'words') {
              final levels = [for (final v in job['levels'] as List) (v as num).toDouble()];
              driver.addLevels(0, (job['levels_hop'] as num).toDouble(), levels);
              // Synthesis is faster than playback: all levels are in before
              // the first word is heard.
              driver.audioComplete();
            }
            if (mode == 'markers') {
              for (final (cs, _, ws, _) in words) {
                driver.addMarker(cs, ws);
              }
            }
          }
          if (mode == 'words') {
            while (started && nextWord < words.length && words[nextWord].$3 <= st) {
              driver.word(words[nextWord].$1, words[nextWord].$2);
              nextWord++;
            }
          }
          if (started && st >= duration) driver.end();
          final speaking = driver.active;
          final mood = speaking ? AvatarMood.speaking : AvatarMood.idle;
          // No offset of its own: frame f is shown at f / fps and the audio
          // starts at `lead` s; the driver applies VisemeTimeline.lead.
          final mouth = speaking ? driver.sample() : VisemeSample.rest;
          final jaw = speaking ? driver.jaw() : 0.0;
          shown.add([st, mouth.viseme.name, jaw]);
          pose.value = animator.frame(t, mood, mouth, available: frames.images.keys.toSet(), jaw: jaw);
          final rec = ui.PictureRecorder();
          final p0 = sw.elapsedMicroseconds;
          painter.paint(Canvas(rec), const Size(w * 1.0, h * 1.0));
          paintMicros += sw.elapsedMicroseconds - p0;
          if (noPng) {
            rec.endRecording().dispose();
            continue;
          }
          final img = await rec.endRecording().toImage(w, h);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/f${f.toString().padLeft(5, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
          img.dispose();
        }
        File('$outDir/$name${noPng ? '.$mode' : ''}.cues.json').writeAsStringSync(jsonEncode({
          'lead': lead,
          'lead_visemes': VisemeTimeline.lead,
          'mode': mode,
          'shown': shown,
          'anchored': [for (final c in timeline.cues) [c.viseme.name, c.start, c.end]],
          'planned': [for (final c in planned.cues) [c.viseme.name, c.start, c.end]],
        }));
        // ignore: avoid_print
        print('$name: $total frames, painter ${(paintMicros / total).toStringAsFixed(0)} µs/frame (host CPU, picture recording)');
      }
    });
  }, timeout: const Timeout(Duration(minutes: 60)));

  // Listening (nods), thinking and idle, 3 s each, per coach (no audio).
  testWidgets('render avatar state demo frames', (tester) async {
    if (outDir == null || Platform.environment['AVATAR_DEMO_STATES'] == null) return;
    await tester.runAsync(() async {
      for (final coach in Coaches.all) {
        final frames = (await AvatarFrames.load(coach))!;
        final animator = AvatarAnimator(seed: coach.id.hashCode);
        final pose = ValueNotifier(AvatarPose.still);
        final painter = AvatarPainter(frames, pose, coach.heroFocus);
        final dir = Directory('$outDir/states-${coach.id}')..createSync(recursive: true);
        for (var f = 0; f < 9 * fps; f++) {
          final t = f / fps;
          final mood = t < 3 ? AvatarMood.listening : t < 6 ? AvatarMood.thinking : AvatarMood.idle;
          pose.value = animator.frame(t, mood, VisemeSample.rest, available: frames.images.keys.toSet());
          final rec = ui.PictureRecorder();
          painter.paint(Canvas(rec), const Size(w * 1.0, h * 1.0));
          final img = await rec.endRecording().toImage(w, h);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/f${f.toString().padLeft(5, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
          img.dispose();
        }
      }
    });
  }, timeout: const Timeout(Duration(minutes: 30)));
}
