// The chat-v7 cost-guard hook in the app: the StoreKit 2 JWS goes out as
// X-DateWise-Entitlement, refusal codes reach CoachUnavailableException, and
// the fair-use headers update CoachUsage.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
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
}
