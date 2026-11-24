// Hosted live-avatar pilot (docs/avatar/PILOT_RUNBOOK.md): flag off, consent gate,
// every fallback path, the bridge protocol, the session client and the widget.
// A fake bridge and a fake Worker stand in for the WebView and the vendor; nothing
// here touches the network or a real vendor.
import 'dart:convert';
import 'dart:typed_data';

import 'package:datewise_ai/avatar/hosted/avatar_consent.dart';
import 'package:datewise_ai/avatar/hosted/avatar_engine.dart';
import 'package:datewise_ai/avatar/hosted/avatar_flags.dart';
import 'package:datewise_ai/avatar/hosted/avatar_session_api.dart';
import 'package:datewise_ai/avatar/hosted/bridge_protocol.dart';
import 'package:datewise_ai/avatar/hosted/hosted_avatar_controller.dart';
import 'package:datewise_ai/avatar/hosted/hosted_avatar_view.dart';
import 'package:datewise_ai/l10n/app_localizations.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_avatar_bridge.dart';

const _on = AvatarFlags(hosted: true, consentCopyApproved: true, vendorName: 'Simli');

typedef Rig = ({HostedAvatarController c, FakeAvatarBridge bridge, FakeSessionApi api, FakeAudio audio, AvatarConsent consent});

Future<AvatarConsent> givenConsent({bool consented = true}) async {
  SharedPreferences.setMockInitialValues({if (consented) 'dw_avatar_consent': '1:simli'});
  return AvatarConsent(await SharedPreferences.getInstance());
}

Rig build(
  AvatarConsent consent, {
  AvatarFlags flags = _on,
  bool entitled = true,
  Future<bool> Function()? ask,
  FakeAudio? audio,
  Duration connectTimeout = const Duration(seconds: 15),
}) {
  final bridge = FakeAvatarBridge();
  final api = FakeSessionApi();
  final a = audio ?? FakeAudio();
  final c = HostedAvatarController(
    api: api,
    bridge: bridge,
    audio: a,
    consent: consent,
    flags: flags,
    coachId: 'ava',
    askConsent: ask,
    hasEntitlement: () => entitled,
    connectTimeout: connectTimeout,
  );
  return (c: c, bridge: bridge, api: api, audio: a, consent: consent);
}

Future<Rig> make({
  AvatarFlags flags = _on,
  bool consented = true,
  bool entitled = true,
  Future<bool> Function()? ask,
  FakeAudio? audio,
  Duration connectTimeout = const Duration(seconds: 15),
}) async {
  final consent = await givenConsent(consented: consented);
  final r = build(consent, flags: flags, entitled: entitled, ask: ask, audio: audio, connectTimeout: connectTimeout);
  addTearDown(() async {
    await r.c.stop();
  });
  return r;
}

Future<void> goLive(HostedAvatarController c, FakeAvatarBridge b) async {
  await c.start();
  b.emit(const FirstFrameEvent(850));
  expect(c.state, HostedAvatarState.live);
}

void main() {
  group('flag off (the default): nothing changes', () {
    test('AvatarFlags default is off, and the build flag is off in tests', () {
      expect(const AvatarFlags().hostedEnabled, isFalse);
      expect(AvatarFlags.fromBuild().hostedEnabled, isFalse);
      expect(AvatarFlags.fromBuild().consentCopyApproved, isFalse);
    });

    test('the engine is the frame avatar and the hosted factory is never called', () {
      var built = false;
      final frame = FrameAvatarEngine(builder: (_) => const SizedBox());
      final e = selectAvatarEngine(flags: const AvatarFlags(), frame: frame, hosted: () {
        built = true;
        throw StateError('must not be built');
      });
      expect(e.kind, AvatarEngineKind.frame);
      expect(built, isFalse);
    });

    test('the frame engine leaves speech to the existing voice service', () async {
      final frame = FrameAvatarEngine(builder: (_) => const SizedBox());
      expect(await frame.speakReply('Hello'), isFalse);
    });

    test('start() with the flag off makes no network call and no bridge call', () async {
      final t = await make(flags: const AvatarFlags());
      await t.c.start();
      expect(t.c.state, HostedAvatarState.fallback);
      expect(t.c.fallbackReason, FallbackReason.flagOff);
      expect(t.api.opens, 0);
      expect(t.bridge.sent, isEmpty);
    });

    test('the remote kill switch turns a compiled-in flag off, and cannot turn one on', () {
      addTearDown(() => AvatarFlags.remoteKill.value = null);
      AvatarFlags.remoteKill.value = false;
      expect(_on.hostedEnabled, isFalse);
      AvatarFlags.remoteKill.value = true;
      expect(const AvatarFlags().hostedEnabled, isFalse);
      expect(_on.hostedEnabled, isTrue);
    });

    test('the pilot screen needs the flag AND a debug or test build', () {
      expect(const AvatarFlags().pilotScreenAvailable(testBuild: true), isFalse);
      expect(_on.pilotScreenAvailable(testBuild: true), isTrue);
      // flutter test is a debug (kDebugMode) run, so this is true here; in a release App Store
      // build kDebugMode is false and testBuild is false (production backend), so it is false.
      expect(_on.pilotScreenAvailable(testBuild: false), isTrue);
    });
  });

  group('consent gate: nothing is sent before consent', () {
    test('no consent and the owner has not approved the copy: no dialog, no call', () async {
      var asked = false;
      final t = await make(consented: false, flags: const AvatarFlags(hosted: true), ask: () async {
        asked = true;
        return true;
      });
      await t.c.start();
      expect(asked, isFalse);
      expect(t.c.fallbackReason, FallbackReason.noConsent);
      expect(t.api.opens, 0);
      expect(t.bridge.sent, isEmpty);
    });

    test('declined: fallback, nothing sent, nothing stored', () async {
      final t = await make(consented: false, ask: () async => false);
      await t.c.start();
      expect(t.c.fallbackReason, FallbackReason.noConsent);
      expect(t.api.opens, 0);
      expect(t.consent.has('Simli'), isFalse);
    });

    test('agreed: stored once, then the session opens; the next start does not ask again', () async {
      var asks = 0;
      final t = await make(consented: false, ask: () async {
        asks++;
        return true;
      });
      await goLive(t.c, t.bridge);
      expect(asks, 1);
      expect(t.consent.has('Simli'), isTrue);
      expect(t.api.opens, 1);
      await t.c.collapse();
      await t.c.start();
      expect(asks, 1);
    });

    test('consent names the vendor: consent to another vendor does not count', () async {
      final t = await make(consented: false, ask: () async => false);
      await t.consent.grant('Anam');
      expect(t.consent.has('Anam'), isTrue);
      expect(t.consent.has('Simli'), isFalse);
      await t.c.start();
      expect(t.api.opens, 0);
    });

    test('Delete my data removes it (stored under a dw_ key); withdraw removes only it', () async {
      final t = await make();
      expect(t.consent.has('Simli'), isTrue);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dw_coach', 'ava');
      await StorageService(prefs).clearAll();
      expect(t.consent.has('Simli'), isFalse);
      await t.consent.grant('Simli');
      await t.consent.withdraw();
      expect(t.consent.has('Simli'), isFalse);
    });

    test('no entitlement: fallback before any network call', () async {
      final t = await make(entitled: false);
      await t.c.start();
      expect(t.c.fallbackReason, FallbackReason.noEntitlement);
      expect(t.api.opens, 0);
    });
  });

  group('fallback paths (each one ends in the frame avatar, silently)', () {
    final refusals = {
      'SUBSCRIPTION_EXPIRED': FallbackReason.noEntitlement,
      'SUBSCRIPTION_REQUIRED': FallbackReason.noEntitlement,
      'AVATAR_ALLOWANCE': FallbackReason.allowanceExhausted,
      'AVATAR_DAILY_CAP': FallbackReason.dailyCap,
      'AVATAR_BUSY': FallbackReason.busy,
      'AVATAR_UNAVAILABLE': FallbackReason.unavailable,
      'GUARD_UNAVAILABLE': FallbackReason.unavailable,
      'SOMETHING_NEW': FallbackReason.sessionError,
    };
    refusals.forEach((code, reason) {
      test('Worker says $code -> $reason', () async {
        final t = await make();
        t.api.openError = AvatarRefusal(code, statusCode: 429);
        await t.c.start();
        expect(t.c.state, HostedAvatarState.fallback);
        expect(t.c.fallbackReason, reason);
        expect(t.bridge.sent, isEmpty, reason: 'no vendor token reached the page');
      });
    });

    test('offline when opening', () async {
      final t = await make();
      t.api.openError = const AvatarOffline();
      await t.c.start();
      expect(t.c.fallbackReason, FallbackReason.offline);
    });

    test('unexpected error when opening -> session error', () async {
      final t = await make();
      t.api.openError = StateError('boom');
      await t.c.start();
      expect(t.c.fallbackReason, FallbackReason.sessionError);
    });

    test('no first frame in time -> connect timeout, session ended', () async {
      final consent = await givenConsent();
      fakeAsync((async) {
        final t = build(consent, connectTimeout: const Duration(seconds: 5));
        final c = t.c, b = t.bridge, api = t.api;
        c.start();
        async.flushMicrotasks();
        expect(c.state, HostedAvatarState.connecting);
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();
        expect(c.fallbackReason, FallbackReason.connectTimeout);
        expect(b.sentOf<StopCommand>(), isNotEmpty);
        expect(api.ends, 1, reason: 'minutes are settled');
      });
    });

    final pageErrors = {
      'permission_denied': FallbackReason.permissionDenied,
      'webview': FallbackReason.webViewFailed,
      'sdk_missing': FallbackReason.webViewFailed,
      'session_refused': FallbackReason.sessionError,
      'media': FallbackReason.sessionError,
    };
    pageErrors.forEach((code, reason) {
      test('page error $code -> $reason', () async {
        final t = await make();
        await goLive(t.c, t.bridge);
        t.bridge.emit(ErrorEvent(code, 'detail'));
        await pumpEventQueue();
        expect(t.c.state, HostedAvatarState.fallback);
        expect(t.c.fallbackReason, reason);
        expect(t.api.ends, 1);
      });
    });

    test('WebView fails while connecting', () async {
      final t = await make();
      await t.c.start();
      t.bridge.emit(const ErrorEvent('webview', 'load failed'));
      await pumpEventQueue();
      expect(t.c.fallbackReason, FallbackReason.webViewFailed);
    });

    test('vendor ends the session (max or idle): fallback, minutes settled', () async {
      final t = await make();
      await goLive(t.c, t.bridge);
      t.bridge.emit(const EndedEvent('idle'));
      await pumpEventQueue();
      expect(t.c.fallbackReason, FallbackReason.sessionEnded);
      expect(t.api.ends, 1);
    });

    test('poor network reported repeatedly -> fallback; one good report resets the count', () async {
      final t = await make();
      await goLive(t.c, t.bridge);
      t.bridge.emit(const NetworkEvent(poor: true, rttMs: 900));
      t.bridge.emit(const NetworkEvent(poor: true));
      t.bridge.emit(const NetworkEvent(poor: false, rttMs: 80));
      t.bridge.emit(const NetworkEvent(poor: true));
      t.bridge.emit(const NetworkEvent(poor: true));
      expect(t.c.state, HostedAvatarState.live);
      t.bridge.emit(const NetworkEvent(poor: true));
      await pumpEventQueue();
      expect(t.c.fallbackReason, FallbackReason.poorNetwork);
    });

    test('heartbeats failing (network drop) -> offline fallback; one failure is tolerated', () async {
      final consent = await givenConsent();
      fakeAsync((async) {
        final t = build(consent);
        final c = t.c, b = t.bridge;
        t.api.beatError = const AvatarOffline();
        c.start().then((_) => b.emit(const FirstFrameEvent(500)));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(c.state, HostedAvatarState.live, reason: 'one miss is tolerated');
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();
        expect(c.fallbackReason, FallbackReason.offline);
      });
    });

    test('heartbeat refusal from the Worker (allowance) ends the session', () async {
      final consent = await givenConsent();
      fakeAsync((async) {
        final t = build(consent);
        final c = t.c;
        t.api.beatError = const AvatarRefusal('AVATAR_ALLOWANCE', statusCode: 429);
        c.start();
        async.flushMicrotasks();
        t.bridge.emit(const FirstFrameEvent(400));
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(c.fallbackReason, FallbackReason.allowanceExhausted);
      });
    });

    test('heartbeat reports usage; max length ends the session', () async {
      final consent = await givenConsent();
      fakeAsync((async) {
        final t = build(consent);
        final c = t.c, api = t.api;
        api.session = const AvatarSession(
            sessionId: 'av_000000000000000000000001', vendor: 'simli', sessionToken: 't', maxSeconds: 100, idleSeconds: 60, heartbeatSeconds: 30, sampleRate: 16000, usedSeconds: 0, totalSeconds: 3600);
        c.start();
        async.flushMicrotasks();
        t.bridge.emit(const FirstFrameEvent(400));
        async.elapse(const Duration(seconds: 61));
        async.flushMicrotasks();
        expect(c.usedSeconds, 60);
        async.elapse(const Duration(seconds: 50));
        async.flushMicrotasks();
        expect(c.fallbackReason, FallbackReason.sessionEnded);
        expect(api.ends, 1);
      });
    });

    test('backgrounding ends the live session', () async {
      final t = await make();
      await goLive(t.c, t.bridge);
      await t.c.onBackgrounded();
      expect(t.c.fallbackReason, FallbackReason.backgrounded);
      expect(t.api.ends, 1);
    });

    test('stopped while the Worker call is in flight: the minutes are given back', () async {
      final t = await make();
      final f = t.c.start();
      await t.c.stop();
      await f;
      await pumpEventQueue();
      expect(t.api.ends, 1);
      expect(t.bridge.sentOf<StartCommand>(), isEmpty);
    });
  });

  group('live session: the reply text is the source of truth', () {
    test('start sends only the short-lived token and audio settings to the page', () async {
      final t = await make();
      await goLive(t.c, t.bridge);
      final s = t.bridge.sentOf<StartCommand>().single;
      final json = jsonDecode(s.encode()) as Map;
      expect(json['v'], 1);
      expect(json['sessionToken'], 'tok');
      expect(json['audio'], {'encoding': 'pcm_s16le', 'sampleRate': 16000, 'channels': 1});
      expect(t.c.firstFrameMs, 850);
    });

    test('speakReply turns exactly the reply text into audio chunks, the last one marked', () async {
      final t = await make();
      await goLive(t.c, t.bridge);
      expect(await t.c.speakReply('Hola, ¿cómo estás?'), isTrue);
      expect(t.audio.texts, ['Hola, ¿cómo estás?']);
      final speaks = t.bridge.sentOf<SpeakCommand>().toList();
      expect(speaks.length, 2);
      expect(speaks.first.last, isFalse);
      expect(speaks.last.last, isTrue);
      expect(speaks.first.sampleRate, 24000);
      expect(speaks.map((s) => s.id).toSet().length, 1);
    });

    test('speakReply returns false (caller speaks it the usual way) when not live or text is empty', () async {
      final t = await make();
      expect(await t.c.speakReply('Hi'), isFalse);
      await goLive(t.c, t.bridge);
      expect(await t.c.speakReply('   '), isFalse);
      expect(t.bridge.sentOf<SpeakCommand>(), isEmpty);
    });

    test('audio failure closes the live session and returns false', () async {
      final t = await make(audio: FakeAudio(fail: true));
      await goLive(t.c, t.bridge);
      expect(await t.c.speakReply('Hi'), isFalse);
      expect(t.c.fallbackReason, FallbackReason.audioUnavailable);
      expect(t.api.ends, 1);
    });

    test('state events drive the activity: listening / thinking / speaking', () async {
      final t = await make();
      await goLive(t.c, t.bridge);
      for (final a in [AvatarActivity.listening, AvatarActivity.thinking, AvatarActivity.speaking]) {
        t.bridge.emit(StateEvent(a));
        expect(t.c.activity, a);
      }
      t.bridge.emit(const MicEvent('prompt'));
      expect(t.c.micState, 'prompt');
    });

    test('interrupt sends the command only while live; collapse ends the session', () async {
      final t = await make();
      await t.c.interrupt();
      expect(t.bridge.sentOf<InterruptCommand>(), isEmpty);
      await goLive(t.c, t.bridge);
      await t.c.interrupt();
      expect(t.bridge.sentOf<InterruptCommand>().length, 1);
      await t.c.collapse();
      expect(t.c.fallbackReason, FallbackReason.collapsed);
      expect(t.bridge.sentOf<StopCommand>().length, 1);
      expect(t.api.ends, 1);
    });
  });

  group('bridge protocol', () {
    test('events decode; malformed, foreign-version and unknown messages are ignored', () {
      expect(decodeBridgeEvent('{"v":1,"type":"ready"}'), isA<ReadyEvent>());
      expect((decodeBridgeEvent('{"v":1,"type":"state","state":"speaking"}') as StateEvent).activity, AvatarActivity.speaking);
      expect((decodeBridgeEvent('{"v":1,"type":"firstFrame","ms":1234.4}') as FirstFrameEvent).ms, 1234);
      expect((decodeBridgeEvent('{"v":1,"type":"network","quality":"poor","rttMs":300}') as NetworkEvent).poor, isTrue);
      expect((decodeBridgeEvent('{"v":1,"type":"error","code":"permission_denied"}') as ErrorEvent).code, 'permission_denied');
      expect((decodeBridgeEvent('{"v":1,"type":"ended","reason":"max"}') as EndedEvent).reason, 'max');
      for (final bad in ['', 'nope', '[]', '{"type":"ready"}', '{"v":2,"type":"ready"}', '{"v":1,"type":"mystery"}', '{"v":1,"type":"state","state":"dancing"}', '{"v":1,"type":"firstFrame","ms":-4}', 'x' * 9000]) {
        expect(decodeBridgeEvent(bad), isNull, reason: bad.length > 40 ? 'long' : bad);
      }
    });

    test('commands encode to versioned JSON the page understands', () {
      expect(jsonDecode(const InterruptCommand().encode()), {'v': 1, 'type': 'interrupt'});
      expect(jsonDecode(const StopCommand().encode()), {'v': 1, 'type': 'stop'});
      final audio = jsonDecode(SpeakCommand.audio(id: 'r1', pcm16: Uint8List.fromList([1, 0]), sampleRate: 24000, last: true).encode()) as Map;
      expect(audio['audio'], base64Encode([1, 0]));
      expect(audio['sampleRate'], 24000);
      expect(audio['last'], isTrue);
      final text = jsonDecode(const SpeakCommand.text(id: 'v1', text: 'Hi').encode()) as Map;
      expect(text['text'], 'Hi');
      expect(text.containsKey('audio'), isFalse);
    });
  });

  group('session client (Worker /v1/avatar/*)', () {
    const body = {
      'sessionId': 'av_000000000000000000000001',
      'vendor': 'anam',
      'sessionToken': 'short',
      'maxSeconds': 600,
      'idleSeconds': 60,
      'heartbeatSeconds': 30,
      'audio': {'encoding': 'pcm_s16le', 'sampleRate': 24000, 'channels': 1},
      'allowance': {'usedSeconds': 120, 'totalSeconds': 3600},
    };

    test('sends the StoreKit header and parses the session', () async {
      late http.Request seen;
      final api = AvatarSessionApi(
        baseUrl: 'https://worker.example/',
        entitlement: () => 'a.b.c',
        clientFactory: () => MockClient((r) async {
          seen = r;
          return http.Response(jsonEncode(body), 200);
        }),
      );
      final s = await api.open(coachId: 'sofia', language: 'es');
      expect(seen.url.toString(), 'https://worker.example/v1/avatar/session');
      expect(seen.headers['X-DateWise-Entitlement'], 'a.b.c');
      expect(jsonDecode(seen.body), {'coachId': 'sofia', 'language': 'es'});
      expect(s.vendor, 'anam');
      expect(s.sampleRate, 24000);
      expect(s.usedSeconds, 120);
    });

    test('no entitlement: refused before any HTTP request', () async {
      var calls = 0;
      final api = AvatarSessionApi(entitlement: () => null, clientFactory: () => MockClient((r) async {
            calls++;
            return http.Response('{}', 200);
          }));
      await expectLater(api.open(coachId: 'ava'), throwsA(isA<AvatarRefusal>().having((r) => r.code, 'code', 'SUBSCRIPTION_REQUIRED')));
      expect(calls, 0);
    });

    test('error bodies map to codes; junk bodies to HTTP_n; a bad success body is unavailable', () async {
      AvatarSessionApi with_(http.Response Function() r) => AvatarSessionApi(baseUrl: 'https://w.example', entitlement: () => 'a.b.c', clientFactory: () => MockClient((_) async => r()));
      await expectLater(with_(() => http.Response('{"code":"AVATAR_ALLOWANCE"}', 429)).open(coachId: 'ava'), throwsA(isA<AvatarRefusal>().having((r) => r.code, 'code', 'AVATAR_ALLOWANCE')));
      await expectLater(with_(() => http.Response('<html>', 502)).open(coachId: 'ava'), throwsA(isA<AvatarRefusal>().having((r) => r.code, 'code', 'HTTP_502')));
      await expectLater(with_(() => http.Response('{"sessionId":"x"}', 200)).open(coachId: 'ava'), throwsA(isA<AvatarRefusal>().having((r) => r.code, 'code', 'AVATAR_UNAVAILABLE')));
    });

    test('a network failure is AvatarOffline', () async {
      final api = AvatarSessionApi(baseUrl: 'https://w.example', entitlement: () => 'a.b.c', clientFactory: () => MockClient((_) async => throw http.ClientException('down')));
      await expectLater(api.open(coachId: 'ava'), throwsA(isA<AvatarOffline>()));
    });

    test('heartbeat and end read usedSeconds', () async {
      final api = AvatarSessionApi(baseUrl: 'https://w.example', entitlement: () => 'a.b.c', clientFactory: () => MockClient((_) async => http.Response('{"ok":true,"usedSeconds":45}', 200)));
      expect(await api.heartbeat('av_x'), 45);
      expect(await api.end('av_x'), 45);
    });
  });

  group('HostedAvatarView', () {
    Widget app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          home: Scaffold(body: SizedBox(width: 300, height: 300, child: child)),
        );
    HostedAvatarView view(HostedAvatarController c) => HostedAvatarView(
          controller: c,
          coachName: 'Ava',
          fallback: const ColoredBox(key: ValueKey('frame-avatar'), color: Colors.pink),
          webViewBuilder: (_) => const SizedBox(key: ValueKey('web')),
        );

    testWidgets('idle: only the frame avatar, no WebView, no buttons', (t) async {
      final m = await make();
      await t.pumpWidget(app(view(m.c)));
      expect(find.byKey(const ValueKey('frame-avatar')), findsOneWidget);
      expect(find.byKey(const ValueKey('web')), findsNothing);
      expect(find.byKey(const ValueKey('hosted-avatar-collapse')), findsNothing);
    });

    testWidgets('live: web face with a VoiceOver label and a collapse button; collapse then expand', (t) async {
      final m = await make();
      await t.pumpWidget(app(view(m.c)));
      await t.runAsync(() async {
        await m.c.start();
        m.bridge.emit(const FirstFrameEvent(700));
      });
      await t.pump();
      expect(find.byKey(const ValueKey('web')), findsOneWidget);
      expect(find.bySemanticsLabel('Live video of Ava'), findsOneWidget);
      expect(find.bySemanticsLabel('Hide live video'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('hosted-avatar-collapse')));
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump();
      expect(find.byKey(const ValueKey('web')), findsNothing);
      expect(find.byKey(const ValueKey('frame-avatar')), findsOneWidget);
      expect(find.bySemanticsLabel('Show live video'), findsOneWidget);
      expect(find.byKey(const ValueKey('hosted-avatar-expand')), findsOneWidget);
    });

    testWidgets('it never blocks reading or typing: no modal, the text field stays usable', (t) async {
      final m = await make();
      final field = TextEditingController();
      await t.pumpWidget(app(Column(children: [SizedBox(height: 150, child: view(m.c)), TextField(controller: field)])));
      await t.runAsync(() async {
        await m.c.start();
        m.bridge.emit(const FirstFrameEvent(700));
      });
      await t.pump();
      await t.enterText(find.byType(TextField), 'typing works');
      expect(field.text, 'typing works');
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Spanish: labels and the consent text name the vendor', (t) async {
      final m = await make();
      await t.pumpWidget(app(view(m.c), locale: const Locale('es')));
      await t.runAsync(() async {
        await m.c.start();
        m.bridge.emit(const FirstFrameEvent(700));
      });
      await t.pump();
      expect(find.bySemanticsLabel('Video en vivo de Ava'), findsOneWidget);
      expect(find.bySemanticsLabel('Ocultar el video en vivo'), findsOneWidget);
      final es = await AppLocalizations.delegate.load(const Locale('es'));
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(es.avatarConsentBody('Simli'), contains('Simli'));
      expect(en.avatarConsentBody('Anam'), contains('Anam'));
      expect(en.avatarConsentBody('Anam'), isNot(contains('Simli')));
      expect(es.avatarConsentAgree, isNot(en.avatarConsentAgree));
    });
  });
}
