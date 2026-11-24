// ignore_for_file: invalid_use_of_visible_for_testing_member
// Renders the real chat screen (real Inter / Newsreader / Material icons) to
// PNG plus a JSON of measured rectangles, for the conversation-screen review.
//
//   CV_OUT=<dir> [CV_COACH=ava] [CV_DEV=se375x667,...] [CV_SCALE=1.0,2.0]
//   [CV_MODE=voice|text] [CV_SCEN=convo,long,usage,speak,es] [CV_AVATAR=auto|open|closed]
//   [CV_LAND=1] [CV_KB=0|1|both] flutter test --concurrency=2 tool/convo/render_convo_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/avatar/avatar_frames.dart';
import 'package:datewise_ai/avatar/coach_stage_avatar.dart';
import 'package:datewise_ai/avatar/talking_avatar.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/coach_usage.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';

import '../../test/fake_voice.dart';
import '../../test/helpers.dart';

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

const _short = 'Start with something specific from their profile. **Ask about the trip in photo three** and keep it light.';
const _long = 'Great question, and the good news is that openers are easier than they feel. Start with something specific from their profile instead of a generic hello, because it shows you actually looked.\n\n'
    '**Three things that work:**\n'
    '• Ask about one photo: "That trail looks unreal, where was it?"\n'
    '• Share a quick, honest reaction to something in their bio.\n'
    '• Keep it to one question so they can answer in a single message.\n\n'
    'Avoid copy-paste lines and anything that sounds like a pickup line; they get ignored. If they reply, match their energy and suggest a low-pressure plan within a few messages, like a coffee this week.\n\n'
    'Here is a message you could send right now, and a playful variant if you want a bit more personality in your first line to them.\n'
    'OPTIONS: Safe | "That trail looks unreal, where was it?" || Playful | "Okay, that view beats my Sunday. Details?"';
const _longEs = 'Muy buena pregunta, y la buena noticia es que abrir una conversación es más fácil de lo que parece. Empieza con algo específico de su perfil en lugar de un saludo genérico, porque demuestra que de verdad lo miraste.\n\n'
    '**Tres cosas que funcionan:**\n'
    '• Pregunta por una foto: "Ese sendero se ve increíble, ¿dónde fue?"\n'
    '• Comparte una reacción sincera a algo de su biografía.\n'
    '• Haz una sola pregunta para que pueda responder en un mensaje.\n\n'
    'Evita las frases copiadas y todo lo que suene a línea de conquista; las ignoran.';

class _ScriptedAi implements AIService {
  _ScriptedAi(this.text);
  final String text;
  @override
  String get providerLabel => 'scripted';
  @override
  Stream<String> streamReply({required List<ChatMessage> history, required SubscriptionTier tier, UserProfile? profile, Coach? coach}) async* {
    yield text;
  }
}

void main() {
  final out = Platform.environment['CV_OUT'];
  final onlyCoach = Platform.environment['CV_COACH'];
  final scen = Platform.environment['CV_SCEN'] ?? 'convo';
  final mode = Platform.environment['CV_MODE'] ?? 'voice';
  final avatarPref = Platform.environment['CV_AVATAR'] ?? 'auto';
  final land = Platform.environment['CV_LAND'] == '1';
  final kbs = switch (Platform.environment['CV_KB'] ?? 'both') { '0' => [false], '1' => [true], _ => [false, true] };
  final devFilter = Platform.environment['CV_DEV']?.split(',');
  final scales = (Platform.environment['CV_SCALE'] ?? '1.0,1.5,2.0').split(',').map(double.parse).toList();
  const devices = {
    'se375x667': (Size(375, 667), 20.0, 0.0),
    'mini360x780': (Size(360, 780), 50.0, 34.0),
    'i15_393x852': (Size(393, 852), 59.0, 34.0),
    'promax430x932': (Size(430, 932), 59.0, 34.0),
    'ipad820x1180': (Size(820, 1180), 24.0, 20.0),
  };

  setUpAll(() async {
    final mi = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(File('/root/fl/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync().buffer)));
    await mi.load();
    for (final (fam, files) in [('Inter', ['Regular', 'Medium', 'SemiBold', 'Bold']), ('Newsreader', ['Regular', 'Medium', 'Italic'])]) {
      final l = FontLoader(fam);
      for (final f in files) {
        l.addFont(Future.value(ByteData.view(File('assets/fonts/$fam-$f.ttf').readAsBytesSync().buffer)));
      }
      await l.load();
    }
  });

  Future<void> shot(WidgetTester t, GlobalKey key, String file) async {
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$file').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  for (final coach in Coaches.all) {
    if (onlyCoach != null && onlyCoach != coach.id) continue;
    for (final d in devices.entries) {
      if (devFilter != null && !devFilter.contains(d.key)) continue;
      for (final scale in scales) {
        for (final kb in kbs) {
          testWidgets('${coach.id} ${d.key} x$scale kb=$kb', (t) async {
            if (out == null) return;
            Directory(out).createSync(recursive: true);
            var (size, top, bottom) = d.value;
            if (land) {
              size = Size(size.height, size.width);
              top = 0;
              bottom = 0;
            }
            AvatarFrames.clearCache();
            addTearDown(AvatarFrames.clearCache);
            await t.runAsync(() => AvatarFrames.acquire(coach));
            final key = GlobalKey();
            setSurface(t, size, scale);
            t.view.padding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
            t.view.viewPadding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
            addTearDown(t.view.resetPadding);
            addTearDown(t.view.resetViewPadding);
            final prefs = <String, Object>{
              ...onboardedPrefs(coach: coach.id, language: coach.language == CoachLanguage.es ? 'es' : 'en'),
              if (avatarPref != 'auto') 'dw_voice_avatar_collapsed': avatarPref == 'closed',
            };
            SharedPreferences.setMockInitialValues(prefs);
            final storage = await StorageService.create();
            final store = FakeStoreService(entitled: true);
            final reply = scen.contains('long') ? (coach.language == CoachLanguage.es ? _longEs : _long) : _short;
            final state = AppState(storage: storage, ai: _ScriptedAi(reply), store: store);
            final app = TestApp(state, store, storage);
            final voice = ScriptedVoice();
            await t.pumpWidget(wrap(app, RepaintBoundary(key: key, child: const DateWiseApp(initialTab: AppTab.chat)), speech: _Speech(), voice: voice));
            await t.pumpAndSettle();
            await t.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
            await t.pump();
            if (scen.contains('usage')) {
              CoachUsage.state.value = const CoachUsageState(notice: 'approaching_daily_limit');
              addTearDown(() => CoachUsage.state.value = null);
              await t.pump();
            }
            if (mode == 'voice') {
              await t.tap(find.byKey(const ValueKey('voice-mode')));
              await t.pump(const Duration(milliseconds: 100));
            }
            if (scen.contains('convo')) {
              await t.runAsync(() => state.sendMessage('How do I open a conversation with someone on a dating app?'));
              await t.pump(const Duration(milliseconds: 200));
            }
            for (var i = 0; i < 8; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
            for (var i = 0; mode == 'voice' && i < 40 && find.byKey(const ValueKey('talking-avatar-paint')).evaluate().isEmpty && find.byType(CoachStageAvatar).evaluate().isNotEmpty; i++) {
              await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
              await t.pump();
            }
            if (scen.contains('speak') && voice.spoken.isNotEmpty) {
              voice.now = const Duration(milliseconds: 14000);
              for (var i = 0; i < 3; i++) {
                await t.pump(const Duration(milliseconds: 250));
              }
            }
            if (kb) {
              if (mode == 'text') {
                await t.tap(find.byType(TextField));
                await t.pump();
                await t.enterText(find.byType(TextField), 'This is a longer message I am typing to check that the field grows a line or two and nothing is hidden under the keyboard or the buttons.');
                await t.pump();
              }
              t.view.viewInsets = FakeViewPadding(bottom: 300.0 * 3);
              addTearDown(t.view.resetViewInsets);
              for (var i = 0; i < 8; i++) {
                await t.pump(const Duration(milliseconds: 100));
              }
            }
            final tag = '${scen.replaceAll(',', '+')}_${mode}_$avatarPref${land ? '_land' : ''}_${coach.id}_${d.key}_x${scale}_${kb ? 'kb' : 'nokb'}';
            await shot(t, key, '$tag.png');
            final m = AvatarManifest.parse(coach.id, File('assets/avatar/${coach.id}/manifest.json').readAsStringSync());
            final image = Size(m.width.toDouble(), m.height.toDouble());
            final stage = find.byType(CoachStageAvatar);
            final stageRect = stage.evaluate().isEmpty ? null : t.getRect(stage);
            Rect? r(Finder f) => f.evaluate().isEmpty ? null : t.getRect(f.first);
            List<double>? rl(Rect? x) => x == null ? null : [x.left, x.top, x.right, x.bottom];
            Map<String, double>? lm;
            if (stageRect != null) {
              final large = scale > 1.3;
              final k = CoachStageAvatar.overscanFor(largeText: large);
              final box = Size(stageRect.width, stageRect.height * k);
              final src = AvatarPainter.sourceRect(image, box, m.mouth, coach.heroFocus);
              final z = AvatarPainter.coverZoom(box);
              double sy(double y) => box.height / 2 + ((y - src.top) / src.height * box.height - box.height / 2) * z;
              final eyes = m.patches['gaze']!.rect;
              lm = {
                'eyeTop': sy(eyes.top), 'eyeBottom': sy(eyes.bottom), 'mouth': sy(m.mouth!.dy),
                'chin': sy(m.mouth!.dy + 0.65 * m.mouthWidth!), 'brow': sy(eyes.top - 0.1 * eyes.height),
              };
            }
            final msgs = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('msg-')).evaluate().toList();
            final rects = <String, List<double>?>{
              'header': rl(r(find.byKey(const ValueKey('chat-header')))),
              'menu': rl(r(find.byKey(const ValueKey('chat-menu')))),
              'stageWidget': rl(r(find.byKey(const ValueKey('voice-stage-scroll')))),
              'portrait': rl(stageRect),
              'controls': rl(r(find.byKey(const ValueKey('voice-stage-controls')))),
              'timer': rl(r(find.byKey(const ValueKey('voice-timer')))),
              'caption': rl(r(find.byKey(const ValueKey('voice-caption')))),
              'capBtn': rl(r(find.byIcon(Icons.closed_caption_rounded)) ?? r(find.byIcon(Icons.closed_caption_off_outlined))),
              'avatarBtn': rl(r(find.byKey(const ValueKey('toggle-avatar')))),
              'list': rl(r(find.byType(ListView))),
              'lastMsg': rl(msgs.isEmpty ? null : t.getRect(find.byElementPredicate((e) => e == msgs.last))),
              'usage': rl(r(find.byKey(const ValueKey('usage-notice')))),
              'talk': rl(r(find.byKey(const ValueKey('hold-to-talk')))),
              'talkFooter': rl(r(find.byKey(const ValueKey('talk-footer')))),
              'composer': rl(r(find.byType(TextField))),
              'send': rl(r(find.byIcon(Icons.arrow_upward_rounded))),
              'voiceBtn': rl(r(find.byKey(const ValueKey('voice-mode')))),
            };
            final captionText = find.byKey(const ValueKey('voice-caption')).evaluate().isEmpty ? null : (t.widget<Text>(find.byKey(const ValueKey('voice-caption'))).data);
            File('$out/$tag.json').writeAsStringSync(jsonEncode({
              'device': d.key, 'coach': coach.id, 'scale': scale, 'kb': kb, 'mode': mode, 'scen': scen, 'land': land,
              'screen': [size.width, size.height], 'inset': kb ? 300 : 0, 'lm': lm, 'rects': rects, 'captionText': captionText,
              'spoken': voice.spoken.length, 'dbg': [voice.speaking.value, voice.lipSync.active, voice.lipSync.planTime(), voice.lipSync.timeline?.words.length], 'exception': t.takeException()?.toString(),
            }));
          });
        }
      }
    }
  }
}
