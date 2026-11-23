// QA: data deletion, Coach memory consent, the 18+ gate, and consistency of
// the privacy disclosures (in-app policy, PrivacyInfo.xcprivacy, App Store
// privacy answers) with what the app and the backend actually do.
//
// Defects are listed in docs/qa/SUBSCRIPTION_PRIVACY_REPORT.md; the D5 test
// (memory OFF deletes the note) now runs unskipped.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/content/legal_text.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';

import 'helpers.dart';

/// Records every request the coach backend would receive.
class _RecordingAI implements AIService {
  final payloads = <Map<String, Object>>[];
  final _backend = BackendAIService(endpoint: 'https://example.invalid');
  @override
  String get providerLabel => 'recording';
  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) {
    payloads.add(_backend.buildPayload(history, tier, profile, coach));
    return Stream.fromIterable(['Sure.']);
  }

  String get lastJson => jsonEncode(payloads.last);
}

Future<(AppState, _RecordingAI, StorageService)> _make(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storage = await StorageService.create();
  final ai = _RecordingAI();
  final state = AppState(storage: storage, ai: ai, store: FakeStoreService(entitled: true));
  return (state, ai, storage);
}

class _SpyingSpeech extends NoSpeechService {
  int readyCalls = 0;
  int starts = 0;
  @override
  bool get available => true;
  @override
  Future<bool> ensureReady() async {
    readyCalls++;
    return true;
  }

  @override
  Future<SpeechStart> start({
    required String localeId,
    List<String> fallbackLocales = const [],
    required void Function(String words) onWords,
    void Function()? onUnsupported,
  }) async {
    starts++;
    return SpeechStart.started;
  }
}

const _secret = 'I am 31 and shy, on Hinge';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Delete my data', () {
    test('clears every DateWise key: chats, profile, plan, memory, stats, legacy caches', () async {
      final (state, _, _) = await _make({
        ...onboardedPrefs(),
        'dw_memory_on': true,
        'dw_memory_text': _secret,
        'dw_active_days': ['2026-11-20', '2026-11-21'],
        'dw_tier': 'magnet',
        'dw_intro_seen': true,
        'dw_analysis_cache': '[{"key":"x"}]',
        'dw_batch_cache': '[]',
      });
      await state.sendMessage('my first date is Friday');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await state.togglePlanItem(0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dw_threads'), contains('Friday'));
      expect(prefs.getString('dw_plan'), isNotNull);

      await state.deleteMyData();

      final left = prefs.getKeys().where((k) => k.startsWith('dw_')).toList();
      expect(left, isEmpty, reason: 'left behind: $left');
      expect(state.threads, isEmpty);
      expect(state.memoryText, isEmpty);
      expect(state.memoryEnabled, isFalse);
      expect(state.plan, isNull);
      expect(state.profile, isNull);
      expect(state.daysUsed, 0);
      expect(state.onboarded, isFalse);

      // A fresh launch on the same prefs finds nothing.
      final again = AppState(storage: await StorageService.create(), ai: _RecordingAI());
      expect(again.threads, isEmpty);
      expect(again.memoryText, isEmpty);
      expect(again.onboarded, isFalse);
    });

    test('the app writes no keys outside the dw_ prefix and no files', () {
      // clearAll() removes only dw_ keys, so every key the app writes must use it.
      final src = File('lib/services/storage_service.dart').readAsStringSync();
      final keys = RegExp(r"static const _k\w+ = '([^']+)'").allMatches(src).map((m) => m[1]!).toList();
      expect(keys, isNotEmpty);
      expect(keys.where((k) => !k.startsWith('dw_')), isEmpty);
      final lib = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      expect(lib.contains('SharedPreferences.getInstance'), isTrue);
      expect(RegExp(r"\bFile\(|Directory\(|path_provider|getTemporaryDirectory|sqflite|hive").hasMatch(lib), isFalse,
          reason: 'no cached files exist, so none need deleting');
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('path_provider'), isFalse);
    });

    test('the 18+ block survives Delete my data', () async {
      final (state, _, _) = await _make(onboardedPrefs());
      await state.markUnderage();
      await state.deleteMyData();
      final again = AppState(storage: await StorageService.create(), ai: _RecordingAI());
      expect(again.underageBlocked, isTrue);
      expect(
        await again.completeOnboarding(goals: const [], language: CoachLanguage.en, coachId: 'ava', adultConfirmed: true),
        isFalse,
      );
    });
  });

  group('Coach memory consent', () {
    test('OFF by default: a saved note is never sent', () async {
      final (state, ai, _) = await _make(onboardedPrefs());
      expect(state.memoryEnabled, isFalse);
      await state.saveMemory(_secret);
      await state.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(ai.lastJson.contains('Hinge'), isFalse);
      expect((ai.payloads.last['profile'] as Map).containsKey('memory'), isFalse);
    });

    test('ON: the note goes in the profile and the system prompt', () async {
      final (state, ai, _) = await _make(onboardedPrefs());
      await state.setMemoryEnabled(true);
      await state.saveMemory(_secret);
      await state.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect((ai.payloads.last['profile'] as Map)['memory'], _secret);
      final system = (ai.payloads.last['messages'] as List).first as Map;
      expect(system['content'], contains(_secret));
    });

    test('switched OFF again: the note is no longer sent', () async {
      final (state, ai, _) = await _make({...onboardedPrefs(), 'dw_memory_on': true, 'dw_memory_text': _secret});
      await state.setMemoryEnabled(false);
      await state.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(ai.lastJson.contains('Hinge'), isFalse);
    });

    test('the app never writes to memory by itself (only the user does)', () async {
      final (state, _, _) = await _make({...onboardedPrefs(), 'dw_memory_on': true});
      await state.sendMessage('I live in Austin and I am 34');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(state.memoryText, isEmpty);
      expect((await SharedPreferences.getInstance()).getString('dw_memory_text'), anyOf(isNull, isEmpty));
    });

    test('switching memory OFF deletes the stored note', () async {
      final (state, _, _) = await _make({...onboardedPrefs(), 'dw_memory_on': true, 'dw_memory_text': _secret});
      await state.setMemoryEnabled(false);
      expect(state.memoryText, isEmpty);
      expect((await SharedPreferences.getInstance()).getString('dw_memory_text'), anyOf(isNull, isEmpty));
    });

    test('requests carry no identifiers: only tier, coachId, profile and messages', () async {
      final (state, ai, _) = await _make(onboardedPrefs());
      await state.sendMessage('hi');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(ai.payloads.last.keys.toSet(), {'tier', 'coachId', 'profile', 'messages'});
      expect((ai.payloads.last['profile'] as Map).keys.toSet(), {'goals', 'language'});
    });
  });

  group('privacy disclosures are consistent', () {
    final manifest = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    final metadata = File('docs/appstore/metadata.md').readAsStringSync();
    final body = manifest.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    test('PrivacyInfo.xcprivacy: no tracking, two collected types, UserDefaults CA92.1', () {
      expect(RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>').hasMatch(body), isTrue);
      expect(RegExp(r'<key>NSPrivacyTrackingDomains</key>\s*<array/>').hasMatch(body), isTrue);
      final types = RegExp(r'<string>(NSPrivacyCollectedDataType\w+)</string>')
          .allMatches(body)
          .map((m) => m[1])
          .where((t) => !t!.startsWith('NSPrivacyCollectedDataTypePurpose'))
          .toSet();
      expect(types, {'NSPrivacyCollectedDataTypeOtherUserContent', 'NSPrivacyCollectedDataTypePurchaseHistory'});
      expect(RegExp(r'<key>NSPrivacyCollectedDataTypeLinked</key>\s*<true/>').hasMatch(body), isFalse);
      expect(RegExp(r'<key>NSPrivacyCollectedDataTypeTracking</key>\s*<true/>').hasMatch(body), isFalse);
      final purposes = RegExp(r'<string>(NSPrivacyCollectedDataTypePurpose\w+)</string>').allMatches(body).map((m) => m[1]).toSet();
      expect(purposes, {'NSPrivacyCollectedDataTypePurposeAppFunctionality'});
      expect(RegExp(r'NSPrivacyAccessedAPICategoryUserDefaults</string>\s*<key>NSPrivacyAccessedAPITypeReasons</key>\s*<array>\s*<string>CA92.1</string>')
          .hasMatch(body), isTrue);
      final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(project, contains('PrivacyInfo.xcprivacy in Resources'), reason: 'the manifest ships in the bundle');
    });

    test('App Store privacy answers match the manifest', () {
      expect(metadata, contains('| User Content › Other User Content'));
      expect(metadata, contains('| Purchases › Purchase History | Yes | No | No | App Functionality |'));
      expect(metadata, contains('**Data Not Linked to You**: User Content, Purchases'));
      expect(metadata, contains('Audio Data'), reason: 'audio is explicitly not collected');
    });

    test('the privacy policy says what is sent, and nothing more is sent', () {
      for (final policy in [kPrivacyPolicy]) {
        expect(policy, contains('no advertising, analytics, or tracking'));
        expect(policy, contains('only when Coach memory is on'));
        expect(policy, contains('not stored on our servers'));
        expect(policy, contains('aged 18 and over'));
      }
      expect(kPrivacyPolicyEs, contains('no contiene publicidad, analítica ni rastreo'));
      expect(kTermsOfService, contains('There is no free plan and no free trial.'));
      expect(kTermsOfService, contains('auto-renewable monthly subscription'));
      // Nothing beyond what the policy lists is sent (see the identifiers test).
      final deps = File('pubspec.yaml').readAsStringSync();
      for (final sdk in ['firebase', 'analytics', 'sentry', 'crashlytics', 'amplitude', 'mixpanel', 'adjust', 'appsflyer', 'facebook', 'admob', 'device_info', 'advertising_id']) {
        expect(deps.toLowerCase().contains(sdk), isFalse, reason: sdk);
      }
    });

    test('Info.plist explains microphone and speech use, and declares exempt encryption', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('NSMicrophoneUsageDescription'));
      expect(plist, contains('NSSpeechRecognitionUsageDescription'));
      expect(RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>').hasMatch(plist), isTrue);
    });
  });

  group('backend stores no conversation content', () {
    final worker = File('backend/worker.js').readAsStringSync();
    final wrangler = File('backend/wrangler.toml').readAsStringSync();

    test('no logging, no storage bindings, no third-party calls', () {
      expect(RegExp(r'console\.(log|info|warn|error|debug)').hasMatch(worker), isFalse);
      final bindings = RegExp(r'env\.([A-Z_][A-Z0-9_]*)').allMatches(worker).map((m) => m[1]).toSet();
      expect(bindings, {'AI'}, reason: 'only the Workers AI binding: no KV, D1, R2, Queues or Analytics Engine');
      expect(RegExp(r'\bfetch\(\s*["`h]').hasMatch(worker), isFalse, reason: 'no outbound fetch to another service');
      for (final k in ['kv_namespaces', 'd1_databases', 'r2_buckets', 'queues', 'analytics_engine', 'logpush', 'observability']) {
        expect(wrangler.contains(k), isFalse, reason: k);
      }
    });

    test('the chat path enforces no subscription (current state, for the cost-guard work)', () {
      // handleChat runs before any tier check; tier is client-sent anyway.
      final chat = worker.indexOf('return await handleChat(env, messages)');
      final gate = worker.indexOf("if (tier !== 'magnet')");
      expect(chat, greaterThan(0));
      expect(gate, greaterThan(chat), reason: 'chat returns before the (photo-only) tier gate');
      expect(RegExp(r'jws|signedTransaction|verifyReceipt|appAccountToken', caseSensitive: false).hasMatch(worker), isFalse,
          reason: 'no App Store transaction verification yet');
    });
  });

  testWidgets('non-subscriber: voice from Home opens the paywall, never the microphone', (tester) async {
    final speech = _SpyingSpeech();
    final app = await pumpApp(tester, prefs: onboardedPrefs(), entitled: false, speech: speech);
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paywall-close')));
    await tester.pumpAndSettle();
    expect(app.state.canChat, isFalse);
    await tester.ensureVisible(find.byKey(const ValueKey('home-voice')));
    await tester.tap(find.byKey(const ValueKey('home-voice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
    expect(speech.readyCalls, 0, reason: 'no permission prompt, no listening');
    expect(speech.starts, 0);
  });

  testWidgets('paywall shows the StoreKit-localized price as is (e.g. 9,99 €), never \$9.99', (tester) async {
    await pumpApp(tester, prefs: onboardedPrefs(), store: FakeStoreService(price: '9,99 €'));
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
    final price = tester.widget<Text>(find.byKey(const ValueKey('paywall-price'))).data;
    expect(price, '9,99 €');
    expect(find.text('Subscribe for 9,99 €/month'), findsOneWidget);
    final d = tester.widget<Text>(find.byKey(const ValueKey('paywall-disclosure'))).data!;
    expect(d, contains('auto-renews monthly at 9,99 €'));
    expect(d, isNot(contains(r'$')));
    for (final k in ['paywall-restore', 'paywall-terms', 'paywall-privacy']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
  });
}
