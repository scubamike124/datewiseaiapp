// Release end-to-end test of the app's own widgets on an iOS simulator.
//
// Runs under `flutter test integration_test/release_e2e_test.dart -d <simulator>`
// (see .github/workflows/ios-sim-release-e2e.yml), never on the host. Build
// flags: DW_AVATAR_AUDIO_PATH=true (the native AVSpeechSynthesizer audio path
// of ios/Runner/AppDelegate.swift), DW_MOCK_AI=true (the offline demo coach:
// no request ever reaches the coach backend) and DW_FAKE_STORE=true (the
// review build's simulated store; no Apple account, nothing is bought).
//
// Scenarios:
//  1. the gold Send button: one tap, a double and a triple tap, the keyboard's
//     Send action, and Send while a reply is still streaming;
//  2. "Find a table" / "Buscar mesa" and the "Plan a table" sheet, with the
//     launched OpenTable, Google Maps and Apple Maps URLs recorded through the
//     sheet's launch hook (nothing is opened);
//  3. the voice conversation with each coach (Ava, Ethan, Sofía, Diego): the
//     reply is read aloud through the real native speech path, and the
//     avatar's rendered poses (mouth shapes, jaw, blinks) are recorded.
//
// Evidence: PNG screenshots and summary.json, written to E2E_OUT_DIR (a host
// directory; simulator apps can write there) and to the app's own tmp
// directory (copied out by the workflow if the first is not writable).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/avatar/speech_audio.dart';
import 'package:datewise_ai/avatar/talking_avatar.dart';
import 'package:datewise_ai/avatar/viseme.dart';
import 'package:datewise_ai/dev/review_mode.dart';
import 'package:datewise_ai/l10n/l10n.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/table_plan.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/mock_ai_service.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/services/voice_service.dart';
import 'package:datewise_ai/state/app_state.dart';
import 'package:datewise_ai/widgets/plan_table_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _outDirDefine = String.fromEnvironment('E2E_OUT_DIR');

final _en = lookupAppLocalizations(const Locale('en'));
final _es = lookupAppLocalizations(const Locale('es'));

/// Everything measured, written as summary.json at the end.
final _summary = <String, Object?>{
  'started': DateTime.now().toIso8601String(),
  'flags': {
    'DW_AVATAR_AUDIO_PATH': DeviceVoiceService.useAudioPath,
    'DW_MOCK_AI': ReviewMode.mockAI,
    'DW_FAKE_STORE': StoreConfig.useFakeStore,
  },
  'scenarios': <String, Object?>{},
  'notes': <String>[],
};
Map<String, Object?> get _scenarios => _summary['scenarios']! as Map<String, Object?>;
List<String> get _notes => _summary['notes']! as List<String>;

final _rootKey = GlobalKey();
late final _TapBackend _audio;
late final DeviceVoiceService _voice;
late final List<Map<String, String>> _voices;
final _speech = _FakeSpeech();

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The app runs as on a phone: every frame the engine asks for is drawn,
  // so the avatar's ticker animates between the test's own pumps.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    _log('output: E2E_OUT_DIR=${_outDirDefine.isEmpty ? '(unset)' : _outDirDefine}, app tmp=${_appOut()}');
    expect(ReviewMode.mockAI, isTrue, reason: 'build with --dart-define=DW_MOCK_AI=true (offline demo coach)');
    expect(StoreConfig.useFakeStore, isTrue, reason: 'build with --dart-define=DW_FAKE_STORE=true');
    expect(DeviceVoiceService.useAudioPath, isTrue, reason: 'build with --dart-define=DW_AVATAR_AUDIO_PATH=true');
    // DeviceVoiceService.create() as lib/main.dart runs it on iOS, with the
    // native backend wrapped only to count its events (one EventChannel
    // listener: a second backend would take the native sink away).
    final tts = FlutterTts();
    await tts.awaitSpeakCompletion(false);
    final raw = await tts.getVoices;
    _voices = <Map<String, String>>[
      if (raw is List)
        for (final v in raw)
          if (v is Map) {for (final e in v.entries) '${e.key}': '${e.value}'},
    ];
    _audio = _TapBackend(ChannelSpeechAudioBackend());
    _voice = DeviceVoiceService.forTesting(tts, _voices, audio: _audio);
    final en = _voices.where((v) => (v['locale'] ?? '').startsWith('en')).length;
    final es = _voices.where((v) => (v['locale'] ?? '').startsWith('es')).length;
    _summary['voices'] = {
      'total': _voices.length,
      'en': en,
      'es': es,
      'esList': [
        for (final v in _voices)
          if ((v['locale'] ?? '').startsWith('es')) '${v['name']} (${v['locale']}, ${v['quality'] ?? '?'}, ${v['gender'] ?? '?'})'
      ],
    };
    _log('system voices: ${_voices.length} (en $en, es $es)');
  });

  tearDownAll(() async {
    _summary['finished'] = DateTime.now().toIso8601String();
    final json = const JsonEncoder.withIndent('  ').convert(_summary);
    _save('summary.json', utf8.encode(json));
    // ignore: avoid_print
    print('[release-e2e] SUMMARY ${jsonEncode(_summary)}');
  });

  // ---------------------------------------------------------------------------
  // 1. The gold Send button.

  _scenario('send: tap, double tap, triple tap, keyboard Send, Send while streaming', (t, r) async {
    final app = await _launch(t, coach: 'ava');
    final composer = find.byKey(const ValueKey('composer'));
    await _shot(t, 'send-0-chat');

    // One tap.
    await _type(t, 'What should I send?');
    var before = _userCount(app);
    await _tap(t, const ValueKey('send'));
    await _until(t, () => _userCount(app) == before + 1, 'user message added');
    expect(_composerText(t), isEmpty, reason: 'the composer clears once the message is accepted');
    await _until(t, () => !app.state.isResponding, 'reply finished', timeout: const Duration(seconds: 60));
    _expectFullReply(t, app, 'What should I send?');
    await _shot(t, 'send-1-single');
    r['singleTap'] = 'one user message, full reply, composer cleared';

    // Double tap: the second tap lands 120 ms later on the same spot, where the
    // button has turned into Stop. It must neither send again nor stop the reply.
    for (final (name, taps) in [('double', 2), ('triple', 3)]) {
      final text = name == 'double' ? 'How do I write a good opener?' : 'I feel nervous before dates.';
      await _type(t, text);
      before = _userCount(app);
      final at = t.getCenter(find.byKey(const ValueKey('send')));
      final seen = <String>[];
      for (var i = 0; i < taps; i++) {
        if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 120));
        seen.add(_buttonState());
        await t.tapAt(at);
        await t.pump();
      }
      await _settle(t, const Duration(milliseconds: 800));
      expect(_userCount(app), before + 1, reason: '$name tap: exactly one message');
      await _until(t, () => !app.state.isResponding, 'reply finished', timeout: const Duration(seconds: 60));
      final last = _lastCoach(app);
      expect(last.status, MessageStatus.ok, reason: '$name tap: the reply was not stopped');
      _expectFullReply(t, app, text);
      expect(_composerText(t), isEmpty);
      await _shot(t, 'send-2-$name');
      r['${name}Tap'] = {'buttonBeforeEachTap': seen, 'userMessagesAdded': _userCount(app) - before, 'replyStatus': last.status.name};
    }

    // The keyboard's Send action.
    await _type(t, 'Can you help with my bio?');
    before = _userCount(app);
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
    await _until(t, () => _userCount(app) == before + 1, 'keyboard Send added the message');
    expect(_composerText(t), isEmpty);
    await _until(t, () => !app.state.isResponding, 'reply finished', timeout: const Duration(seconds: 60));
    _expectFullReply(t, app, 'Can you help with my bio?');
    r['keyboardSend'] = 'sent, composer cleared';

    // Send while a reply streams: refused, and the text stays in the composer.
    await _type(t, 'What should I send?');
    before = _userCount(app);
    await _tap(t, const ValueKey('send'));
    await _until(t, () => app.state.isResponding, 'reply streaming');
    await _settle(t, const Duration(milliseconds: 300));
    const waiting = 'Is a second message refused?';
    await t.enterText(composer, waiting);
    await t.pump();
    expect(app.state.isResponding, isTrue, reason: 'still streaming when the second message is sent');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await _settle(t, const Duration(milliseconds: 500));
    expect(_userCount(app), before + 1, reason: 'nothing sent while the reply streams');
    expect(_composerText(t), waiting, reason: 'the text is kept');
    await _shot(t, 'send-3-refused-while-streaming');
    await _until(t, () => !app.state.isResponding, 'reply finished', timeout: const Duration(seconds: 60));
    expect(_lastCoach(app).status, MessageStatus.ok);
    expect(_composerText(t), waiting, reason: 'still kept after the reply');
    await _tap(t, const ValueKey('send'));
    await _until(t, () => _userCount(app) == before + 2, 'the kept text is sent once the reply is done');
    await _until(t, () => !app.state.isResponding, 'reply finished', timeout: const Duration(seconds: 60));
    r['sendWhileStreaming'] = 'refused, text kept, sent afterwards';
  });

  // ---------------------------------------------------------------------------
  // 2. Find a table / Plan a table.

  for (final lang in [CoachLanguage.en, CoachLanguage.es]) {
    _scenario('reservation (${lang.name}): Find a table, Plan a table sheet, search links', (t, r) async {
      final es = lang == CoachLanguage.es;
      final l = es ? _es : _en;
      final launched = <Uri>[];
      final realLaunch = PlanTableSheet.launch;
      final realNow = PlanTableSheet.now;
      PlanTableSheet.launch = (uri) async {
        launched.add(uri);
        return true;
      };
      // Wednesday 2026-11-25, 15:05: the default is today at 19:30.
      PlanTableSheet.now = () => DateTime(2026, 11, 25, 15, 5);
      try {
        final app = await _launch(t, coach: es ? 'sofia' : 'ava', language: lang);
        final ask = es ? '¿Puedes reservarnos una mesa para el viernes?' : 'Can you book us a table for Friday?';
        await _type(t, ask);
        await _tap(t, const ValueKey('send'));
        await _until(t, () => !app.state.isResponding && _lastCoach(app).text.isNotEmpty, 'reply finished',
            timeout: const Duration(seconds: 60));
        final button = find.byKey(const ValueKey('find-table'));
        await _until(t, () => button.evaluate().isNotEmpty, 'Find a table under the reply');
        expect(find.descendant(of: button, matching: find.text(l.findTable)), findsOneWidget);
        r['buttonLabel'] = l.findTable;
        await t.ensureVisible(button);
        await _settle(t, const Duration(milliseconds: 400));
        await _shot(t, 'table-${lang.name}-0-button');
        await t.tap(button);
        await _until(t, () => find.byKey(const ValueKey('plan-table')).evaluate().isNotEmpty, 'Plan a table sheet');
        await _settle(t, const Duration(milliseconds: 600));
        final honest = t.widget<Text>(find.byKey(const ValueKey('plan-table-honest'))).data;
        expect(honest, l.planTableHonest);
        r['honestNote'] = honest;

        final area = es ? 'Polanco' : 'Chicago';
        final cuisine = es ? 'italiana' : 'Italian';
        await t.enterText(find.byKey(const ValueKey('plan-table-area')), area);
        await t.pump();
        await t.enterText(find.byKey(const ValueKey('plan-table-cuisine')), cuisine);
        await t.pump();
        await _tapIn(t, const ValueKey('plan-table-budget-2'));
        // Friday 27 in the date picker.
        await _tapIn(t, const ValueKey('plan-table-date'));
        await _until(t, () => find.byType(Dialog).evaluate().isNotEmpty, 'date picker');
        await _settle(t, const Duration(milliseconds: 500));
        await _shot(t, 'table-${lang.name}-1-date-picker');
        await t.tap(find.descendant(of: find.byType(Dialog), matching: find.text('27')));
        await t.pump();
        await t.tap(find.descendant(of: find.byType(Dialog), matching: find.byType(TextButton)).last);
        await _until(t, () => find.byType(Dialog).evaluate().isEmpty, 'date picker closed');
        // 20:00 in the time picker's text entry (12-hour in English: 8 with the
        // default PM; 24-hour in Spanish).
        await _tapIn(t, const ValueKey('plan-table-time'));
        await _until(t, () => find.byType(Dialog).evaluate().isNotEmpty, 'time picker');
        await _settle(t, const Duration(milliseconds: 500));
        final toInput = find.descendant(
            of: find.byType(Dialog),
            matching: find.byWidgetPredicate((w) =>
                w is Icon && (w.icon == Icons.keyboard_outlined || w.icon == Icons.keyboard)));
        await t.tap(toInput.first);
        await _settle(t, const Duration(milliseconds: 500));
        final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
        await t.enterText(fields.at(0), es ? '20' : '8');
        await t.pump();
        await t.enterText(fields.at(1), '00');
        await t.pump();
        await _shot(t, 'table-${lang.name}-2-time-picker');
        await t.tap(find.descendant(of: find.byType(Dialog), matching: find.byType(TextButton)).last);
        await _until(t, () => find.byType(Dialog).evaluate().isEmpty, 'time picker closed');
        await _tapIn(t, const ValueKey('plan-table-more'));
        await _tapIn(t, const ValueKey('plan-table-more'));
        expect(t.widget<Text>(find.byKey(const ValueKey('plan-table-party'))).data, l.planTablePeople(4));
        await _settle(t, const Duration(milliseconds: 300));
        await _shot(t, 'table-${lang.name}-3-filled');

        for (final k in ['plan-table-opentable', 'plan-table-google', 'plan-table-apple']) {
          await _tapIn(t, ValueKey(k));
        }
        expect(find.byKey(const ValueKey('plan-table-error')), findsNothing);
        await _shot(t, 'table-${lang.name}-4-links');
        final plan = TablePlan(
          area: area,
          cuisine: cuisine,
          budget: 2,
          date: DateTime(2026, 11, 27),
          time: const TimeOfDay(hour: 20, minute: 0),
          partySize: 4,
        );
        final want = [plan.openTableUri.toString(), plan.googleMapsUri(l).toString(), plan.appleMapsUri(l).toString()];
        r['launched'] = [for (final u in launched) u.toString()];
        expect([for (final u in launched) u.toString()], want);
        // The literal URLs, independent of TablePlan.
        final q = es
            ? 'restaurantes%20italiana%20de%20precio%20medio%20en%20Polanco'
            : 'moderately%20priced%20Italian%20restaurants%20in%20Chicago';
        expect(launched[0].toString(),
            'https://www.opentable.com/s/?covers=4&dateTime=2026-11-27T20%3A00%3A00&term=${es ? 'italiana%20Polanco' : 'Italian%20Chicago'}');
        expect(launched[1].toString(), 'https://www.google.com/maps/search/?api=1&query=$q');
        expect(launched[2].toString(), 'https://maps.apple.com/?q=$q');
        // Nothing from the chat is in any link.
        for (final u in launched) {
          expect(Uri.decodeFull(u.toString()).toLowerCase(), isNot(contains(es ? 'viernes' : 'friday')));
        }
      } finally {
        PlanTableSheet.launch = realLaunch;
        PlanTableSheet.now = realNow;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 3. The talking avatar with each coach, through the native speech path.

  // Measurement, not part of the app's behavior: how long the very first native
  // utterance of the process takes to produce audio. The app gives it
  // DeviceVoiceService.audioStartTimeout (3 s) before it falls back to
  // flutter_tts; here it gets 20 s, so the real cold-start time is seen.
  _scenario('native audio cold start: time to the first audio of the first utterance', (t, r) async {
    final saved = DeviceVoiceService.audioStartTimeout;
    DeviceVoiceService.audioStartTimeout = const Duration(seconds: 20);
    try {
      _audio.reset();
      final clock = Stopwatch()..start();
      await _voice.speak('Hi, I am Ava. Tell me what you would like to work on.', Coaches.byId('ava'));
      while (_audio.starts == 0 && _audio.errors.isEmpty && clock.elapsed < const Duration(seconds: 21)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      r['firstAudioMs'] = _audio.starts > 0 ? clock.elapsedMilliseconds : null;
      final until = DateTime.now().add(const Duration(seconds: 20));
      while (_voice.speaking.value && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      r['nativeTimeline'] = [..._audio.timeline];
      r['chunksPlayedNatively'] = '${_audio.playedNatively.where((b) => b).length}/${_audio.playedNatively.length}';
      r['errors'] = [..._audio.errors];
      _log('cold start: $r');
      expect(_audio.starts, greaterThan(0), reason: 'the first native utterance never produced audio within 20 s');
    } finally {
      DeviceVoiceService.audioStartTimeout = saved;
    }
  });

  for (final id in ['ava', 'ethan', 'sofia', 'diego']) {
    _scenario('avatar ($id): voice conversation, reply read aloud through the native audio path', (t, r) async {
      final coach = Coaches.byId(id);
      final es = coach.language == CoachLanguage.es;
      final app = await _launch(t, coach: id, language: coach.language);
      _speech.transcript = es ? 'Hola, ¿qué le contesto?' : 'What should I send?';
      final problems = <String>[];

      await _tap(t, const ValueKey('voice-mode'));
      final window = find.byKey(const ValueKey('avatar-window'));
      await _until(t, () => window.evaluate().isNotEmpty, 'voice stage with the avatar window');
      final avatar = find.byType(TalkingAvatar);
      await _until(t, () => avatar.evaluate().isNotEmpty, 'talking avatar');
      final st = t.state<TalkingAvatarState>(avatar);
      await _until(t, () => st.frames != null, 'avatar frames decoded', timeout: const Duration(seconds: 20));
      final rec = _PoseRecorder(st);
      await _settle(t, const Duration(milliseconds: 1200));
      await _shot(t, 'avatar-$id-0-idle');

      // Hold to talk: the fake recognizer hears the transcript; the reply is
      // then read aloud by the real voice service.
      _audio.reset();
      final g = await t.startGesture(t.getCenter(find.byKey(const ValueKey('hold-to-talk'))));
      await _settle(t, const Duration(milliseconds: 900));
      await _shot(t, 'avatar-$id-1-listening');
      await g.up();
      await t.pump();
      await _until(t, () => app.state.isResponding || _voice.speaking.value, 'reply started');
      await _shot(t, 'avatar-$id-2-thinking');
      await _until(t, () => _voice.speaking.value, 'coach speaking', timeout: const Duration(seconds: 40));
      final speakStart = rec.now;
      var hasAudio = false;
      var maxHop = 0.0;
      final shotsAt = [700, 1800, 3000, 4500];
      var shot = 0;
      final endBy = DateTime.now().add(const Duration(seconds: 90));
      while (_voice.speaking.value && DateTime.now().isBefore(endBy)) {
        if (_voice.lipSync.hasAudio) hasAudio = true;
        if (shot < shotsAt.length && rec.now - speakStart >= shotsAt[shot]) {
          await _shot(t, 'avatar-$id-3-speaking-${shot + 1}');
          shot++;
        }
        maxHop = maxHop < _audio.lastHop ? _audio.lastHop : maxHop;
        await Future<void>.delayed(const Duration(milliseconds: 16));
        await t.pump();
      }
      final speakMs = rec.now - speakStart;
      if (_voice.speaking.value) problems.add('still speaking after 90 s');
      await _settle(t, const Duration(milliseconds: 1500));
      await _shot(t, 'avatar-$id-4-after');
      final end = rec.last;
      rec.dispose();

      final m = rec.metrics(speakStart);
      final path = _audio.levelValues > 0 && _audio.starts > 0 ? 'native AVSpeechSynthesizer.write' : 'flutter_tts fallback (no native audio)';
      r.addAll({
        'voicePicked': _describe(DeviceVoiceService.pickVoiceDistinct(_voices, coach, coach.language)),
        'nativeSpeakCalls': [..._audio.speakCalls],
        'nativeTimeline': [..._audio.timeline],
        'chunksPlayedNatively': '${_audio.playedNatively.where((b) => b).length}/${_audio.playedNatively.length}',
        'audioSecondsPerCall': [for (final s in _audio.audioSeconds) double.parse(s.toStringAsFixed(2))],
        'audioPath': path,
        'nativeEvents': _audio.counts(),
        'levelValues': _audio.levelValues,
        'levelHopSeconds': maxHop,
        'markers': _audio.markers,
        'errors': [..._audio.errors],
        'lipSyncHasAudio': hasAudio,
        'speakingMs': speakMs,
        ...m,
        'restAfterEnd': {'mouth': end?.mouth, 'jaw': end?.jaw, 'mood': end?.speaking},
      });
      _log('avatar $id: $r');

      if (_audio.speakCalls.isEmpty) problems.add('the native audio path was never asked to speak');
      if (_audio.starts == 0) problems.add('no native "start" event (playback never started)');
      if (_audio.levelValues == 0) problems.add('no native loudness levels (AVSpeechSynthesizer.write produced no buffers)');
      if (!hasAudio) problems.add('LipSyncDriver.hasAudio never true');
      final distinct = (m['distinctVisemes'] as List).length;
      if (distinct < 3) problems.add('only $distinct distinct mouth shapes while speaking');
      if ((m['closuresBetweenWords'] as int) < 1) problems.add('the mouth never rested or closed between words');
      final firstBlink = m['firstBlinkMs'] as int?;
      if (firstBlink == null || firstBlink > 6000) problems.add('no blink within 6 s of the stage (first: $firstBlink ms)');
      if (end == null || end.mouth != 'rest' || end.jaw > 0.01) problems.add('mouth not at rest after speech: ${end?.mouth} jaw ${end?.jaw}');
      if (problems.isNotEmpty) fail(problems.join('; '));
    });
  }
}

// ---------------------------------------------------------------------------

/// Runs [body] as one test and records its outcome and measurements.
void _scenario(String name, Future<void> Function(WidgetTester t, Map<String, Object?> r) body) {
  testWidgets(name, (t) async {
    final r = <String, Object?>{};
    _scenarios[name] = {'result': 'did not finish', 'details': r};
    try {
      await body(t, r);
      _scenarios[name] = {'result': 'pass', 'details': r};
    } catch (e, st) {
      _scenarios[name] = {'result': 'FAIL', 'error': '$e', 'stack': st.toString().split('\n').take(6).join('\n'), 'details': r};
      await _shot(t, 'FAIL-${name.split(':').first.replaceAll(RegExp(r'[^\w]+'), '-')}');
      rethrow;
    } finally {
      await _voice.stop();
      await _teardownApp(t);
      _save('summary.json', utf8.encode(const JsonEncoder.withIndent('  ').convert(_summary)));
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}

class _App {
  _App(this.store, this.state);
  final StoreService store;
  final AppState state;
}

_App? _current;

Future<void> _teardownApp(WidgetTester t) async {
  final old = _current;
  _current = null;
  if (old == null) return;
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump();
  old.store.dispose();
}

/// A cold start as lib/main.dart builds it in a review build: createStoreService
/// (the fake store, subscribed through its own purchase), the offline coach,
/// the device voice service; a user who finished onboarding, on the chat tab.
Future<_App> _launch(WidgetTester t, {required String coach, CoachLanguage language = CoachLanguage.en}) async {
  await _teardownApp(t);
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await prefs.setBool('dw_onboarded', true);
  await prefs.setBool('dw_ai_consent', true);
  await prefs.setInt('dw_ai_consent_version', StorageService.aiConsentVersion);
  await prefs.setString('dw_coach', coach);
  await prefs.setString('dw_profile', '{"goals":["profile","conversations","dates"],"language":"${language.name}"}');

  final storage = await StorageService.create();
  final store = createStoreService();
  expect(store, isA<FakeStoreService>(), reason: 'the review build store, never StoreKit or a real purchase');
  await store.init();
  expect(await store.buy(), PurchaseResult.purchased);
  final state = AppState(storage: storage, ai: _PacedAI(MockAIService()), store: store);
  final app = _current = _App(store, state);
  await t.pumpWidget(RepaintBoundary(
    key: _rootKey,
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<StoreService>.value(value: store),
        ChangeNotifierProvider<AppState>.value(value: state),
        Provider<VoiceService>.value(value: _voice),
        Provider<SpeechService>.value(value: _speech),
      ],
      child: const DateWiseApp(initialTab: AppTab.chat),
    ),
  ));
  await _until(t, () => find.byKey(const ValueKey('composer')).evaluate().isNotEmpty, 'chat composer');
  expect(state.selectedCoach.id, coach);
  await _settle(t);
  return app;
}

/// The offline demo coach, streamed at a person's reading pace (about 12 words
/// a second) instead of 45: a reply streams long enough to tap during it.
class _PacedAI implements AIService {
  _PacedAI(this._inner);
  final AIService _inner;

  @override
  String get providerLabel => _inner.providerLabel;

  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) async* {
    await for (final chunk in _inner.streamReply(history: history, tier: tier, profile: profile, coach: coach)) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      yield chunk;
    }
  }
}

/// Speech recognition stand-in (the simulator cannot grant it): ready, and
/// "hears" [transcript] while the talk button is held.
class _FakeSpeech implements SpeechService {
  String transcript = '';
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
  }) async {
    onWords(transcript);
    return SpeechStart.started;
  }

  @override
  Future<String> stop() async => transcript;
  @override
  Future<void> cancel() async {}
}

/// The app's native speech backend, with its calls and events counted.
class _TapBackend implements SpeechAudioBackend {
  _TapBackend(this._inner) {
    _inner.events.listen(_on);
  }
  final SpeechAudioBackend _inner;
  final speakCalls = <Map<String, Object?>>[];
  final errors = <String>[];
  int starts = 0, levelEvents = 0, levelValues = 0, markers = 0, synthesized = 0, done = 0, interrupted = 0;
  double lastHop = 0;
  double? latency;

  /// Audio seconds rendered per speak call (the end of its last loudness window).
  final audioSeconds = <double>[];

  /// Whether each speak call's audio started playing natively.
  final playedNatively = <bool>[];

  /// What happened, in order, with milliseconds since the speak call it belongs to.
  final timeline = <String>[];
  final _sinceSpeak = Stopwatch();
  bool _sawLevels = false;

  void reset() {
    speakCalls.clear();
    errors.clear();
    audioSeconds.clear();
    playedNatively.clear();
    timeline.clear();
    starts = levelEvents = levelValues = markers = synthesized = done = interrupted = 0;
    latency = null;
  }

  void _mark(String what) => timeline.add('+${_sinceSpeak.elapsedMilliseconds}ms $what');

  void _on(SpeechAudioEvent e) {
    switch (e) {
      case SpeechAudioStarted(:final latency):
        starts++;
        this.latency = latency;
        if (playedNatively.isNotEmpty) playedNatively[playedNatively.length - 1] = true;
        _mark('start (latency ${(latency * 1000).toStringAsFixed(1)} ms)');
      case SpeechAudioLevels(:final values, :final hop, :final t0):
        levelEvents++;
        levelValues += values.length;
        lastHop = hop;
        if (!_sawLevels) _mark('first levels');
        _sawLevels = true;
        final end = t0 + values.length * hop;
        if (audioSeconds.isNotEmpty && end > audioSeconds.last) audioSeconds[audioSeconds.length - 1] = end;
      case SpeechAudioMarker():
        markers++;
      case SpeechAudioSynthesized():
        synthesized++;
        _mark('synthesized (${audioSeconds.isEmpty ? 0 : audioSeconds.last.toStringAsFixed(2)} s of audio)');
      case SpeechAudioDone(:final interrupted, :final reason):
        done++;
        _mark('done${interrupted ? ' interrupted: $reason' : ''}');
        if (interrupted) {
          this.interrupted++;
          errors.add('done interrupted: $reason');
        }
      case SpeechAudioError(:final message, :final started):
        _mark('error: $message (started: $started)');
        errors.add('error: $message (started: $started)');
    }
  }

  Map<String, Object?> counts() => {
        'start': starts,
        'levelsEvents': levelEvents,
        'markers': markers,
        'synthesized': synthesized,
        'done': done,
        'latencySeconds': latency,
      };

  @override
  Stream<SpeechAudioEvent> get events => _inner.events;

  @override
  Future<void> speak({required String text, String? voice, required String language, required double rate, required double pitch}) {
    speakCalls.add({'text': text, 'voice': voice, 'language': language, 'rate': rate, 'pitch': pitch});
    _sinceSpeak
      ..reset()
      ..start();
    _sawLevels = false;
    audioSeconds.add(0);
    playedNatively.add(false);
    _mark('speak #${speakCalls.length}');
    return _inner.speak(text: text, voice: voice, language: language, rate: rate, pitch: pitch);
  }

  @override
  Future<void> stop() {
    _mark('stop');
    return _inner.stop();
  }
}

/// One rendered avatar frame: what the painter drew.
class _Pose {
  _Pose(this.ms, this.speaking, this.mouth, this.jaw, this.blink);
  final int ms;
  final bool speaking;
  final String mouth; // viseme asset name, or 'rest'
  final double jaw;
  final bool blink;
}

/// Records every pose the avatar's ticker hands to its painter.
class _PoseRecorder {
  _PoseRecorder(this._st) {
    _st.pose.addListener(_on);
  }
  final TalkingAvatarState _st;
  final _clock = Stopwatch()..start();
  final poses = <_Pose>[];
  static final _mouths = {for (final v in Viseme.values) if (v.asset != null) v.asset!: v};

  int get now => _clock.elapsedMilliseconds;
  _Pose? get last => poses.isEmpty ? null : poses.last;

  void _on() {
    final p = _st.pose.value;
    String mouth = 'rest';
    var blink = false;
    for (final l in p.layers) {
      if (l.patch.startsWith('blink')) blink = true;
      // The topmost mouth patch with any opacity is the one seen.
      if (_mouths.containsKey(l.patch) && l.opacity > 0.5) mouth = l.patch;
    }
    poses.add(_Pose(now, _voice.speaking.value, mouth, p.jaw, blink));
  }

  void dispose() => _st.pose.removeListener(_on);

  Map<String, Object?> metrics(int speakStart) {
    final speaking = poses.where((p) => p.speaking && p.ms >= speakStart).toList();
    final distinct = <String>{for (final p in speaking) if (p.mouth != 'rest') p.mouth};
    bool closed(String m) => m == 'rest' || (_mouths[m]?.closed ?? false);
    var closures = 0;
    var sawOpen = false;
    var changes = 0;
    String? prev;
    for (final p in speaking) {
      if (prev != null && p.mouth != prev) changes++;
      if (!closed(p.mouth)) {
        sawOpen = true;
      } else if (sawOpen && prev != null && !closed(prev)) {
        closures++;
      }
      prev = p.mouth;
    }
    final blinks = <int>[];
    for (var i = 0; i < poses.length; i++) {
      if (poses[i].blink && (i == 0 || !poses[i - 1].blink)) blinks.add(poses[i].ms);
    }
    final jaws = [for (final p in speaking) p.jaw];
    final timeline = <String>[];
    for (final p in speaking) {
      if (timeline.isEmpty || !timeline.last.endsWith(' ${p.mouth}')) timeline.add('${p.ms - speakStart} ${p.mouth}');
    }
    return {
      'framesRecorded': poses.length,
      'framesWhileSpeaking': speaking.length,
      'distinctVisemes': distinct.toList()..sort(),
      'mouthChanges': changes,
      'closuresBetweenWords': closures,
      'jawMax': jaws.isEmpty ? 0 : jaws.reduce((a, b) => a > b ? a : b),
      'framesWithJaw': jaws.where((j) => j > 0.05).length,
      'blinkCount': blinks.length,
      'firstBlinkMs': blinks.isEmpty ? null : blinks.first,
      'blinkTimesMs': blinks,
      'mouthTimeline': timeline.take(80).toList(),
    };
  }
}

String? _describe(Map<String, String>? v) =>
    v == null ? null : '${v['name']} (${v['locale']}, quality ${v['quality'] ?? '?'}, ${v['identifier'] ?? 'no id'})';

int _userCount(_App app) => app.state.activeThread?.messages.where((m) => m.isUser).length ?? 0;

ChatMessage _lastCoach(_App app) => app.state.activeThread!.messages.lastWhere((m) => !m.isUser);

String _composerText(WidgetTester t) => t.widget<TextField>(find.byKey(const ValueKey('composer'))).controller!.text;

String _buttonState() => find.byKey(const ValueKey('stop')).evaluate().isNotEmpty ? 'stop' : 'send';

/// The last reply is the offline coach's whole answer to [userText] and is shown.
void _expectFullReply(WidgetTester t, _App app, String userText) {
  final thread = app.state.activeThread!;
  final last = thread.messages.last;
  expect(last.isUser, isFalse);
  expect(last.status, MessageStatus.ok);
  final coach = app.state.selectedCoach;
  final want = coach.language == CoachLanguage.es
      ? MockAIService.spanishReply(userText, coach)
      : MockAIService.englishReply(userText, coach);
  expect(last.text, want);
  final user = thread.messages.lastWhere((m) => m.isUser);
  expect(user.text, userText);
  expect(find.byKey(ValueKey('msg-${user.id}')), findsOneWidget, reason: 'the user message is shown');
  expect(find.byKey(ValueKey('msg-${last.id}')), findsOneWidget, reason: 'the reply is shown');
}

Future<void> _type(WidgetTester t, String text) async {
  final f = find.byKey(const ValueKey('composer'));
  await t.tap(f);
  await t.pump();
  await t.enterText(f, text);
  await t.pump();
}

Future<void> _tap(WidgetTester t, Key key) async {
  final f = find.byKey(key);
  await _until(t, () => f.evaluate().isNotEmpty, 'widget $key');
  await t.tap(f, warnIfMissed: false);
  await t.pump();
}

Future<void> _tapIn(WidgetTester t, Key key) async {
  final f = find.byKey(key);
  await _until(t, () => f.evaluate().isNotEmpty, 'widget $key');
  await t.ensureVisible(f);
  await _settle(t, const Duration(milliseconds: 300));
  await t.tap(f);
  await _settle(t, const Duration(milliseconds: 300));
}

/// Real time passes, with frames.
Future<void> _settle(WidgetTester t, [Duration d = const Duration(milliseconds: 1500)]) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await t.pump();
  }
}

Future<void> _until(WidgetTester t, FutureOr<bool> Function() cond, String what,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    if (await cond()) {
      await t.pump();
      return;
    }
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out after ${timeout.inSeconds}s waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await t.pump();
  }
}

void _log(String message) {
  // ignore: avoid_print
  print('[release-e2e] $message');
}

String _appOut() => '${Directory.systemTemp.path}/release-e2e';

final _saveFailures = <String>{};

void _save(String name, List<int> bytes) {
  for (final dir in [if (_outDirDefine.isNotEmpty) _outDirDefine, _appOut()]) {
    try {
      Directory(dir).createSync(recursive: true);
      File('$dir/$name').writeAsBytesSync(bytes);
    } catch (e) {
      if (_saveFailures.add(dir)) {
        _notes.add('cannot write to $dir: $e');
        _log('cannot write to $dir: $e');
      }
    }
  }
}

/// The whole app (as drawn by Flutter) and, on the voice stage, the avatar
/// window at 3x.
Future<void> _shot(WidgetTester t, String name) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      await t.pump();
      final root = _rootKey.currentContext?.findRenderObject();
      if (root is! RenderRepaintBoundary) return;
      await _savePng(root, '$name.png', t.view.devicePixelRatio);
      final win = find.descendant(of: find.byKey(const ValueKey('avatar-window')), matching: find.byType(RepaintBoundary));
      if (win.evaluate().isNotEmpty) {
        final ro = t.renderObject(win.first);
        if (ro is RenderRepaintBoundary) await _savePng(ro, '$name-avatar.png', 3);
      }
      return;
    } catch (e) {
      if (attempt == 2) _notes.add('screenshot $name failed: $e');
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }
}

Future<void> _savePng(RenderRepaintBoundary ro, String name, double ratio) async {
  final img = await ro.toImage(pixelRatio: ratio);
  try {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    _save(name, data!.buffer.asUint8List());
  } finally {
    img.dispose();
  }
}
