// Talking avatar widget: frame preloading for all four coaches, the
// animator's states, Reduce Motion fallback, accessibility labels, the
// voice-stage hook, and a painter frame-time benchmark.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/avatar_animator.dart';
import 'package:datewise_ai/avatar/avatar_frames.dart';
import 'package:datewise_ai/avatar/coach_stage_avatar.dart';
import 'package:datewise_ai/avatar/lip_sync.dart';
import 'package:datewise_ai/avatar/premium_voice_tip.dart';
import 'package:datewise_ai/avatar/talking_avatar.dart';
import 'package:datewise_ai/avatar/viseme.dart';
import 'package:datewise_ai/l10n/app_localizations.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/widgets/dw.dart';

Widget host(Widget child, {Locale locale = const Locale('en'), bool disableAnimations = false}) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), disableAnimations: disableAnimations),
        child: Center(child: SizedBox(width: 366, height: 170, child: child)),
      ),
    );

/// Decodes a coach's frames for real (outside the fake-async test zone), so
/// the widget then finds them already loaded.
Future<void> preload(WidgetTester tester, Coach coach) async {
  await tester.runAsync(() => AvatarFrames.acquire(coach));
}

/// Lets the widget pick up the preloaded frames and start animating.
Future<void> settleFrames(WidgetTester tester) async {
  // The cached future completed in the real zone; let its callbacks run.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  setUp(AvatarFrames.clearCache);

  group('generated frames', () {
    for (final coach in Coaches.all) {
      testWidgets('${coach.name}: manifest matches the portrait, every core patch decodes', (tester) async {
        final f = await tester.runAsync(() => AvatarFrames.load(coach));
        expect(f, isNotNull, reason: 'run tool/avatar/regenerate.sh after changing ${coach.heroAsset}');
        expect((f!.base.width, f.base.height), (f.manifest.width, f.manifest.height));
        // The mouth must at least open, close and round; blinks must exist.
        for (final n in [
          for (final v in Viseme.values)
            if (v.asset != null) v.asset!,
          'blink_half',
          'blink_closed',
          'gaze',
        ]) {
          expect(f.images.containsKey(n), isTrue, reason: '${coach.id}/$n');
        }
        for (final p in f.manifest.patches.values) {
          final img = f.images[p.name]!;
          expect((img.width, img.height), (p.rect.width.round(), p.rect.height.round()), reason: p.name);
          expect(p.rect.right <= f.manifest.width && p.rect.bottom <= f.manifest.height, isTrue);
        }
        // Mouth and eye patches never overlap where their masks are active:
        // the eye box ends above the mouth box's center.
        final mouth = f.manifest.patches['mbp']!.rect, eyes = f.manifest.patches['blink_half']!.rect;
        expect(eyes.center.dy, lessThan(mouth.top));
        expect(f.manifest.patches.values.where((p) => p.region == AvatarRegion.head), isEmpty,
            reason: 'head motion is a transform, never a warped frame');
        expect(avatarMemoryBytes(f), lessThan(20 * 1024 * 1024));
      });
    }
  });

  group('animator', () {
    test('blinks switch frames (never fade) and last 150 ms', () {
      expect(AvatarAnimator.blinkFrame(-0.01), isNull);
      expect(AvatarAnimator.blinkFrame(0.02), 'blink_half');
      expect(AvatarAnimator.blinkFrame(0.07), 'blink_closed');
      expect(AvatarAnimator.blinkFrame(0.12), 'blink_half');
      expect(AvatarAnimator.blinkFrame(0.15), isNull);
      final a = AvatarAnimator();
      for (var t = 0.0; t < 30; t += 1 / 60) {
        for (final l in a.frame(t, AvatarMood.idle, VisemeSample.rest).layers) {
          if (l.patch.startsWith('blink')) expect(l.opacity, 1);
        }
      }
    });

    test('some blinks are double blinks', () {
      final a = AvatarAnimator(seed: 1);
      final starts = <double>[];
      var was = false;
      for (var t = 0.0; t < 120; t += 1 / 60) {
        final b = a.frame(t, AvatarMood.idle, VisemeSample.rest).layers.any((l) => l.patch.startsWith('blink'));
        if (b && !was) starts.add(t);
        was = b;
      }
      final gaps = [for (var k = 1; k < starts.length; k++) starts[k] - starts[k - 1]];
      expect(gaps.where((g) => g < 0.5), isNotEmpty, reason: 'double blinks');
      expect(gaps.where((g) => g >= 2), isNotEmpty, reason: 'mostly single blinks seconds apart');
    });

    test('speaking draws the crossfaded mouth; thinking glances aside with lips closed', () {
      final a = AvatarAnimator();
      final p = a.frame(0.5, AvatarMood.speaking, const VisemeSample(Viseme.e, Viseme.a, 0.4));
      expect(p.layers.where((l) => !l.patch.startsWith('blink')), [const AvatarLayer('e', 1), const AvatarLayer('a', 0.4)]);
      final b = AvatarAnimator();
      var think = AvatarPose.still;
      for (var t = 1.0; t < 1.4; t += 1 / 60) {
        think = b.frame(t, AvatarMood.thinking, VisemeSample.rest);
      }
      expect(think.layers.map((l) => l.patch), containsAll(['gaze', 'mbp']));
      expect(think.layers.every((l) => l.opacity == 1), isTrue);
      expect(think.rotation.abs(), greaterThan(0.005), reason: 'slight head tilt while thinking');
    });

    test('listening nods are 400 ms whole-image bumps (3 px, under 1 degree); motion stays subtle', () {
      final a = AvatarAnimator();
      var nodFrames = 0;
      var maxDy = 0.0, maxRot = 0.0;
      for (var t = 0.0; t < 20; t += 1 / 60) {
        final p = a.frame(t, AvatarMood.listening, VisemeSample.rest);
        expect(p.layers.where((l) => !l.patch.startsWith('blink')), isEmpty, reason: 'no warped head frames');
        if (p.dy > 2.5) nodFrames++;
        maxDy = math.max(maxDy, p.dy.abs());
        maxRot = math.max(maxRot, p.rotation.abs());
        expect(p.scale, inInclusiveRange(1.04, 1.06));
      }
      expect(maxDy, inInclusiveRange(2.5, 4.5));
      expect(maxRot, lessThan(1 * math.pi / 180));
      expect(nodFrames, greaterThan(5), reason: 'nods happen');
      expect(nodFrames, lessThan(20 * 60 * 0.25), reason: 'nods are short, not held');
    });

    test('a phrase start after a pause gets a small nod', () {
      final a = AvatarAnimator();
      for (var t = 0.0; t < 1; t += 1 / 60) {
        a.frame(t, AvatarMood.speaking, VisemeSample.rest);
      }
      var maxDy = 0.0;
      for (var t = 1.0; t < 1.5; t += 1 / 60) {
        maxDy = math.max(maxDy, a.frame(t, AvatarMood.speaking, const VisemeSample(Viseme.e, Viseme.e, 1)).dy);
      }
      expect(maxDy, greaterThan(2));
    });

    test('a missing patch is skipped, never drawn', () {
      final a = AvatarAnimator();
      final p = a.frame(0.5, AvatarMood.speaking, const VisemeSample(Viseme.o, Viseme.e, 1), available: {'mbp'});
      expect(p.layers.where((l) => !l.patch.startsWith('blink')), isEmpty);
    });

    test('mood follows the chat screen state', () {
      AvatarMood m({bool s = false, bool l = false, bool r = false}) =>
          CoachStageAvatar.moodFor(speaking: s, listening: l, responding: r);
      expect(m(), AvatarMood.idle);
      expect(m(l: true), AvatarMood.listening);
      expect(m(r: true), AvatarMood.thinking);
      expect(m(s: true, r: true), AvatarMood.speaking);
    });
  });

  group('widget', () {
    testWidgets('animated: painted portrait with an "animated AI coach" label per state (EN)', (tester) async {
      final lip = LipSyncDriver();
      await preload(tester, Coaches.ava);
      await tester.pumpWidget(host(CoachStageAvatar(coach: Coaches.ava, mood: AvatarMood.speaking, lipSync: lip)));
      await settleFrames(tester);
      expect(find.byKey(const ValueKey('talking-avatar-paint')), findsOneWidget);
      expect(find.bySemanticsLabel('Ava, animated AI coach, speaking'), findsOneWidget);
      await tester.pumpWidget(host(CoachStageAvatar(coach: Coaches.ava, mood: AvatarMood.listening, lipSync: lip)));
      expect(find.bySemanticsLabel('Ava, animated AI coach, listening'), findsOneWidget);
      await tester.pumpWidget(host(CoachStageAvatar(coach: Coaches.ava, mood: AvatarMood.thinking, lipSync: lip)));
      expect(find.bySemanticsLabel('Ava, animated AI coach, thinking'), findsOneWidget);
      await tester.pumpWidget(host(const CoachStageAvatar(coach: Coaches.ava, mood: AvatarMood.idle)));
      expect(find.bySemanticsLabel('Ava, animated AI coach'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('still portrait')), findsNothing);
      // The ticker keeps animating (blinks, breathing) without errors.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Spanish labels', (tester) async {
      await preload(tester, Coaches.sofia);
      await tester.pumpWidget(host(const CoachStageAvatar(coach: Coaches.sofia, mood: AvatarMood.speaking), locale: const Locale('es')));
      await settleFrames(tester);
      expect(find.bySemanticsLabel('Retrato animado de Sofía, coach con IA, hablando'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Reduce Motion: the still portrait, labeled as still, no animation', (tester) async {
      await preload(tester, Coaches.diego);
      await tester.pumpWidget(host(const CoachStageAvatar(coach: Coaches.diego, mood: AvatarMood.speaking), disableAnimations: true));
      await settleFrames(tester);
      expect(find.byKey(const ValueKey('talking-avatar-paint')), findsNothing);
      expect(find.byType(CoachImage), findsOneWidget);
      expect(find.bySemanticsLabel('Diego, AI coach (still portrait)'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'no ticker running');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Reduce Motion does not decode the frames at all', (tester) async {
      await tester.pumpWidget(host(const CoachStageAvatar(coach: Coaches.diego, mood: AvatarMood.idle), disableAnimations: true));
      await tester.pump();
      expect(AvatarFrames.heldCoach, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('frames of one coach at a time; disposed when the stage closes', (tester) async {
      await preload(tester, Coaches.ava);
      await tester.pumpWidget(host(const CoachStageAvatar(coach: Coaches.ava, mood: AvatarMood.idle)));
      await settleFrames(tester);
      final avaFrames = tester.state<TalkingAvatarState>(find.byType(TalkingAvatar)).frames!;
      AvatarFrames.release('ava'); // the preload's hold
      await preload(tester, Coaches.ethan);
      await tester.pumpWidget(host(const CoachStageAvatar(coach: Coaches.ethan, mood: AvatarMood.idle)));
      await settleFrames(tester);
      expect(AvatarFrames.heldCoach, 'ethan');
      expect(avaFrames.isDisposed, isTrue, reason: 'switching coach frees the previous images');
      final ethanFrames = tester.state<TalkingAvatarState>(find.byType(TalkingAvatar)).frames!;
      AvatarFrames.release('ethan');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      expect(ethanFrames.isDisposed, isTrue, reason: 'closing the voice stage frees them');
      expect(AvatarFrames.heldCoach, isNull);
    });

    testWidgets('closing the stage before the frames finish loading gives the hold back', (tester) async {
      await tester.pumpWidget(host(const CoachStageAvatar(coach: Coaches.sofia, mood: AvatarMood.idle)));
      expect(AvatarFrames.heldCoach, 'sofia');
      await tester.pumpWidget(const SizedBox());
      expect(AvatarFrames.heldCoach, isNull);
    });

    testWidgets('blinks keep coming after a Reduce Motion round trip', (tester) async {
      Widget app(bool reduce) => host(const CoachStageAvatar(coach: Coaches.ava, mood: AvatarMood.idle), disableAnimations: reduce);
      await preload(tester, Coaches.ava);
      await tester.pumpWidget(app(false));
      await settleFrames(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(app(true));
      await tester.pump(const Duration(seconds: 1));
      await preload(tester, Coaches.ava);
      await tester.pumpWidget(app(false));
      await settleFrames(tester);
      final st = tester.state<TalkingAvatarState>(find.byType(TalkingAvatar));
      var blinked = false;
      for (var i = 0; i < 8 * 30; i++) {
        await tester.pump(const Duration(milliseconds: 33));
        blinked |= st.pose.value.layers.any((l) => l.patch.startsWith('blink'));
      }
      expect(blinked, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('before the frames are decoded it shows the still portrait (no blank stage)', (tester) async {
      await tester.pumpWidget(host(const CoachStageAvatar(coach: Coaches.ethan, mood: AvatarMood.idle)));
      expect(find.byType(CoachImage), findsOneWidget);
      expect(find.byKey(const ValueKey('talking-avatar-paint')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  for (final (lang, title, path) in [
    ('en', 'Get more natural voices', 'Accessibility › Spoken Content › Voices'),
    ('es', 'Consigue voces más naturales', 'Accesibilidad › Contenido leído › Voces'),
  ]) {
    testWidgets('Premium-voice tip explains the iOS download path ($lang)', (tester) async {
      await tester.pumpWidget(host(Builder(
          builder: (c) => GestureDetector(onTap: () => showPremiumVoiceTip(c), child: const Text('open'))),
          locale: Locale(lang)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.textContaining(path), findsOneWidget);
      expect(find.textContaining('Premium'), findsOneWidget);
    });
  }

  testWidgets('benchmark: painter work per frame at iPhone stage size (3x)', (tester) async {
    final results = <String>[];
    await tester.runAsync(() async {
      for (final coach in Coaches.all) {
        final f = (await AvatarFrames.load(coach))!;
        results.add('${coach.id}: ${(avatarMemoryBytes(f) / 1048576).toStringAsFixed(1)} MB decoded');
        final pose = ValueNotifier(AvatarPose.still);
        final painter = AvatarPainter(f, pose, coach.heroFocus);
        final anim = AvatarAnimator();
        final tl = VisemeTimeline.plan('Hi, I am here to help you feel confident before your date tonight.', coach.language);
        const n = 600;
        final sw = Stopwatch();
        for (var i = 0; i < n; i++) {
          final t = i / 60;
          pose.value = anim.frame(t, AvatarMood.speaking, tl.sample(t % tl.duration), available: f.images.keys.toSet());
          final rec = ui.PictureRecorder();
          sw.start();
          final canvas = Canvas(rec)..scale(3);
          painter.paint(canvas, const Size(366, 170));
          final pic = rec.endRecording();
          sw.stop();
          pic.dispose();
        }
        final us = sw.elapsedMicroseconds / n;
        // Software rasterization of the same frame at 3x (1098x510 px) on the
        // host CPU: an upper bound; iPhones rasterize on the GPU.
        final rs = Stopwatch();
        for (var i = 0; i < 30; i++) {
          pose.value = anim.frame(10 + i / 60, AvatarMood.speaking, tl.sample(i / 60), available: f.images.keys.toSet());
          final rec = ui.PictureRecorder();
          final canvas = Canvas(rec)..scale(3);
          painter.paint(canvas, const Size(366, 170));
          final pic = rec.endRecording();
          rs.start();
          final img = await pic.toImage(1098, 510);
          rs.stop();
          img.dispose();
          pic.dispose();
        }
        results.add('${coach.id}: record ${us.toStringAsFixed(0)} µs, raster ${(rs.elapsedMicroseconds / 30000).toStringAsFixed(1)} ms');
        expect(us, lessThan(4000), reason: 'painter must stay far below the 16.7 ms (60 Hz) frame budget');
      }
    });
    // ignore: avoid_print
    print('Avatar painter (host CPU; raster = software toImage, upper bound): ${results.join(', ')}');
  });
}
