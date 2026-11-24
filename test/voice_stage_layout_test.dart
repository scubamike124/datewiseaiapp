// The real chat screen in voice mode: nothing is drawn over a coach's brows,
// eyes, mouth or chin (the timer and captions button sit below the portrait),
// the face is whole at every text size, and the talk dock stays above the
// keyboard. Geometry is measured from the rendered widgets.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/avatar/avatar_animator.dart' show AvatarPose;
import 'package:datewise_ai/avatar/avatar_frames.dart';
import 'package:datewise_ai/avatar/coach_stage_avatar.dart';
import 'package:datewise_ai/avatar/talking_avatar.dart';
import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/coach_usage.dart';
import 'package:datewise_ai/services/speech_service.dart';

import 'helpers.dart';

/// A header name is one 21 pt line (height 1.15) before scaling.
class AppFontsProbe {
  static const nameLineHeight = 21 * 1.15;
}

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

// name: (screen, status bar, home indicator).
const _devices = {
  'SE': (Size(375, 667), 20.0, 0.0),
  '12 mini': (Size(360, 780), 50.0, 34.0),
  '15': (Size(393, 852), 59.0, 34.0),
  'Pro Max': (Size(430, 932), 59.0, 34.0),
};

Future<void> _openVoice(WidgetTester t, Coach coach, Size size, double top, double bottom, double scale, {double keyboard = 0}) async {
  setSurface(t, size, scale);
  t.view.padding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
  t.view.viewPadding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
  addTearDown(t.view.resetPadding);
  addTearDown(t.view.resetViewPadding);
  final app = await makeState(prefs: onboardedPrefs(coach: coach.id));
  await t.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat), speech: _Speech()));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('voice-mode')));
  await t.pumpAndSettle();
  if (keyboard > 0) {
    t.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
  }
}

Rect _r(WidgetTester t, String key) => t.getRect(find.byKey(ValueKey(key)));

/// The app's real fonts (not the test font, whose glyphs are far wider), so
/// the measurements match a device.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
    }
    await loader.load();
  }

  await load('Inter', [for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Inter-$w.ttf']);
  await load('Newsreader', [for (final w in ['Regular', 'Medium', 'Italic']) 'assets/fonts/Newsreader-$w.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/root/fl/flutter';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await load('MaterialIcons', [icons.path]);
}

void main() {
  const browMargin = 0.1;
  setUpAll(_loadFonts);

  for (final coach in Coaches.all) {
    final manifest = AvatarManifest.parse(coach.id, File('assets/avatar/${coach.id}/manifest.json').readAsStringSync());
    final image = Size(manifest.width.toDouble(), manifest.height.toDouble());
    final eyes = manifest.patches['gaze']!.rect;

    for (final d in _devices.entries) {
      for (final scale in const [1.0, 1.5, 2.0]) {
        testWidgets('${coach.name} ${d.key} x$scale: the timer and captions button clear the brows, eyes and chin; the face is whole', (t) async {
          final (size, top, bottom) = d.value;
          await _openVoice(t, coach, size, top, bottom, scale);
          expect(t.takeException(), isNull);

          final portrait = t.getRect(find.byType(CoachStageAvatar));
          final viewport = t.getRect(find.byKey(const ValueKey('voice-stage-scroll')));
          // Face landmarks as painted (stage coordinates -> screen).
          final box = Size(portrait.width, portrait.height * CoachStageAvatar.overscanFor(largeText: scale > 1.3));
          final src = AvatarPainter.sourceRect(image, box, manifest.mouth, coach.heroFocus);
          final z = AvatarPainter.coverZoom(box);
          double y(double v) => portrait.top + box.height / 2 + ((v - src.top) / src.height * box.height - box.height / 2) * z;
          final brows = Rect.fromLTRB(portrait.left, y(eyes.top - browMargin * eyes.height) - AvatarPose.maxDy, portrait.right, y(eyes.top));
          final eyeBand = Rect.fromLTRB(portrait.left, y(eyes.top), portrait.right, y(eyes.bottom));
          final face = Rect.fromLTRB(portrait.left, brows.top, portrait.right, y(manifest.mouth!.dy + 0.65 * manifest.mouthWidth!) + AvatarPose.maxDy);

          final header = _r(t, 'chat-header');
          // The timer is left out only when it would break the coach's name
          // (large text on a narrow phone); the name then stays on one line.
          final hasTimer = find.byKey(const ValueKey('voice-timer')).evaluate().isNotEmpty;
          if (!hasTimer) expect(scale, greaterThan(1.3), reason: 'timer present at normal text');
          final nameLines = t.getRect(find.text(coach.name).first).height;
          expect(nameLines, lessThan(AppFontsProbe.nameLineHeight * scale * 1.6), reason: 'the coach name stays on one line');
          final timer = hasTimer ? _r(t, 'voice-timer') : Rect.fromLTWH(-100, -100, 1, 1);
          final button = t.getRect(find.byIcon(Icons.closed_caption_rounded));
          for (final (name, over) in [('timer', timer), ('captions button', button)]) {
            expect(over.overlaps(brows), isFalse, reason: '$name $over over the brows $brows');
            expect(over.overlaps(eyeBand), isFalse, reason: '$name over the eyes');
            expect(over.overlaps(face), isFalse, reason: '$name $over over the face $face');
            expect(over.bottom, lessThanOrEqualTo(portrait.top + 0.5), reason: '$name sits in the header, above the portrait');
            expect(over.bottom, lessThanOrEqualTo(header.bottom + 0.5), reason: '$name inside the header');
          }
          if (hasTimer) expect(timer.overlaps(button), isFalse, reason: 'timer and captions button do not overlap');
          expect(button.width, greaterThanOrEqualTo(44));
          expect(button.height, greaterThanOrEqualTo(44));

          // Brows, eyes and chin are inside the portrait and the visible viewport.
          expect(brows.top, greaterThanOrEqualTo(portrait.top - 2), reason: 'brows inside the stage');
          expect(face.bottom, lessThanOrEqualTo(portrait.bottom), reason: 'chin inside the stage');
          expect(face.bottom, lessThanOrEqualTo(viewport.bottom), reason: 'chin not cut by the stage viewport');
          expect(portrait.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(button.right, lessThanOrEqualTo(size.width), reason: 'captions button on screen');
          if (hasTimer) expect(timer.right, lessThanOrEqualTo(button.left + 0.5));
          expect(button.right, lessThanOrEqualTo(_r(t, 'chat-menu').left + 0.5), reason: 'captions button clear of the menu button');
          if (hasTimer) expect(timer.left, greaterThanOrEqualTo(_r(t, 'chat-header').left));
          // The eyebrow line is never half cut by the stage viewport.
          final eyebrow = find.text(coach.name.toUpperCase());
          if (eyebrow.evaluate().isNotEmpty) {
            final e = t.getRect(eyebrow.first);
            expect(e.top >= viewport.bottom - 0.5 || e.bottom <= viewport.bottom + 0.5, isTrue, reason: 'caption eyebrow $e cut by the viewport $viewport');
          }

          // Controls on screen.
          final screen = Offset.zero & size;
          for (final k in const ['chat-menu', 'hold-to-talk', 'talk-footer']) {
            expect(screen.contains(_r(t, k).topLeft) && screen.contains(_r(t, k).bottomRight - const Offset(.01, .01)), isTrue, reason: '$k on screen');
          }
        });
      }
    }
  }

  for (final d in _devices.entries) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('${d.key} x$scale keyboard open (300 pt), voice mode: the dock is above the keyboard, no overflow', (t) async {
        final (size, top, bottom) = d.value;
        await _openVoice(t, Coaches.ava, size, top, bottom, scale, keyboard: 300);
        expect(t.takeException(), isNull, reason: 'no RenderFlex overflow');
        final above = size.height - 300;
        for (final k in const ['chat-menu', 'hold-to-talk', 'talk-footer']) {
          final r = _r(t, k);
          expect(r.top, greaterThanOrEqualTo(0), reason: k);
          expect(r.bottom, lessThanOrEqualTo(above + 0.5), reason: '$k above the keyboard ($r vs $above)');
        }
        // The timer and the captions button (header) stay reachable.
        if (find.byKey(const ValueKey('voice-timer')).evaluate().isNotEmpty) expect(_r(t, 'voice-timer').bottom, lessThanOrEqualTo(above));
        expect(t.getRect(find.byIcon(Icons.closed_caption_rounded)).bottom, lessThanOrEqualTo(above));
        // The stage shrank: no portrait while the keyboard is up.
        expect(find.byType(CoachStageAvatar), findsNothing);
        if (scale > 1.3) expect(find.byKey(const ValueKey('voice-stage-scroll')), findsNothing, reason: 'no stage at large text with the keyboard up');
      });
    }
  }

  testWidgets('the keyboard closing brings the portrait back', (t) async {
    await _openVoice(t, Coaches.ava, const Size(393, 852), 59, 34, 1.0, keyboard: 300);
    expect(find.byType(CoachStageAvatar), findsNothing);
    t.view.viewInsets = FakeViewPadding.zero;
    await t.pumpAndSettle();
    expect(find.byType(CoachStageAvatar), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('text mode with the keyboard open is unaffected: no stage, composer above the keyboard', (t) async {
    setSurface(t, const Size(393, 852), 1.0);
    final app = await makeState(prefs: onboardedPrefs());
    await t.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat), speech: _Speech()));
    await t.pumpAndSettle();
    t.view.viewInsets = FakeViewPadding(bottom: 900);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-stage-scroll')), findsNothing);
    expect(find.byType(CoachStageAvatar), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(t.getRect(find.byType(TextField)).bottom, lessThanOrEqualTo(852 - 300));
    expect(t.takeException(), isNull);
  });

  for (final (name, size) in const [('iPad portrait', Size(820, 1180)), ('iPad landscape', Size(1180, 820))]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('$name x$scale: no overflow, controls on screen', (t) async {
        await _openVoice(t, Coaches.ava, size, 24, 20, scale);
        expect(t.takeException(), isNull);
        expect(find.byType(CoachStageAvatar), findsOneWidget);
        expect(_r(t, 'hold-to-talk').bottom, lessThanOrEqualTo(size.height));
      });
    }
  }

  testWidgets('SE x2.0, keyboard open, usage banner: no overflow and the footer above the keyboard', (t) async {
    CoachUsage.state.value = const CoachUsageState(notice: 'approaching_daily_limit');
    addTearDown(() => CoachUsage.state.value = null);
    await _openVoice(t, Coaches.ava, const Size(375, 667), 20, 0, 2.0, keyboard: 300);
    expect(t.takeException(), isNull);
    expect(_r(t, 'talk-footer').bottom, lessThanOrEqualTo(367.5));
    expect(_r(t, 'hold-to-talk').bottom, lessThanOrEqualTo(367.5));
  });

  // The conversation keeps at least the room it had before the framing change
  // (Ava, after one exchange, real fonts, no keyboard): message-list heights
  // measured on the app before the change, in pt; and with a usage banner.
  final base = {
    ('SE', 1.0, false): 112.5, ('SE', 1.5, false): 264.9, ('SE', 1.0, true): 87.5, ('SE', 1.5, true): 206.9,
    ('12 mini', 1.0, false): 159.0, ('12 mini', 1.5, false): 303.6, ('12 mini', 1.0, true): 134.0, ('12 mini', 1.5, true): 245.6,
    ('15', 1.0, false): 225.5, ('15', 1.5, false): 353.6, ('15', 1.0, true): 200.5, ('15', 1.5, true): 320.6,
    ('Pro Max', 1.0, false): 287.0, ('Pro Max', 1.5, false): 419.2, ('Pro Max', 1.0, true): 262.0, ('Pro Max', 1.5, true): 386.2,
  };
  for (final e in base.entries) {
    final (dev, scale, usage) = e.key;
    testWidgets('$dev x$scale${usage ? ' with a usage banner' : ''}: the message list is at least as tall as before (${e.value} pt)', (t) async {
      if (usage) {
        CoachUsage.state.value = const CoachUsageState(notice: 'approaching_daily_limit');
        addTearDown(() => CoachUsage.state.value = null);
      }
      final (size, top, bottom) = _devices[dev]!;
      setSurface(t, size, scale);
      t.view.padding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
      t.view.viewPadding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
      addTearDown(t.view.resetPadding);
      addTearDown(t.view.resetViewPadding);
      final app = await makeState(prefs: onboardedPrefs(coach: 'ava'));
      await t.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat), speech: _Speech()));
      await t.pumpAndSettle();
      await t.runAsync(() => app.state.sendMessage('How do I open a conversation with someone on a dating app?'));
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(find.byKey(const ValueKey('voice-mode')));
      await t.pumpAndSettle();
      final list = t.getRect(find.byType(ListView).first);
      expect(list.height, greaterThanOrEqualTo(e.value - 1.5), reason: 'message list ${list.height} pt vs ${e.value} before');
    });
  }
}
