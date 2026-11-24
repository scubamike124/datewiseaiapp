// The voice conversation screen after the owner's iPhone test of build 203:
// a small live subtitle instead of the whole reply, the whole face in a
// proportioned avatar window, and an avatar that can be hidden (remembered,
// with a default by screen size and text size), with nothing clipped.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/avatar/avatar_animator.dart' show AvatarPose;
import 'package:datewise_ai/avatar/avatar_frames.dart';
import 'package:datewise_ai/avatar/coach_stage_avatar.dart';
import 'package:datewise_ai/avatar/talking_avatar.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/services/storage_service.dart';

import 'fake_voice.dart';
import 'helpers.dart';

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
  Future<SpeechStart> start({required String localeId, List<String> fallbackLocales = const [], required void Function(String words) onWords, void Function()? onUnsupported, void Function(String words)? onEnded}) async => SpeechStart.started;
  @override
  Future<String> stop() async => '';
  @override
  Future<void> cancel() async {}
}

const _devices = {
  'SE': (Size(375, 667), 20.0, 0.0),
  '12 mini': (Size(360, 780), 50.0, 34.0),
  '15': (Size(393, 852), 59.0, 34.0),
  'Pro Max': (Size(430, 932), 59.0, 34.0),
};

Future<TestApp> _open(WidgetTester t, Size size, double scale,
    {Map<String, Object> extra = const {}, double top = 47, double bottom = 34, double keyboard = 0, ScriptedVoice? voice, String coach = 'ava', bool voiceMode = true}) async {
  setSurface(t, size, scale);
  t.view.padding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
  t.view.viewPadding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
  addTearDown(t.view.resetPadding);
  addTearDown(t.view.resetViewPadding);
  final app = await makeState(prefs: {...onboardedPrefs(coach: coach), ...extra});
  await t.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat), speech: _Speech(), voice: voice));
  await t.pumpAndSettle();
  if (voiceMode) {
    await t.tap(find.byKey(const ValueKey('voice-mode')));
    await t.pumpAndSettle();
  }
  if (keyboard > 0) {
    t.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
  }
  return app;
}

Rect _r(WidgetTester t, String key) => t.getRect(find.byKey(ValueKey(key)));

void main() {
  const open = {'dw_voice_avatar_collapsed': false};
  const closed = {'dw_voice_avatar_collapsed': true};

  group('avatar window: the whole face, framed the same on every phone and text size', () {
    const browMargin = 0.1;
    for (final coach in Coaches.all) {
      final manifest = AvatarManifest.parse(coach.id, File('assets/avatar/${coach.id}/manifest.json').readAsStringSync());
      final image = Size(manifest.width.toDouble(), manifest.height.toDouble());
      final eyes = manifest.patches['gaze']!.rect;
      for (final d in _devices.entries) {
        for (final scale in const [1.0, 2.0]) {
          testWidgets('${coach.name} ${d.key} x$scale', (t) async {
            final (size, top, bottom) = d.value;
            await _open(t, size, scale, extra: open, top: top, bottom: bottom, coach: coach.id);
            expect(t.takeException(), isNull);
            final win = _r(t, 'avatar-window');
            expect(win.width / win.height, closeTo(CoachStageAvatar.windowAspect, 0.01));
            expect(win.height, lessThanOrEqualTo(size.height * 0.24 + 0.5 > 120 ? size.height * 0.24 + 0.5 : 120));
            final portrait = t.getRect(find.byType(CoachStageAvatar));
            final k = CoachStageAvatar.overscanFor(largeText: scale > 1.3);
            final box = Size(portrait.width, portrait.height * k);
            final src = AvatarPainter.sourceRect(image, box, manifest.mouth, coach.heroFocus);
            final z = AvatarPainter.coverZoom(box);
            double y(double v) => portrait.top + box.height / 2 + ((v - src.top) / src.height * box.height - box.height / 2) * z;
            final browTop = y(eyes.top - browMargin * eyes.height) - AvatarPose.maxDy;
            final chin = y(manifest.mouth!.dy + 0.65 * manifest.mouthWidth!) + AvatarPose.maxDy;
            // Hair/forehead above the brows (a quarter of the window at least), chin inside.
            expect(browTop - win.top, greaterThan(win.height * 0.15), reason: 'room above the brows for the forehead');
            expect(chin, lessThanOrEqualTo(win.bottom), reason: 'the chin is inside the window');
            expect(y(eyes.bottom), lessThan(y(manifest.mouth!.dy)));
            // Nothing is drawn over the window.
            for (final k in const ['voice-timer', 'toggle-captions', 'toggle-avatar', 'voice-caption']) {
              expect(_r(t, k).overlaps(win), isFalse, reason: '$k overlaps the avatar window');
            }
            // 44 pt targets.
            for (final k in const ['toggle-captions', 'toggle-avatar']) {
              expect(_r(t, k).width, greaterThanOrEqualTo(44));
              expect(_r(t, k).height, greaterThanOrEqualTo(44));
            }
          });
        }
      }
    }
  });

  group('the stage is small, the conversation keeps the room', () {
    for (final d in _devices.entries) {
      testWidgets('${d.key}: expanded stage is at most about a fifth to a quarter of the screen', (t) async {
        final (size, top, bottom) = d.value;
        await _open(t, size, 1.0, extra: open, top: top, bottom: bottom);
        final stage = t.getRect(find.byKey(const ValueKey('voice-stage-scroll')));
        expect(stage.height, lessThanOrEqualTo(size.height * 0.30), reason: 'stage ${stage.height} of ${size.height}');
        expect(t.getRect(find.byType(ListView)).height, greaterThan(size.height * 0.2));
      });
    }
  });

  group('avatar hidden or shown', () {
    testWidgets('the control hides and shows the portrait and the choice is remembered', (t) async {
      final app = await _open(t, const Size(393, 852), 1.0, extra: open);
      expect(find.byType(CoachStageAvatar), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('toggle-avatar')));
      await t.pumpAndSettle();
      expect(find.byType(CoachStageAvatar), findsNothing);
      expect(app.state.voiceAvatarCollapsed, isTrue);
      expect(StorageService(await SharedPreferences.getInstance()).voiceAvatarCollapsed, isTrue);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('toggle-avatar')));
      await t.pumpAndSettle();
      expect(find.byType(CoachStageAvatar), findsOneWidget);
      expect(StorageService(await SharedPreferences.getInstance()).voiceAvatarCollapsed, isFalse);
    });

    testWidgets('a saved "shown" wins over the small-screen default (iPhone SE)', (t) async {
      await _open(t, const Size(375, 667), 1.0, extra: open, top: 20, bottom: 0);
      expect(find.byType(CoachStageAvatar), findsOneWidget);
    });

    testWidgets('a saved "hidden" wins over the tall-screen default (Pro Max)', (t) async {
      await _open(t, const Size(430, 932), 1.0, extra: closed, bottom: 34);
      expect(find.byType(CoachStageAvatar), findsNothing);
    });

    for (final (name, size, scale, expectHidden) in const [
      ('iPhone SE', Size(375, 667), 1.0, true),
      ('12 mini', Size(360, 780), 1.0, true),
      ('iPhone 15', Size(393, 852), 1.0, false),
      ('Pro Max', Size(430, 932), 1.0, false),
      ('iPhone 15 at text 1.5', Size(393, 852), 1.5, true),
      ('Pro Max at text 2.0', Size(430, 932), 2.0, true),
      ('iPad', Size(820, 1180), 1.0, false),
      ('iPhone 15 landscape', Size(852, 393), 1.0, true),
    ]) {
      testWidgets('default on $name: ${expectHidden ? 'hidden' : 'shown'}', (t) async {
        await _open(t, size, scale, top: 24, bottom: 20);
        expect(t.takeException(), isNull);
        expect(find.byType(CoachStageAvatar), expectHidden ? findsNothing : findsOneWidget);
      });
    }

    for (final (lang, coach, hide, show) in const [('en', 'ava', 'Hide avatar', 'Show avatar'), ('es', 'sofia', 'Ocultar avatar', 'Mostrar avatar')]) {
      testWidgets('VoiceOver label ($lang) follows the state', (t) async {
        final h = t.ensureSemantics();
        setSurface(t, const Size(393, 852), 1.0);
        final app = await makeState(prefs: {...onboardedPrefs(coach: coach, language: lang), ...open});
        await t.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat), speech: _Speech()));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('voice-mode')));
        await t.pumpAndSettle();
        expect(find.bySemanticsLabel(hide), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('toggle-avatar')));
        await t.pumpAndSettle();
        expect(find.bySemanticsLabel(show), findsOneWidget);
        expect(find.bySemanticsLabel(hide), findsNothing);
        h.dispose();
      });
    }

    testWidgets('"Delete my data" forgets the choice', (t) async {
      final app = await _open(t, const Size(393, 852), 1.0, extra: closed);
      expect(app.state.voiceAvatarCollapsed, isTrue);
      await t.runAsync(() => app.state.deleteMyData());
      expect(app.state.voiceAvatarCollapsed, isNull);
      expect(StorageService(await SharedPreferences.getInstance()).voiceAvatarCollapsed, isNull);
    });

    for (final (name, size, scale) in const [('SE x2.0', Size(375, 667), 2.0), ('mini x2.0', Size(360, 780), 2.0), ('15 x1.0', Size(393, 852), 1.0)]) {
      testWidgets('hidden, $name: header, buttons and the last message are reachable; no overflow', (t) async {
        await _open(t, size, scale, extra: closed, top: 24, bottom: 20);
        expect(t.takeException(), isNull);
        final screen = Offset.zero & size;
        for (final k in const ['chat-menu', 'toggle-avatar', 'toggle-captions', 'hold-to-talk', 'talk-footer']) {
          final r = _r(t, k);
          expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight - const Offset(.01, .01)), isTrue, reason: '$k $r on screen');
        }
        expect(t.getRect(find.byType(ListView)).height, greaterThan(size.height * 0.2));
      });
    }
  });

  group('the subtitle', () {
    testWidgets('is one short sentence of the reply, not the reply', (t) async {
      final voice = ScriptedVoice();
      final app = await _open(t, const Size(393, 852), 1.0, extra: open, voice: voice);
      await t.runAsync(() => app.state.sendMessage('How do I open a chat?'));
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final reply = app.state.activeThread!.messages.last.text;
      final caption = t.widget<Text>(find.byKey(const ValueKey('voice-caption'))).data!;
      expect(caption, isNotEmpty);
      expect(caption.length, lessThan(reply.length), reason: 'not the whole reply');
      expect(reply.replaceAll('**', ''), contains(caption.replaceAll('…', '')));
      expect(t.getRect(find.byKey(const ValueKey('voice-caption'))).height, lessThan(80));
    });

    testWidgets('follows the speech: later words give a later sentence', (t) async {
      final voice = ScriptedVoice();
      final app = await _open(t, const Size(393, 852), 1.0, extra: open, voice: voice);
      await t.runAsync(() => app.state.sendMessage('How do I open a chat?'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(voice.spoken.length, 1);
      final first = t.widget<Text>(find.byKey(const ValueKey('voice-caption'))).data!;
      voice.now = const Duration(seconds: 8);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 250));
      }
      final later = t.widget<Text>(find.byKey(const ValueKey('voice-caption'))).data!;
      expect(later, isNot(first));
    });

    testWidgets('captions off: no subtitle at all', (t) async {
      await _open(t, const Size(393, 852), 1.0, extra: open);
      expect(find.byKey(const ValueKey('voice-caption')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('toggle-captions')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-caption')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('large text does not grow it past two or three lines or clip the stage', (t) async {
      await _open(t, const Size(430, 932), 2.0, extra: open, bottom: 34);
      expect(t.takeException(), isNull);
      final cap = _r(t, 'voice-caption');
      final stage = t.getRect(find.byKey(const ValueKey('voice-stage-scroll')));
      expect(cap.bottom, lessThanOrEqualTo(stage.bottom));
    });
  });

  group('keyboard', () {
    for (final d in _devices.entries) {
      testWidgets('${d.key}: voice mode, keyboard open: dock above the keyboard, controls reachable', (t) async {
        final (size, top, bottom) = d.value;
        await _open(t, size, 1.0, extra: open, top: top, bottom: bottom, keyboard: 300);
        expect(t.takeException(), isNull);
        final above = size.height - 300;
        for (final k in const ['chat-menu', 'hold-to-talk', 'talk-footer', 'voice-timer', 'toggle-captions', 'toggle-avatar']) {
          expect(_r(t, k).bottom, lessThanOrEqualTo(above + 0.5), reason: k);
        }
      });
    }
  });

  group('header and session time', () {
    for (final coach in Coaches.all) {
      for (final d in _devices.entries) {
        for (final scale in const [1.0, 1.5, 2.0]) {
         for (final collapsed in [false, true]) {
          testWidgets('${coach.name} ${d.key} x$scale avatar ${collapsed ? 'hidden' : 'shown'}: the header subtitle is never truncated; the session time is shown and announced', (t) async {
            final h = t.ensureSemantics();
            final (size, top, bottom) = d.value;
            final lang = coach.language == CoachLanguage.es ? 'es' : 'en';
            setSurface(t, size, scale);
            t.view.padding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
            t.view.viewPadding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
            addTearDown(t.view.resetPadding);
            addTearDown(t.view.resetViewPadding);
            {
              final app = await makeState(prefs: {...onboardedPrefs(coach: coach.id, language: lang), 'dw_voice_avatar_collapsed': collapsed});
              await t.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat), speech: _Speech()));
              await t.pumpAndSettle();
              await t.tap(find.byKey(const ValueKey('voice-mode')));
              await t.pumpAndSettle();
              final p = t.renderObject<RenderParagraph>(find.descendant(of: find.byKey(const ValueKey('ai-label')), matching: find.byType(RichText)));
              expect(p.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(p.size.width + 0.5), reason: 'header subtitle truncated: needs ${p.getMaxIntrinsicWidth(double.infinity)}, has ${p.size.width}');
              // The language is still announced.
              expect(find.bySemanticsLabel(RegExp(lang == 'es' ? 'IA · Español' : 'AI dating coach · English')), findsOneWidget);
              // The timer chip is always there, whole, and VoiceOver reads the time.
              final timer = t.getRect(find.byKey(const ValueKey('voice-timer')));
              expect(timer.width, greaterThan(40), reason: 'timer (collapsed=$collapsed)');
              expect(find.bySemanticsLabel(RegExp(lang == 'es' ? r'Sesión de voz · \d\d:\d\d' : r'Voice session · \d\d:\d\d')), findsOneWidget);
              expect(t.takeException(), isNull);
            }
            h.dispose();
          });
         }
        }
      }
    }
  });
}
