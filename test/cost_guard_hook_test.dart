// The chat-v7 cost-guard hook in the app: the StoreKit 2 JWS goes out as
// X-DateWise-Entitlement, refusal codes reach CoachUnavailableException, and
// the fair-use headers update CoachUsage.

import 'dart:convert';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/l10n/app_localizations.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/coach_limit_messages.dart';
import 'package:datewise_ai/services/coach_usage.dart';

final history = [ChatMessage(id: '1', role: MessageRole.user, text: 'Hi', createdAt: DateTime(2026))];
const jws = 'eyJhbGciOiJFUzI1NiJ9.eyJ0cmFuc2FjdGlvbklkIjoiMSJ9.c2ln';

BackendAIService serviceReturning(int status, String body, Map<String, String> headers, void Function(http.BaseRequest) onRequest) =>
    BackendAIService(
      endpoint: 'https://example.workers.dev',
      clientFactory: () => MockClient.streaming((req, _) async {
        onRequest(req);
        return http.StreamedResponse(Stream.value(utf8.encode(body)), status, headers: headers);
      }),
    );

void main() {
  tearDown(() {
    EntitlementToken.update(null);
    EntitlementToken.refresher = null;
    CoachUsage.state.value = null;
  });

  test('sends the entitlement JWS only when there is one', () async {
    http.BaseRequest? seen;
    final ok = serviceReturning(200, 'data: {"response":"Hi"}\n\ndata: [DONE]\n\n', {}, (r) => seen = r);
    await ok.streamReply(history: history, tier: SubscriptionTier.values.last).toList();
    expect(seen!.headers.containsKey('X-DateWise-Entitlement'), isFalse);

    EntitlementToken.update(jws);
    await ok.streamReply(history: history, tier: SubscriptionTier.values.last).toList();
    expect(seen!.headers['X-DateWise-Entitlement'], jws);
  });

  test('a refusal carries its code and Retry-After', () async {
    final svc = serviceReturning(429, '{"error":"DAILY_LIMIT","code":"DAILY_LIMIT","resetAt":1}', {'retry-after': '3600'}, (_) {});
    await expectLater(
      svc.streamReply(history: history, tier: SubscriptionTier.values.last).toList(),
      throwsA(isA<CoachUnavailableException>()
          .having((e) => e.statusCode, 'statusCode', 429)
          .having((e) => e.code, 'code', CoachLimitCode.dailyLimit)
          .having((e) => e.retryAfter, 'retryAfter', 3600)),
    );
    expect(BackendAIService.errorCodeFrom('<html>502</html>'), isNull);
  });

  test('usage headers update CoachUsage', () async {
    final svc = serviceReturning(200, 'data: {"response":"Hi"}\n\ndata: [DONE]\n\n', {
      'x-datewise-usage-notice': 'approaching_daily_limit',
      'x-datewise-remaining-today': '30',
      'x-datewise-remaining-month': '900',
    }, (_) {});
    await svc.streamReply(history: history, tier: SubscriptionTier.values.last).toList();
    final s = CoachUsage.state.value!;
    expect(s.notice, 'approaching_daily_limit');
    expect(s.remainingToday, 30);
    expect(s.remainingMonth, 900);
  });

  test('only a compact JWS is kept from purchase verification data', () {
    EntitlementToken.updateIfJws('MIIT...base64 StoreKit 1 receipt');
    expect(EntitlementToken.current, isNull);
    EntitlementToken.updateIfJws(jws);
    expect(EntitlementToken.current, jws);
  });

  test('an expired or invalid token: refresh the entitlement once, retry once', () async {
    final seen = <String?>[];
    var refreshes = 0;
    var answers = [403, 200];
    final svc = BackendAIService(
      endpoint: 'https://example.workers.dev',
      clientFactory: () => MockClient.streaming((req, _) async {
        seen.add(req.headers['X-DateWise-Entitlement']);
        final status = answers.removeAt(0);
        final body = status == 200 ? 'data: {"response":"Hi"}\n\ndata: [DONE]\n\n' : '{"code":"SUBSCRIPTION_EXPIRED"}';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
      }),
    );
    EntitlementToken.update('old.jws.token');
    EntitlementToken.refresher = () async {
      refreshes++;
      EntitlementToken.update('new.jws.token');
    };
    expect(await svc.streamReply(history: history, tier: SubscriptionTier.values.last).toList(), ['Hi']);
    expect(refreshes, 1);
    expect(seen, ['old.jws.token', 'new.jws.token']);

    // Still refused after the refresh: the error surfaces, with no second refresh.
    answers = [403, 403];
    seen.clear();
    await expectLater(
      svc.streamReply(history: history, tier: SubscriptionTier.values.last).toList(),
      throwsA(isA<CoachUnavailableException>().having((e) => e.code, 'code', CoachLimitCode.subscriptionExpired)),
    );
    expect(refreshes, 2);
    expect(seen.length, 2);
  });

  test('403 SUBSCRIPTION_REQUIRED (a v2 request without a token): re-read StoreKit once, retry with the token', () async {
    final seen = <String?>[];
    var answers = [403, 200];
    final svc = BackendAIService(
      endpoint: 'https://example.workers.dev',
      clientFactory: () => MockClient.streaming((req, _) async {
        seen.add(req.headers['X-DateWise-Entitlement']);
        final status = answers.removeAt(0);
        final body = status == 200 ? 'data: {"response":"Hi"}\n\ndata: [DONE]\n\n' : '{"error":"SUBSCRIPTION_REQUIRED","code":"SUBSCRIPTION_REQUIRED"}';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
      }),
    );
    EntitlementToken.refresher = () async => EntitlementToken.update('fresh.jws.token');
    expect(await svc.streamReply(history: history, tier: SubscriptionTier.values.last).toList(), ['Hi']);
    expect(seen, [null, 'fresh.jws.token']);

    // Still no subscription after the re-read: the code reaches the chat, which
    // shows the "subscription isn't active" notice.
    answers = [403, 403];
    EntitlementToken.update(null);
    EntitlementToken.refresher = () async {};
    await expectLater(
      svc.streamReply(history: history, tier: SubscriptionTier.values.last).toList(),
      throwsA(isA<CoachUnavailableException>().having((e) => e.code, 'code', CoachLimitCode.subscriptionRequired)),
    );
    final en = lookupAppLocalizations(const Locale('en'));
    expect(coachLimitMessage(en, CoachLimitCode.subscriptionRequired), en.coachLimitSubscriptionInactive);
  });

  test('limit codes do not trigger a refresh', () async {
    var refreshes = 0;
    EntitlementToken.refresher = () async => refreshes++;
    final svc = serviceReturning(429, '{"code":"DAILY_LIMIT"}', {}, (_) {});
    await expectLater(svc.streamReply(history: history, tier: SubscriptionTier.values.last).toList(),
        throwsA(isA<CoachUnavailableException>()));
    expect(refreshes, 0);
  });

  group('the transient retry and the refresh retry share one budget of 2 requests', () {
    late List<(int, String)> answers;
    late int requests;
    late int refreshes;
    late BackendAIService svc;
    setUp(() {
      requests = 0;
      refreshes = 0;
      EntitlementToken.update('old.jws.token');
      EntitlementToken.refresher = () async => refreshes++;
      svc = BackendAIService(
        endpoint: 'https://example.workers.dev',
        retryDelay: Duration.zero,
        clientFactory: () => MockClient.streaming((req, _) async {
          requests++;
          final (status, body) = answers.isEmpty ? (200, 'data: {"response":"Hi"}\n\ndata: [DONE]\n\n') : answers.removeAt(0);
          return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
        }),
      );
    });
    Future<List<String>> reply() => svc.streamReply(history: history, tier: SubscriptionTier.values.last).toList();
    final expired = (403, '{"code":"SUBSCRIPTION_EXPIRED"}');

    test('503, then SUBSCRIPTION_EXPIRED: no refresh, no third request', () async {
      answers = [(503, ''), expired];
      await expectLater(reply(), throwsA(isA<CoachUnavailableException>().having((e) => e.code, 'code', CoachLimitCode.subscriptionExpired)));
      expect(requests, 2);
      expect(refreshes, 0);
    });

    test('SUBSCRIPTION_EXPIRED, refresh, then 503: no transient retry on top', () async {
      answers = [expired, (503, '')];
      await expectLater(reply(), throwsA(isA<CoachUnavailableException>().having((e) => e.statusCode, 'statusCode', 503)));
      expect(requests, 2);
      expect(refreshes, 1);
    });

    test('SUBSCRIPTION_EXPIRED, refresh, then a network error: no third request', () async {
      var n = 0;
      svc = BackendAIService(
        endpoint: 'https://example.workers.dev',
        retryDelay: Duration.zero,
        clientFactory: () => MockClient.streaming((req, _) async {
          requests++;
          if (n++ == 0) return http.StreamedResponse(Stream.value(utf8.encode(expired.$2)), 403);
          throw http.ClientException('offline');
        }),
      );
      await expectLater(reply(), throwsA(isA<CoachUnavailableException>()));
      expect(requests, 2);
      expect(refreshes, 1);
    });

    test('a bare 503 is retried once and can succeed', () async {
      answers = [(503, '')];
      expect(await reply(), ['Hi']);
      expect(requests, 2);
    });

    test('a coded 503 (SERVICE_BUDGET_EXHAUSTED) is not retried', () async {
      answers = [(503, '{"code":"SERVICE_BUDGET_EXHAUSTED"}')];
      await expectLater(reply(), throwsA(isA<CoachUnavailableException>().having((e) => e.code, 'code', CoachLimitCode.serviceBudgetExhausted)));
      expect(requests, 1);
    });
  });

  test('every refusal code has an English and a Spanish message', () {
    const codes = [
      CoachLimitCode.dailyLimit,
      CoachLimitCode.monthlyLimit,
      CoachLimitCode.rateLimited,
      CoachLimitCode.concurrencyLimit,
      CoachLimitCode.serviceBudgetExhausted,
      CoachLimitCode.guardUnavailable,
      CoachLimitCode.subscriptionRequired,
      CoachLimitCode.subscriptionInvalid,
      CoachLimitCode.subscriptionExpired,
      CoachLimitCode.subscriptionRevoked,
      CoachLimitCode.appUpdateRequired,
    ];
    final en = lookupAppLocalizations(const Locale('en'));
    final es = lookupAppLocalizations(const Locale('es'));
    for (final code in codes) {
      final a = coachLimitMessage(en, code);
      final b = coachLimitMessage(es, code);
      expect(a, isNotNull, reason: code);
      expect(b, isNotNull, reason: code);
      expect(a, isNot(b), reason: code);
      expect('$a $b'.toLowerCase(), isNot(contains('unlimited')));
      expect('$a $b'.toLowerCase(), isNot(contains('ilimitad')));
    }
    expect(coachLimitMessage(en, 'SOMETHING_NEW'), isNull);
    expect(coachLimitMessage(en, null), isNull);
    expect(coachUsageNotice(es, 'approaching_daily_limit'), es.coachUsageNoticeDaily);
    expect(coachUsageNotice(en, 'approaching_monthly_limit'), en.coachUsageNoticeMonthly);
  });
}
