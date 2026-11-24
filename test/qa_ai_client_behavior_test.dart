// QA (independent review of PR #27): client behavior tests (no live AI).
//
// Nothing in this file talks to the production coach backend or to any AI
// model. Every reply below is canned SSE text written by a LOCAL fake server
// (dart:io HttpServer / ServerSocket on 127.0.0.1). These tests prove how the
// app's HTTP/SSE client and chat state behave on the wire (chunking, retries,
// timeouts, disconnects, error statuses, history and memory). They say
// nothing about the quality, persona or language of real coach replies: that
// needs the live chat-v6 Worker and is BLOCKED (see docs/qa/AI_VOICE_REPORT.md).
//
// Unlike test/backend_chat_test.dart (package:http MockClient), the requests
// here go through the real IOClient and a real TCP socket. The app refuses
// non-HTTPS endpoints, so the client factory rewrites the production URL to
// the local plain-HTTP server; everything else is the shipping code path.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/services/ai_config.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/state/app_state.dart';

/// Sends every request to [target] (the local fake server) instead of the
/// production HTTPS URL, through a real IOClient.
class _LocalClient extends http.BaseClient {
  _LocalClient(this.target);
  final Uri target;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final r = request as http.Request;
    final local = http.Request(r.method, target)
      ..headers.addAll(r.headers)
      ..bodyBytes = r.bodyBytes;
    return _inner.send(local);
  }

  @override
  void close() => _inner.close();
}

typedef Handler = Future<void> Function(HttpRequest req, String body, int n);

/// A local fake coach backend. [handler] decides each response; every request
/// body is recorded in [bodies].
class FakeServer {
  FakeServer._(this._server, this.handler);
  final HttpServer _server;
  Handler handler;
  final bodies = <Map<String, dynamic>>[];

  static Future<FakeServer> start(Handler handler) async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeServer._(s, handler);
    s.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      fake.bodies.add(jsonDecode(body) as Map<String, dynamic>);
      try {
        await fake.handler(req, body, fake.bodies.length);
      } catch (_) {
        // The client may abort mid-response; that is part of some tests.
      }
    });
    return fake;
  }

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/');
  int get requests => bodies.length;
  Future<void> close() => _server.close(force: true);
}

String sse(String token) => 'data: ${jsonEncode({'response': token})}\n\n';

/// Streams [tokens] as Workers AI SSE events, one flush per event, ending
/// with `data: [DONE]` unless [done] is false.
Handler streamTokens(List<String> tokens, {Duration gap = Duration.zero, bool done = true}) =>
    (req, _, __) async {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8')
        ..bufferOutput = false;
      for (final t in tokens) {
        req.response.add(utf8.encode(sse(t)));
        await req.response.flush();
        if (gap > Duration.zero) await Future<void>.delayed(gap);
      }
      if (done) req.response.add(utf8.encode('data: [DONE]\n\n'));
      await req.response.close();
    };

Handler status(int code, {Map<String, String> headers = const {}, String body = '{"error":"x"}'}) =>
    (req, _, __) async {
      req.response.statusCode = code;
      headers.forEach(req.response.headers.set);
      req.response.write(body);
      await req.response.close();
    };

BackendAIService client(Uri target, {Duration? connect, Duration? idle}) => BackendAIService(
      endpoint: AIConfig.productionUrl,
      clientFactory: () => _LocalClient(target),
      connectTimeout: connect ?? const Duration(seconds: 5),
      idleTimeout: idle ?? const Duration(seconds: 5),
      retryDelay: const Duration(milliseconds: 20),
    );

final _hi = [ChatMessage(id: '1', role: MessageRole.user, text: 'Hi', createdAt: DateTime(2026))];

Stream<String> ask(BackendAIService s, {Coach coach = Coaches.ava}) =>
    s.streamReply(history: _hi, tier: SubscriptionTier.magnet, coach: coach);

Future<AppState> appState(BackendAIService ai, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({
    'dw_onboarded': true,
    'dw_ai_consent': true,
    'dw_coach': 'ava',
    'dw_profile': '{"goals":["conversations"],"language":"en"}',
    ...prefs,
  });
  final storage = await StorageService.create();
  return AppState(storage: storage, ai: ai);
}

Matcher unavailable(String reason, {int? code}) => isA<CoachUnavailableException>()
    .having((e) => e.reason, 'reason', startsWith(reason))
    .having((e) => e.statusCode, 'statusCode', code);

/// Collects tokens and the first error (the stream closes after it).
Future<(List<String>, Object?)> collect(Stream<String> s) async {
  final got = <String>[];
  try {
    await for (final t in s) {
      got.add(t);
    }
  } catch (e) {
    return (got, e);
  }
  return (got, null);
}

void main() {
  group('client behavior tests (no live AI): streaming chunk assembly', () {
    test('tokens flushed one by one over a real socket are assembled in order', () async {
      final tokens = ['Hi, ', "I'm ", '**Ava**', '. ', 'Your ', 'next ', 'step: ', 'send it today.'];
      final server = await FakeServer.start(streamTokens(tokens, gap: const Duration(milliseconds: 5)));
      addTearDown(server.close);
      final got = await ask(client(server.uri)).toList();
      expect(got, tokens, reason: 'one token per SSE event, nothing merged or lost');
      expect(got.join(), "Hi, I'm **Ava**. Your next step: send it today.");
    });

    test('Spanish text with events and UTF-8 bytes split across TCP writes (CRLF)', () async {
      const reply = ['¡Hola! ', 'Soy **Sofía**. ', '¿Qué ', 'te ', 'preocupa? ', 'Ánimo 💪'];
      final events = [for (final t in reply) 'data: ${jsonEncode({'response': t})}\r\n\r\n'].join();
      final bytes = utf8.encode('$events: keep-alive\r\n\r\ndata: [DONE]\r\n\r\n');
      final server = await FakeServer.start((req, _, __) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType('text', 'event-stream')
          ..bufferOutput = false;
        // 3-byte writes cut through lines and multi-byte characters.
        for (var i = 0; i < bytes.length; i += 3) {
          req.response.add(bytes.sublist(i, i + 3 > bytes.length ? bytes.length : i + 3));
          await req.response.flush();
        }
        await req.response.close();
      });
      addTearDown(server.close);
      final got = await ask(client(server.uri), coach: Coaches.sofia).toList();
      expect(got.join(), reply.join());
    });

    test('AppState shows the reply growing chunk by chunk and saves it complete', () async {
      final server = await FakeServer.start(streamTokens(['One ', 'two ', 'three.'], gap: const Duration(milliseconds: 20)));
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      final seen = <String>[];
      state.addListener(() {
        final last = state.activeThread?.messages.lastOrNull;
        if (last != null && !last.isUser && last.isStreaming) seen.add(last.text);
      });
      expect(await state.sendMessage('Count to three'), isTrue);
      final reply = state.activeThread!.messages.last;
      expect(reply.text, 'One two three.');
      expect(reply.status, MessageStatus.ok);
      expect(reply.isStreaming, isFalse);
      expect(seen, containsAllInOrder(['One ', 'One two ', 'One two three.']));
    });
  });

  group('client behavior tests (no live AI): retries', () {
    test('one automatic retry: a 503 twice is two requests, then a failed reply the user can retry', () async {
      final server = await FakeServer.start(status(503));
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      await state.sendMessage('Help me with my bio');
      expect(server.requests, 2, reason: 'one automatic retry for 502/503/504 (D4)');
      final thread = state.activeThread!;
      expect(thread.messages.last.status, MessageStatus.failed);
      expect(thread.messages.last.failure, ReplyFailure.server);
      expect(thread.messages.last.failedStatus, 503);
      expect(thread.messages.where((m) => m.isUser).single.text, 'Help me with my bio', reason: 'user message kept');
      expect(state.canRetry, isTrue);
      expect(state.isResponding, isFalse);

      // The backend recovers; "Try again" sends the same conversation again.
      server.handler = streamTokens(['Here is a better bio.']);
      expect(await state.retryLastReply(), isTrue);
      expect(server.requests, 3);
      expect(thread.messages.last.text, 'Here is a better bio.');
      expect(thread.messages.last.status, MessageStatus.ok);
      expect(thread.messages.where((m) => m.status == MessageStatus.failed), isEmpty, reason: 'failed reply replaced');
      final retried = (server.bodies.last['messages'] as List).cast<Map>();
      expect(retried.where((m) => m['role'] == 'user').map((m) => m['content']), ['Help me with my bio'],
          reason: 'the user message is sent once, the failed reply not at all');
      expect(state.canRetry, isFalse);
    });

    test('a transient 502 before the first token is retried once and the reply arrives', () async {
      final server = await FakeServer.start((req, _, n) async {
        if (n == 1) return status(502)(req, '', n);
        await streamTokens(['Recovered.'])(req, '', n);
      });
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      await state.sendMessage('Hi');
      expect(server.requests, 2);
      expect(state.activeThread!.messages.last.text, 'Recovered.');
      expect(state.activeThread!.messages.last.status, MessageStatus.ok);
    });

    test('no retry for other statuses (e.g. 429, 500) or after the first token', () async {
      for (final code in [400, 429, 500]) {
        final server = await FakeServer.start(status(code));
        final (_, error) = await collect(ask(client(server.uri)));
        expect(error, unavailable('http', code: code));
        expect(server.requests, 1, reason: 'HTTP $code is not retried');
        await server.close();
      }
      // Tokens then an error: never retried (the reply would be sent twice).
      final server = await FakeServer.start((req, _, __) async {
        req.response
          ..statusCode = 200
          ..bufferOutput = false;
        req.response.add(utf8.encode('${sse('Some ')}data: {"error":"overloaded"}\n\n'));
        await req.response.close();
      });
      addTearDown(server.close);
      final (got, error) = await collect(ask(client(server.uri)));
      expect(got, ['Some ']);
      expect(error, isA<CoachUnavailableException>());
      expect(server.requests, 1);
    });

    test('connection refused (backend unreachable) → retried once, then a "network" failure (offline notice)', () async {
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();
      final s = client(Uri.parse('http://127.0.0.1:$port/'));
      final (_, error) = await collect(ask(s));
      expect(error, unavailable('network'));
      expect(AppState.replyFailureFor(error!), ReplyFailure.offline);
    });
  });

  group('client behavior tests (no live AI): timeouts', () {
    test('no response headers within connectTimeout → "timeout"', () async {
      final server = await FakeServer.start((req, _, __) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        await streamTokens(['late'])(req, '', 0);
      });
      addTearDown(server.close);
      final sw = Stopwatch()..start();
      await expectLater(ask(client(server.uri, connect: const Duration(milliseconds: 300))).toList(),
          throwsA(unavailable('timeout')));
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('stream goes silent longer than idleTimeout → tokens so far, then "timeout"', () async {
      final server = await FakeServer.start((req, _, __) async {
        req.response
          ..statusCode = 200
          ..bufferOutput = false;
        req.response.add(utf8.encode(sse('Partial ')));
        await req.response.flush();
        await Future<void>.delayed(const Duration(seconds: 2));
        await req.response.close();
      });
      addTearDown(server.close);
      final (got, error) = await collect(ask(client(server.uri, idle: const Duration(milliseconds: 300))));
      expect(got, ['Partial ']);
      expect(error, unavailable('timeout'));
    });

    test('AppState: a timed-out reply is failed (partial text kept on screen, never sent as history)', () async {
      final server = await FakeServer.start((req, _, n) async {
        if (n == 1) {
          req.response
            ..statusCode = 200
            ..bufferOutput = false;
          req.response.add(utf8.encode(sse('Half a rep')));
          await req.response.flush();
          await Future<void>.delayed(const Duration(seconds: 2));
          await req.response.close();
        } else {
          await streamTokens(['Full reply.'])(req, '', n);
        }
      });
      addTearDown(server.close);
      final state = await appState(client(server.uri, idle: const Duration(milliseconds: 300)));
      await state.sendMessage('Hi');
      final failed = state.activeThread!.messages.last;
      expect(failed.status, MessageStatus.failed);
      expect(failed.text, 'Half a rep');
      expect(state.canRetry, isTrue);
      await state.retryLastReply();
      final sent = (server.bodies.last['messages'] as List).cast<Map>();
      expect(sent.any((m) => (m['content'] as String).contains('Half a rep')), isFalse);
      expect(state.activeThread!.messages.last.text, 'Full reply.');
    });
  });

  group('client behavior tests (no live AI): mid-stream disconnect', () {
    test('TCP connection dropped mid-reply → "stream" failure, not a silently short reply', () async {
      final ss = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(ss.close);
      ss.listen((sock) {
        var seen = '';
        late StreamSubscription<List<int>> sub;
        sub = sock.listen((data) async {
          seen += latin1.decode(data);
          if (!seen.contains('\r\n\r\n')) return;
          await sub.cancel();
          final chunk = sse('Start of the reply ');
          sock.write('HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n'
              '${utf8.encode(chunk).length.toRadixString(16)}\r\n$chunk\r\n');
          await sock.flush();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          sock.destroy(); // no terminating 0-length chunk, no [DONE]
        });
      });
      final (got, error) = await collect(ask(client(Uri.parse('http://127.0.0.1:${ss.port}/'))));
      expect(got, ['Start of the reply ']);
      expect(error, unavailable('stream'));
    });

    test('a cleanly closed stream without [DONE] is a cut-off reply: failed, retryable (D2 fixed)', () async {
      // The server (or a proxy) ends the HTTP response properly but the
      // model stream never sent [DONE]. The text is kept on screen but the
      // reply is failed, so it never goes into the next request's history.
      final server = await FakeServer.start(streamTokens(['The first half of'], done: false));
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      await state.sendMessage('Hi');
      final reply = state.activeThread!.messages.last;
      expect(reply.text, 'The first half of');
      expect(reply.status, MessageStatus.failed);
      expect(state.canRetry, isTrue);
    });
  });

  group('client behavior tests (no live AI): HTTP error mapping and recovery', () {
    for (final code in [400, 401, 403, 404, 413, 429, 500, 502, 503, 504]) {
      test('HTTP $code → CoachUnavailableException(http, $code); no coaching text', () async {
        final server = await FakeServer.start(status(code));
        addTearDown(server.close);
        final (got, error) = await collect(ask(client(server.uri)));
        expect(got, isEmpty);
        expect(error, unavailable('http', code: code));
      });
    }

    test('429: the status is kept on the failed reply (busy notice), persisted, and recoverable (D3 fixed)', () async {
      final server = await FakeServer.start(status(429, headers: {'Retry-After': '30'}));
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      await state.sendMessage('Hi');
      final last = state.activeThread!.messages.last;
      expect(last.status, MessageStatus.failed);
      expect(last.failedStatus, 429);
      expect(last.failure, ReplyFailure.busy);
      final restored = ChatMessage.fromJson(last.toJson());
      expect(restored.failedStatus, 429);
      expect(restored.failure, ReplyFailure.busy);
      expect(state.canRetry, isTrue);
      server.handler = streamTokens(['OK now.']);
      await state.retryLastReply();
      expect(state.activeThread!.messages.last.text, 'OK now.');
    });

    test('in-stream {"error": …} event after some tokens → failure, recoverable', () async {
      final server = await FakeServer.start((req, _, n) async {
        req.response
          ..statusCode = 200
          ..bufferOutput = false;
        req.response.add(utf8.encode('${sse('Some ')}data: {"error":"AiError: 3040: Capacity temporarily exceeded"}\n\n'));
        await req.response.close();
      });
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      await state.sendMessage('Hi');
      expect(state.activeThread!.messages.last.status, MessageStatus.failed);
      expect(state.canRetry, isTrue);
    });

    test('the recorded production chat-v5 body (HTTP 502, deprecated model) → failed reply', () async {
      final server = await FakeServer.start(status(502,
          body: '{"error":"Workers AI error","detail":"AiError: 5028: @cf/meta/llama-3.1-8b-instruct-fp8 was deprecated on 2026-11-20."}'));
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      await state.sendMessage('Hi');
      final last = state.activeThread!.messages.last;
      expect(last.status, MessageStatus.failed);
      expect(last.text, isEmpty, reason: 'no invented coaching text');
    });
  });

  group('client behavior tests (no live AI): conversation memory and history', () {
    test('history: system prompt first, then every complete turn; failed/stopped turns excluded', () async {
      var n = 0;
      final server = await FakeServer.start((req, _, __) async {
        n++;
        if (n == 2) return status(500)(req, '', n);
        return streamTokens(['Reply $n.'])(req, '', n);
      });
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      await state.sendMessage('First');
      await state.sendMessage('Second'); // fails (500)
      await state.retryLastReply(); // ok
      await state.sendMessage('Third');
      final msgs = (server.bodies.last['messages'] as List).cast<Map<String, dynamic>>();
      expect(msgs.first['role'], 'system');
      expect(msgs.skip(1).map((m) => '${m['role']}:${m['content']}').toList(), [
        "assistant:${Coaches.ava.greeting}",
        'user:First',
        'assistant:Reply 1.',
        'user:Second',
        'assistant:Reply 3.',
        'user:Third',
      ]);
      expect(server.bodies.last['coachId'], 'ava');
    });

    test('client-side cap: a 40-turn thread sends the system prompt + the newest 24 turns (D5 fixed)', () async {
      final server = await FakeServer.start(streamTokens(['ok']));
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      for (var i = 0; i < 40; i++) {
        await state.sendMessage('Message $i');
      }
      final msgs = server.bodies.last['messages'] as List;
      // The thread holds system + greeting + 40 user + 39 replies; the client
      // now sends what worker.js sanitizeMessages would keep anyway.
      expect(msgs.length, 1 + BackendAIService.maxHistoryTurns);
      expect((msgs.first as Map)['role'], 'system');
      expect((msgs.last as Map)['content'], 'Message 39', reason: 'the newest turns are kept');
    });

    test('Coach memory OFF by default: no memory in the profile or the system prompt', () async {
      final server = await FakeServer.start(streamTokens(['ok']));
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      await state.saveMemory('I am shy and I like hiking.'); // saved but memory is OFF
      expect(state.memoryEnabled, isFalse);
      await state.sendMessage('Hi');
      final body = server.bodies.last;
      expect((body['profile'] as Map).containsKey('memory'), isFalse);
      expect(jsonEncode(body), isNot(contains('hiking')));
    });

    test('Coach memory ON: sent in profile.memory and the system prompt; OFF again: gone', () async {
      final server = await FakeServer.start(streamTokens(['ok']));
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      await state.saveMemory('I am shy and I like hiking.');
      await state.setMemoryEnabled(true);
      await state.sendMessage('Hi');
      var body = server.bodies.last;
      expect((body['profile'] as Map)['memory'], 'I am shy and I like hiking.');
      expect((body['messages'] as List).first['content'], contains('remember this about them'));
      expect((body['messages'] as List).first['content'], contains('hiking'));

      await state.setMemoryEnabled(false);
      await state.sendMessage('Again');
      body = server.bodies.last;
      expect(jsonEncode(body), isNot(contains('hiking')), reason: 'consent withdrawn → nothing sent');

      await state.setMemoryEnabled(true);
      await state.clearMemory();
      await state.sendMessage('Cleared');
      expect(jsonEncode(server.bodies.last), isNot(contains('hiking')));
    });

    test('memory note is capped at ${AppState.memoryMaxLength} characters before it is sent', () async {
      final server = await FakeServer.start(streamTokens(['ok']));
      addTearDown(server.close);
      final state = await appState(client(server.uri));
      await state.setMemoryEnabled(true);
      await state.saveMemory('x' * 900);
      await state.sendMessage('Hi');
      expect(((server.bodies.last['profile'] as Map)['memory'] as String).length, AppState.memoryMaxLength);
    });

    test('no v1 profile fields (age, gender, city, interestedIn, goal, app) are sent, even if stored', () async {
      final server = await FakeServer.start(streamTokens(['ok']));
      addTearDown(server.close);
      final state = await appState(client(server.uri), prefs: {
        'dw_profile': '{"goals":["dates"],"language":"en","age":"29","gender":"man","city":"Austin",'
            '"interestedIn":"women","goal":"relationship","app":"Hinge"}',
      });
      await state.sendMessage('Hi');
      final body = server.bodies.last;
      expect(body.keys.toSet(), {'tier', 'coachId', 'profile', 'messages'});
      // Plus, at most, the crisis-line region (compliance F1): one of four codes, never a city.
      final profile = body['profile'] as Map;
      expect(profile.keys.toSet().difference({'country'}), {'goals', 'language'});
      if (profile.containsKey('country')) expect(profile['country'], isIn(['US', 'CA', 'MX', 'ES']));
      final all = jsonEncode(body);
      for (final v1 in ['Austin', 'Hinge', '"age"', '"gender"', '"city"', 'interestedIn', '"app"']) {
        expect(all, isNot(contains(v1)), reason: 'v1 field leaked: $v1');
      }
      expect(legacyProfileKeys, containsAll(['age', 'gender', 'city', 'interestedIn', 'goal', 'app']));
    });

    test('changing the app language mid-chat keeps the coach; the profile line flips language', () async {
      final server = await FakeServer.start(streamTokens(['ok']));
      addTearDown(server.close);
      final state = await appState(client(server.uri),
          prefs: {'dw_coach': 'sofia', 'dw_profile': '{"goals":["dates"],"language":"es"}'});
      await state.sendMessage('Hola');
      await state.setLanguage(CoachLanguage.en);
      await state.sendMessage('Seguimos');
      final before = (server.bodies.first['messages'] as List).first['content'] as String;
      final after = (server.bodies.last['messages'] as List).first['content'] as String;
      expect(server.bodies.last['coachId'], 'sofia', reason: 'the coach does not change with the UI language');
      expect(before, contains('uses the app in Español'));
      // D8 fixed: the profile line names only the interface language and
      // defers to the LANGUAGE rule, so there is no competing "prefers".
      expect(after, contains('By default reply in natural, warm, neutral Latin-American Spanish'));
      expect(after, contains('uses the app in English (follow your LANGUAGE rule for replies)'));
      expect(after, isNot(contains('prefers')));
    });
  });
}
