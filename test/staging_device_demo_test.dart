// The iPhone end-to-end demo build (docs/qa/IPHONE_E2E_DEMO.md): a release
// build with COACH_BACKEND_URL set to the staging Worker uses the real
// backend client and the real store, sends the StoreKit entitlement, and only
// that build names its coach host in Settings.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/screens/settings_screen.dart';
import 'package:datewise_ai/services/ai_config.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/coach_usage.dart';

import 'helpers.dart';

const stagingUrl = 'https://datewise-coach-staging.scubamike124.workers.dev';

void main() {
  tearDown(() {
    AIConfig.debugUrlForHostLabel = null;
    EntitlementToken.update(null);
  });

  group('release build pointed at staging', () {
    test('uses the real backend client (no offline coach) at exactly that URL', () {
      final ai = AIServiceFactory.create(url: stagingUrl, release: true);
      expect(ai, isA<BackendAIService>());
      expect((ai as BackendAIService).endpoint, stagingUrl);
    });

    test('a non-HTTPS staging URL is never used: release fails closed', () {
      expect(AIServiceFactory.create(url: 'http://datewise-coach-staging.scubamike124.workers.dev', release: true),
          isA<UnconfiguredAIService>());
      expect(() => BackendAIService(endpoint: 'http://datewise-coach-staging.scubamike124.workers.dev'), throwsArgumentError);
    });

    test('every request carries the StoreKit entitlement JWS to the staging Worker', () async {
      EntitlementToken.update('eyJhbGciOiJFUzI1NiJ9.eyJ4IjoxfQ.c2ln');
      http.BaseRequest? seen;
      final ai = BackendAIService(
        endpoint: stagingUrl,
        clientFactory: () => MockClient.streaming((req, body) async {
          seen = req;
          await body.drain<void>();
          return http.StreamedResponse(Stream.value('data: {"response":"Hi"}\n\ndata: [DONE]\n\n'.codeUnits), 200);
        }),
      );
      final out = await ai
          .streamReply(history: [ChatMessage(id: '1', role: MessageRole.user, text: 'Hi', createdAt: DateTime(2026))], tier: SubscriptionTier.magnet)
          .join();
      expect(out, 'Hi');
      expect(seen!.url.toString(), stagingUrl);
      expect(seen!.headers['X-DateWise-Entitlement'], 'eyJhbGciOiJFUzI1NiJ9.eyJ4IjoxfQ.c2ln');
    });

    test('release iOS builds use the real App Store and never the fake store or mock AI', () {
      final store = File('lib/services/store_service.dart').readAsStringSync();
      expect(store, contains('if (StoreConfig.useFakeStore && (kIsWeb || kDebugMode)) return FakeStoreService();'));
      expect(store, contains('return AppStoreService();'));
      expect(File('lib/main.dart').readAsStringSync(), contains('ReviewMode.mockAI && (kIsWeb || !kReleaseMode)'));
    });

    test('no staging host is compiled into lib/ (production binaries stay clean)', () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        expect(f.readAsStringSync(), isNot(contains('datewise-coach-staging')), reason: f.path);
      }
    });
  });

  group('test-build host label', () {
    test('only a non-production HTTPS backend is named', () {
      expect(AIConfig.testBuildHost(), isNull, reason: 'tests run with the production default');
      expect(AIConfig.testBuildHost(AIConfig.productionUrl), isNull);
      expect(AIConfig.testBuildHost(' ${AIConfig.productionUrl} '), isNull);
      expect(AIConfig.testBuildHost(stagingUrl), 'datewise-coach-staging.scubamike124.workers.dev');
      expect(AIConfig.testBuildHost('http://evil.example'), isNull);
      expect(AIConfig.testBuildHost(''), isNull);
    });

    testWidgets('Settings shows no coach server in a production build', (tester) async {
      await pumpScreen(tester, const Scaffold(body: SettingsScreen()), size: const Size(390, 2600));
      await tester.pumpAndSettle();
      expect(find.textContaining('coach server'), findsNothing);
    });

    testWidgets('Settings names the staging host in a staging build', (tester) async {
      AIConfig.debugUrlForHostLabel = stagingUrl;
      await pumpScreen(tester, const Scaffold(body: SettingsScreen()), size: const Size(390, 2600));
      await tester.pumpAndSettle();
      expect(find.textContaining('Test build · coach server: datewise-coach-staging.scubamike124.workers.dev'), findsOneWidget);
    });
  });
}
