// The coach backend client against recorded/format-exact fixtures:
// endpoint and request shape (backend/worker.js chat-v6), the SSE parser
// (CRLF, split chunks, split UTF-8, keep-alives, [DONE]), non-200 errors,
// timeouts and cancellation.
//
// Fixtures (test/fixtures):
// - worker_502_deprecated_model.json: recorded from the production Worker
//   (still chat-v5) on 2026-11-22: POST {messages:[...]} → HTTP 502, this body.
// - workers_ai_chat.sse / workers_ai_chat_crlf.sse: the Workers AI streaming
//   format chat-v6 forwards verbatim (data: {"response":"…"} events, a usage
//   event, data: [DONE]), LF and CRLF. Built to the documented format: the
//   live Worker could not stream when they were written (HTTP 502 above).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/services/ai_config.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';

List<int> fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

final history = [ChatMessage(id: '1', role: MessageRole.user, text: 'Hi', createdAt: DateTime(2026))];

/// A client that answers with [status] and streams [chunks] (with an
/// optional pause between them), recording the request.
class FakeBackend {
  FakeBackend({this.status = 200, required this.chunks, this.gap = Duration.zero, this.headerDelay = Duration.zero});
  final int status;
  final List<List<int>> chunks;
  final Duration gap;
  final Duration headerDelay;
  http.BaseRequest? request;
  String? body;
  bool closed = false;
  bool streamCanceled = false;

  http.Client client() => _Tracked(this, MockClient.streaming((req, bodyStream) async {
        request = req;
        body = await bodyStream.bytesToString();
        await Future<void>.delayed(headerDelay);
        final controller = StreamController<List<int>>(onCancel: () => streamCanceled = true);
        () async {
          for (final c in chunks) {
            if (controller.isClosed) return;
            if (gap > Duration.zero) await Future<void>.delayed(gap);
            if (streamCanceled) return;
            controller.add(c);
          }
          await controller.close();
        }();
        return http.StreamedResponse(controller.stream, status);
      }));
}

class _Tracked extends http.BaseClient {
  _Tracked(this.owner, this.inner);
  final FakeBackend owner;
  final http.Client inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => inner.send(request);
  @override
  void close() {
    owner.closed = true;
    inner.close();
  }
}

BackendAIService service(FakeBackend b, {Duration? connect, Duration? idle}) => BackendAIService(
      endpoint: AIConfig.productionUrl,
      clientFactory: b.client,
      connectTimeout: connect ?? const Duration(seconds: 30),
      idleTimeout: idle ?? const Duration(seconds: 30),
    );

Stream<String> reply(BackendAIService s, {UserProfile? profile, Coach coach = Coaches.ava}) =>
    s.streamReply(history: history, tier: SubscriptionTier.magnet, profile: profile, coach: coach);

/// Splits [bytes] into chunks of [size] bytes (cutting through lines and
/// multi-byte UTF-8 characters).
List<List<int>> split(List<int> bytes, int size) => [
      for (var i = 0; i < bytes.length; i += size) bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size),
    ];

void main() {
  group('endpoint', () {
    test('production is the HTTPS Worker; no API keys or secrets in the app', () {
      expect(AIConfig.productionUrl, 'https://datewise-photo-coach.scubamike124.workers.dev');
      expect(AIConfig.coachBackendUrl, AIConfig.productionUrl);
      expect(Uri.parse(AIConfig.coachBackendUrl).scheme, 'https');
      expect(AIConfig.hasCoachBackend, isTrue);
      expect(AIServiceFactory.create(), isA<BackendAIService>());
      final lib = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      for (final secret in [RegExp(r'AIza[0-9A-Za-z_\-]{20,}'), RegExp(r'sk-[A-Za-z0-9]{20,}'), RegExp(r'api[_-]?key\s*[:=]\s*.[A-Za-z0-9]{12,}', caseSensitive: false)]) {
        expect(secret.hasMatch(lib), isFalse, reason: 'secret-looking value in lib/: $secret');
      }
    });

    test('a non-HTTPS endpoint is refused', () {
      expect(() => BackendAIService(endpoint: 'http://datewise-photo-coach.scubamike124.workers.dev'), throwsArgumentError);
    });
  });

  group('request', () {
    test('POST {messages:[system, …history]} plus coachId/profile/tier, as worker.js expects', () async {
      final b = FakeBackend(chunks: [fixture('workers_ai_chat.sse')]);
      await reply(service(b), profile: const UserProfile(goals: [CoachingGoal.dates], language: CoachLanguage.es), coach: Coaches.diego).toList();
      expect(b.request!.method, 'POST');
      expect(b.request!.url.toString(), AIConfig.productionUrl);
      expect(b.request!.headers['Content-Type'], startsWith('application/json'));
      expect(b.request!.headers['Accept'], 'text/event-stream');
      final json = jsonDecode(b.body!) as Map<String, dynamic>;
      expect(json.keys.toSet(), {'messages', 'coachId', 'profile', 'tier'});
      final msgs = (json['messages'] as List).cast<Map<String, dynamic>>();
      expect(msgs.first['role'], 'system');
      expect(msgs.first['content'], startsWith('You are Diego'));
      expect(msgs.last, {'role': 'user', 'content': 'Hi'});
      expect(msgs.every((m) => m['content'] is String && {'system', 'user', 'assistant'}.contains(m['role'])), isTrue,
          reason: 'sanitizeMessages() keeps only these');
      expect(json['coachId'], 'diego');
      expect(json['profile'], {'goals': ['dates'], 'language': 'es'});
      expect(b.closed, isTrue, reason: 'the connection is closed when the reply ends');
    });
  });

  group('SSE parser', () {
    test('Workers AI stream (LF) → tokens, stops at [DONE], ignores the usage event', () async {
      final b = FakeBackend(chunks: [fixture('workers_ai_chat.sse')]);
      expect(await reply(service(b)).toList(), ['Hi', ' there', '! Ready?']);
    });

    test('CRLF line endings and keep-alive comments', () async {
      final b = FakeBackend(chunks: [fixture('workers_ai_chat_crlf.sse')]);
      expect((await reply(service(b)).toList()).join(), '¡Hola, soy Sofía.');
    });

    test('events and UTF-8 characters split across network chunks', () async {
      for (final size in [1, 2, 3, 7, 16]) {
        final b = FakeBackend(chunks: split(fixture('workers_ai_chat_crlf.sse'), size));
        expect((await reply(service(b)).toList()).join(), '¡Hola, soy Sofía.', reason: 'chunk size $size');
      }
    });

    test('nothing after [DONE] is read', () async {
      final b = FakeBackend(chunks: [utf8.encode('data: {"response":"a"}\n\ndata: [DONE]\n\ndata: {"response":"zzz"}\n\n')]);
      expect(await reply(service(b)).toList(), ['a']);
    });

    test('"data:" without a space, a last line without a newline, OpenAI-style deltas', () async {
      final b = FakeBackend(chunks: [
        utf8.encode('data:{"response":"one"}\n'),
        utf8.encode('event: message\nid: 7\ndata: {"choices":[{"delta":{"content":" two"}}]}\n'),
        utf8.encode('data: {"response":" three"}'),
      ]);
      expect((await reply(service(b)).toList()).join(), 'one two three');
    });

    test('an in-stream error event fails the reply', () async {
      final b = FakeBackend(chunks: [utf8.encode('data: {"response":"Hi"}\n\ndata: {"error":"model overloaded"}\n\n')]);
      final tokens = <String>[];
      await expectLater(reply(service(b)).forEach(tokens.add), throwsA(isA<CoachUnavailableException>()));
      expect(tokens, ['Hi']);
    });
  });

  group('errors', () {
    test('HTTP 502 (recorded) → CoachUnavailableException, no fake coaching text', () async {
      final b = FakeBackend(status: 502, chunks: [fixture('worker_502_deprecated_model.json')]);
      final tokens = <String>[];
      await expectLater(
        reply(service(b)).forEach(tokens.add),
        throwsA(isA<CoachUnavailableException>().having((e) => e.statusCode, 'statusCode', 502)),
      );
      expect(tokens, isEmpty);
      expect(b.closed, isTrue);
    });

    test('other non-200 statuses fail the same way', () async {
      for (final status in [400, 404, 429, 500, 503]) {
        final b = FakeBackend(status: status, chunks: [utf8.encode('{"error":"x"}')]);
        await expectLater(reply(service(b)).toList(), throwsA(isA<CoachUnavailableException>()), reason: '$status');
      }
    });

    test('an empty 200 stream is a failure, not a blank reply', () async {
      final b = FakeBackend(chunks: [utf8.encode('data: [DONE]\n\n')]);
      await expectLater(reply(service(b)).toList(), throwsA(isA<CoachUnavailableException>()));
    });

    test('request timeout (no response headers)', () async {
      final b = FakeBackend(chunks: [fixture('workers_ai_chat.sse')], headerDelay: const Duration(milliseconds: 300));
      await expectLater(
        reply(service(b, connect: const Duration(milliseconds: 50))).toList(),
        throwsA(isA<CoachUnavailableException>().having((e) => e.reason, 'reason', 'timeout')),
      );
    });

    test('stream stalls mid-reply → timeout', () async {
      final b = FakeBackend(
        chunks: [utf8.encode('data: {"response":"Hi"}\n\n'), utf8.encode('data: [DONE]\n\n')],
        gap: const Duration(milliseconds: 300),
      );
      await expectLater(
        reply(service(b, idle: const Duration(milliseconds: 100))).toList(),
        throwsA(isA<CoachUnavailableException>()),
      );
    });

    test('a network failure → CoachUnavailableException', () async {
      final s = BackendAIService(
        endpoint: AIConfig.productionUrl,
        clientFactory: () => MockClient((_) async => throw const SocketException('offline')),
      );
      await expectLater(reply(s).toList(), throwsA(isA<CoachUnavailableException>()));
    });
  });

  test('canceling the subscription stops reading and closes the connection', () async {
    final b = FakeBackend(
      chunks: [for (var i = 0; i < 50; i++) utf8.encode('data: {"response":"$i "}\n\n')],
      gap: const Duration(milliseconds: 20),
    );
    final got = <String>[];
    final sub = reply(service(b)).listen(got.add);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await sub.cancel();
    final count = got.length;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(got.length, count, reason: 'no tokens after cancel');
    expect(count, lessThan(50));
    expect(b.closed, isTrue);
    expect(b.streamCanceled, isTrue);
  });
}
