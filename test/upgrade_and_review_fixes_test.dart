// Upgrading from v1 (1.0.x) and the final-review fixes: v1 profile fields
// are purged and never sent, v1 users go through the v2 onboarding (18+),
// v1 photo messages, chat persistence and cancellation, the store price,
// the bundled assets and hold-to-talk.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/persona.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';
import 'package:datewise_ai/widgets/dw.dart';

import 'helpers.dart';

/// What a v1.0.2 user has on the device.
const _v1Profile =
    '{"gender":"male","age":34,"interestedIn":"women","goal":"serious","app":"hinge","city":"Austin"}';

const _v1Thread = '[{"id":"t1","title":"Photo review","createdAt":"2025-05-01T10:00:00.000",'
    '"updatedAt":"2025-05-01T10:00:00.000","messages":['
    '{"id":"m1","role":"user","text":"","createdAt":"2025-05-01T10:00:00.000","imageBase64":"QUFBQUFBQUE="},'
    '{"id":"m2","role":"coach","text":"","createdAt":"2025-05-01T10:00:01.000","analysis":{"score":7}},'
    '{"id":"m3","role":"user","text":"Thanks, what about my bio?","createdAt":"2025-05-01T10:01:00.000","imageBase64":null}'
    ']}]';

Map<String, Object> v1Prefs() => {
      'dw_onboarded': true,
      'dw_intro_seen': true,
      'dw_tier': 'magnet',
      'dw_profile': _v1Profile,
      'dw_threads': _v1Thread,
      'dw_analysis_cache': '[{"key":"deep_abc","analysis":{"score":7}}]',
      'dw_batch_cache': '[]',
    };

/// Legacy values that must never reach a prompt or a request.
const _legacyMarkers = ['Austin', '34', 'hinge', 'Hinge', '"gender"', '"age"', '"city"', '"interestedIn"',
    '"goal"', '"app"', 'interested in', 'Something serious', 'years old', 'looking for'];

/// A coach stream driven by the test.
class _ControlledAI implements AIService {
  final streams = <StreamController<String>>[];
  final cancels = <int>[];

  /// When set, canceling never completes (a misbehaving stream).
  bool hangOnCancel = false;

  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) {
    final i = streams.length;
    late final StreamController<String> c;
    c = StreamController<String>(onCancel: () {
      cancels.add(i);
      return hangOnCancel ? Completer<void>().future : null;
    });
    streams.add(c);
    return c.stream;
  }

  @override
  String get providerLabel => 'controlled';
}

/// An HTTP client whose request never answers until it is closed.
class _HangingClient extends http.BaseClient {
  final _response = Completer<http.StreamedResponse>();
  bool closed = false;
  bool sent = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sent = true;
    return _response.future;
  }

  @override
  void close() {
    closed = true;
    if (!_response.isCompleted) _response.completeError(http.ClientException('closed'));
  }
}

/// Answers headers, then never sends a byte until closed.
class _SilentStreamClient extends http.BaseClient {
  final _body = StreamController<List<int>>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(_body.stream, 200);

  @override
  void close() {
    if (closed) return;
    closed = true;
    _body.addError(http.ClientException('closed'));
    _body.close();
  }
}

/// In-app purchase plugin whose product query fails the first time.
class _FlakyIap implements InAppPurchase {
  int queries = 0;
  int restores = 0;
  final _purchases = StreamController<List<PurchaseDetails>>.broadcast();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _purchases.stream;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async {
    queries++;
    if (queries == 1) throw PlatformException(code: 'network');
    return ProductDetailsResponse(
      productDetails: [
        ProductDetails(
          id: StoreConfig.productId,
          title: 'DateWise Premium',
          description: 'Monthly',
          price: r'$9.99',
          rawPrice: 9.99,
          currencyCode: 'USD',
        ),
      ],
      notFoundIDs: const [],
    );
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async => restores++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Speech recognition the test controls: [start] completes when the test says.
class _FakeSpeech implements SpeechService {
  Completer<SpeechStart>? pendingStart;
  SpeechStart nextResult = SpeechStart.started;
  bool listening = false;
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  String words = 'Help me reply';
  bool holdStart = false;

  @override
  bool available = true;

  @override
  Future<bool> ensureReady() async => available;

  @override
  Future<void> recheckPermission() async {}

  @override
  Future<SpeechStart> start({
    required String localeId,
    required void Function(String words) onWords,
    void Function()? onUnsupported,
  }) async {
    starts++;
    if (holdStart) {
      pendingStart = Completer<SpeechStart>();
      final r = await pendingStart!.future;
      listening = r == SpeechStart.started;
      return r;
    }
    listening = nextResult == SpeechStart.started;
    return nextResult;
  }

  @override
  Future<String> stop() async {
    stops++;
    final was = listening;
    listening = false;
    return was ? words : '';
  }

  @override
  Future<void> cancel() async {
    cancels++;
    listening = false;
  }
}

Future<(AppState, StorageService, AIService)> _make(Map<String, Object> prefs, {AIService? ai}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storage = await StorageService.create();
  final coach = ai ?? _ControlledAI();
  return (AppState(storage: storage, ai: coach, store: FakeStoreService(entitled: true)), storage, coach);
}

void main() {
  group('upgrading from v1: legacy profile fields', () {
    test('are purged from dw_profile on first load and never reach prompts or requests', () async {
      final prefs = {...v1Prefs(), 'dw_memory_on': true, 'dw_memory_text': 'I get nervous on first dates'};
      final (state, _, _) = await _make(prefs);
      final stored = await SharedPreferences.getInstance();

      // Nothing v2 was left in the v1 profile, so it is removed entirely.
      final raw = stored.getString('dw_profile');
      for (final k in legacyProfileKeys) {
        expect(raw == null || !(jsonDecode(raw) as Map).containsKey(k), isTrue, reason: k);
      }
      expect(raw, isNull);
      expect(stored.getString('dw_analysis_cache'), isNull, reason: 'v1 photo caches are deleted');
      expect(stored.getString('dw_batch_cache'), isNull);

      // The request the app would send: system prompt + profile JSON.
      final backend = BackendAIService(endpoint: 'https://coach.example.com');
      final history = [ChatMessage(id: 'u', role: MessageRole.user, text: 'Hi', createdAt: DateTime(2026))];
      final body = jsonEncode(backend.buildPayload(history, AppState.aiTier, state.profileForCoach, state.selectedCoach));
      final prompt = CoachPersona.systemPrompt(AppState.aiTier, profile: state.profileForCoach, coach: state.selectedCoach);
      for (final m in _legacyMarkers) {
        expect(body.contains(m), isFalse, reason: 'request contains "$m"');
        expect(prompt.contains(m), isFalse, reason: 'prompt contains "$m"');
      }
      expect(prompt, contains('I get nervous on first dates'), reason: 'memory is sent while ON');

      // After the v2 onboarding, the stored profile holds only v2 fields.
      await state.completeOnboarding(
          goals: [CoachingGoal.dates], language: CoachLanguage.en, coachId: 'ava', adultConfirmed: true);
      final after = jsonDecode(stored.getString('dw_profile')!) as Map<String, dynamic>;
      expect(after.keys.toSet(), {'goals', 'language'});
      final payload = backend.buildPayload(history, AppState.aiTier, state.profileForCoach, state.selectedCoach);
      expect((payload['profile'] as Map).keys.toSet(), {'goals', 'language', 'memory'});
    });

    test('a v2 profile with stray legacy keys keeps its v2 fields and stays onboarded', () async {
      final (state, _, _) = await _make({
        'dw_onboarded': true,
        'dw_coach': 'sofia',
        'dw_profile': '{"goals":["profile"],"language":"es","age":29,"city":"Lima","app":"tinder"}',
      });
      final stored = await SharedPreferences.getInstance();
      expect(jsonDecode(stored.getString('dw_profile')!), {'goals': ['profile'], 'language': 'es'});
      expect(state.onboarded, isTrue);
      expect(state.profile!.toJson().keys.toSet(), {'goals', 'language'});
      expect(state.profileForCoach!.summary, isNot(contains('Lima')));
    });

    test('UserProfile.fromJson ignores legacy keys and toJson never writes them', () {
      final p = UserProfile.fromJson(jsonDecode(_v1Profile) as Map<String, dynamic>);
      expect(p.toJson().keys.toSet(), {'goals', 'language'});
      expect(p.summary, 'prefers English');
    });
  });

  group('upgrading from v1: onboarding', () {
    test('a v1 user is routed through the v2 onboarding once', () async {
      final (state, _, _) = await _make(v1Prefs());
      expect(state.onboarded, isFalse);
      expect(state.threads, hasLength(1), reason: 'conversations are kept');
      await state.completeOnboarding(
          goals: [CoachingGoal.profile], language: CoachLanguage.en, coachId: 'ava', adultConfirmed: true);
      // Next launch: onboarded.
      final storage = await StorageService.create();
      final relaunched = AppState(storage: storage, ai: _ControlledAI(), store: FakeStoreService(entitled: true));
      expect(relaunched.onboarded, isTrue);
    });

    testWidgets('the upgrader sees the welcome screen, goals, language and the 18+ step', (tester) async {
      await pumpApp(tester, prefs: v1Prefs());
      expect(find.byKey(const ValueKey('welcome')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('get-started')));
      await tester.tap(find.byKey(const ValueKey('get-started')));
      await tester.pumpAndSettle();
      expect(find.text('What would you like help with?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('goal-profile')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Choose your language'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('age-confirm')), findsOneWidget);
      expect(find.byKey(const ValueKey('age-under')), findsOneWidget);
    });

    testWidgets('a Spanish-device upgrader gets Spanish (no stored language → device language)', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('es', 'MX')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final app = await pumpApp(tester, prefs: v1Prefs());
      expect(app.state.chosenLanguage, isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('get-started')));
      await tester.tap(find.byKey(const ValueKey('get-started')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('goal-profile')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Elige tu idioma'), findsOneWidget);
    });
  });

  group('v1 photo messages', () {
    test('photo data is dropped from storage; the turn is kept as a placeholder for the model', () async {
      final (state, _, _) = await _make({...v1Prefs(), 'dw_profile': '{"goals":["profile"],"language":"en"}'});
      final stored = await SharedPreferences.getInstance();
      final raw = stored.getString('dw_threads')!;
      expect(raw, isNot(contains('imageBase64')));
      expect(raw, isNot(contains('QUFBQUFBQUE=')));
      expect(raw, isNot(contains('"analysis"')));
      final msgs = state.threads.single.messages;
      expect(msgs.map((m) => m.isPhotoOnly), [true, true, false]);
      final sent = BackendAIService(endpoint: 'https://coach.example.com')
          .buildMessages(msgs, AppState.aiTier, null, Coaches.ava)
          .skip(1)
          .map((m) => m['content'])
          .toList();
      expect(sent, ['[shared a photo for review]', '[gave a photo critique]', 'Thanks, what about my bio?']);
    });

    testWidgets('photo-only bubbles show a short note instead of an empty bubble', (tester) async {
      await pumpApp(tester,
          prefs: {...onboardedPrefs(), 'dw_threads': _v1Thread}, tab: AppTab.chat);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-placeholder')), findsNWidgets(2));
      expect(find.text('Photo from an earlier version (no longer available)'), findsNWidgets(2));
    });
  });

  group('chat persistence', () {
    test('the user message is saved as soon as it is sent; a partial reply saves as incomplete', () async {
      final (state, storage, ai) = await _make(onboardedPrefs());
      final coach = ai as _ControlledAI;
      final sending = state.sendMessage('Is this opener ok?');
      await pumpEventQueue();
      expect(storage.loadThreads().first.messages.where((m) => m.isUser).map((m) => m.text), ['Is this opener ok?']);

      coach.streams.single.add('Half a rep');
      await pumpEventQueue();
      // Anything that saves mid-reply (here: the raw JSON of the thread).
      final partial = ChatMessage.fromJson(state.activeThread!.messages.last.toJson());
      expect(partial.status, MessageStatus.stopped);
      expect(partial.isComplete, isFalse);
      expect(ChatMessage.fromJson({'id': 'x', 'role': 'coach', 'text': 'Hal', 'isStreaming': true}).status,
          MessageStatus.stopped);

      await coach.streams.single.close();
      await sending;
      expect(storage.loadThreads().first.messages.last.status, MessageStatus.ok);
      expect(storage.loadThreads().first.messages.last.text, 'Half a rep');
    });
  });

  group('cancellation', () {
    test('Stop aborts a request still waiting for headers at once and closes the client', () async {
      final client = _HangingClient();
      final backend = BackendAIService(endpoint: 'https://coach.example.com', clientFactory: () => client);
      final errors = <Object>[];
      final sub = backend
          .streamReply(history: const [], tier: AppState.aiTier)
          .listen((_) {}, onError: errors.add);
      await pumpEventQueue();
      expect(client.sent, isTrue);
      await sub.cancel().timeout(const Duration(milliseconds: 200));
      expect(client.closed, isTrue);
      await pumpEventQueue();
      expect(errors, isEmpty, reason: 'no error after cancel');
    });

    test('Stop aborts a silent stream at once', () async {
      final client = _SilentStreamClient();
      final backend = BackendAIService(endpoint: 'https://coach.example.com', clientFactory: () => client);
      final sub = backend.streamReply(history: const [], tier: AppState.aiTier).listen((_) {});
      await pumpEventQueue();
      await sub.cancel().timeout(const Duration(milliseconds: 200));
      expect(client.closed, isTrue);
    });

    test('cancel and deletes never wait on the stream; a new send waits for the stop', () async {
      final ai = _ControlledAI()..hangOnCancel = true;
      final (state, _, _) = await _make(onboardedPrefs(), ai: ai);
      unawaited(state.sendMessage('First'));
      await pumpEventQueue();
      expect(state.isResponding, isTrue);

      // Stop, then send straight away: the new message goes out after the
      // first reply has stopped, never alongside it.
      final stop = state.cancelReply();
      final second = state.sendMessage('Second');
      await stop.timeout(const Duration(milliseconds: 200));
      await pumpEventQueue();
      expect(ai.cancels, [0]);
      expect(ai.streams, hasLength(2));
      final msgs = state.activeThread!.messages;
      expect(msgs.where((m) => m.status == MessageStatus.stopped), hasLength(1));

      // Deleting mid-reply returns immediately although the stream hangs.
      await state.deleteAllConversations().timeout(const Duration(milliseconds: 200));
      expect(await second.timeout(const Duration(milliseconds: 200)), isTrue);
      expect(state.isResponding, isFalse);
      expect(state.threads, isEmpty);
    });

    test('Delete my data mid-reply leaves no dw_ keys behind', () async {
      final ai = _ControlledAI()..hangOnCancel = true;
      final (state, _, _) = await _make(onboardedPrefs(), ai: ai);
      unawaited(state.sendMessage('Hello'));
      await pumpEventQueue();
      await state.deleteMyData().timeout(const Duration(milliseconds: 200));
      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('dw_')), isEmpty);
    });
  });

  group('store', () {
    test('the entitlement is read even when the product query fails; refresh retries the product', () async {
      final iap = _FlakyIap();
      final store = AppStoreService(iap: iap);
      await store.init();
      expect(store.ready, isTrue);
      expect(iap.restores, 1, reason: 'entitlement refreshed although the product failed');
      expect(store.canPurchase, isFalse);
      expect(store.storePrice, isNull);
      await store.refresh();
      expect(iap.queries, 2);
      expect(store.canPurchase, isTrue);
      expect(store.storePrice, r'$9.99');
    });

    testWidgets('without a StoreKit price: no hard-coded price, Subscribe disabled', (tester) async {
      await pumpApp(tester, prefs: onboardedPrefs(), store: FakeStoreService(price: null));
      expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
      final d = tester.widget<Text>(find.byKey(const ValueKey('paywall-disclosure'))).data!;
      expect(d, isNot(contains(r'$')));
      expect(d, contains('price shown by the App Store'));
      expect(d, contains('Settings › Apple ID › Subscriptions'));
      expect(find.textContaining('9.99'), findsNothing);
      expect(find.text('Price shown by the App Store'), findsOneWidget);
      final button = tester.widget<DwButton>(find.byKey(const ValueKey('paywall-subscribe')));
      expect(button.onPressed, isNull);
      expect(button.label, 'Subscribe');
    });

    testWidgets('the same in Spanish', (tester) async {
      await pumpApp(tester, prefs: spanishPrefs(), store: FakeStoreService(price: null));
      final d = tester.widget<Text>(find.byKey(const ValueKey('paywall-disclosure'))).data!;
      expect(d, contains('precio indicado por el App Store'));
      expect(find.textContaining('9.99'), findsNothing);
    });
  });

  group('bundled assets', () {
    testWidgets('only coach portraits, the app icon and fonts are bundled (no stock photos)', (tester) async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets();
      expect(assets.where((a) => a.startsWith('assets/coaches/')), hasLength(8));
      final images = assets.where((a) => RegExp(r'\.(jpe?g|png|webp|gif|heic)$', caseSensitive: false).hasMatch(a));
      for (final a in images) {
        expect(a.startsWith('assets/coaches/') || a.startsWith('assets/icon/'), isTrue, reason: a);
      }
      for (final a in assets) {
        expect(
          a.startsWith('assets/coaches/') ||
              a.startsWith('assets/fonts/') ||
              a.startsWith('assets/icon/') ||
              a.startsWith('packages/') ||
              a.startsWith('shaders/') ||
              a == 'fonts/MaterialIcons-Regular.otf',
          isTrue,
          reason: 'unexpected bundled asset $a',
        );
      }
      expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('- images/')));
      expect(Directory('images').existsSync(), isFalse);
    });

    test('avatars decode near their display size', () {
      expect(CoachImage.decodeExtent(30, 3), 180);
      expect(CoachImage.decodeExtent(40, 2), 160);
    });
  });

  group('hold to talk', () {
    Future<_FakeSpeech> openVoice(WidgetTester tester, {_FakeSpeech? speech}) async {
      final s = speech ?? _FakeSpeech();
      await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.chat, speech: s);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('voice-mode')));
      await tester.pumpAndSettle();
      return s;
    }

    testWidgets('a release that arrives while recognition is starting stops it right after', (tester) async {
      final speech = await openVoice(tester, speech: _FakeSpeech()..holdStart = true);
      final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('hold-to-talk'))));
      await tester.pump();
      expect(speech.starts, 1);
      expect(find.text('Listening…'), findsOneWidget, reason: 'listening shows before start completes');
      await g.up(); // early release
      await tester.pump();
      expect(speech.stops, 0);
      speech.pendingStart!.complete(SpeechStart.started);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(speech.stops, 1);
      expect(speech.listening, isFalse);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('accessibility: the talk button toggles with a tap', (tester) async {
      final speech = _FakeSpeech();
      await pumpApp(tester, prefs: onboardedPrefs(), tab: AppTab.chat, speech: speech);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('voice-mode')));
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();
      // VoiceOver/TalkBack double-tap = the semantics tap action.
      final talk = find.semantics.byLabel('Hold to talk');
      expect(talk, findsOne);
      tester.semantics.tap(talk);
      await tester.pump();
      expect(speech.starts, 1);
      expect(speech.listening, isTrue);
      tester.semantics.tap(find.semantics.byLabel('Stop and send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(speech.stops, 1);
      handle.dispose();
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('unsupported language on the device: a friendly message', (tester) async {
      final speech = await openVoice(tester, speech: _FakeSpeech()..nextResult = SpeechStart.unsupported);
      final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('hold-to-talk'))));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining("Voice isn't available for this language"), findsOneWidget);
      await g.up();
      await tester.pump();
      expect(speech.stops, 0);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}
