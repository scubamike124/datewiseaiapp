// "Replies appear duplicated" (owner's iPhone test of build 203). The data
// path is proven clean here, from the exact bytes the chat-v7 Worker streams
// (test/fixtures/chat_v7_stream_es.sse, captured by
// tool/live/capture_chat_stream.mjs from backend/worker.js through the local
// test harness) to the saved conversation: a reply is added to the message
// list once, a retry never doubles it, and it is spoken once. What the owner
// saw twice was the presentation: the voice stage's caption printed the whole
// reply above the message list's bubble with the same text. The caption is now
// one sentence (see voice_conversation_test.dart); the last test here pins that
// the full reply is on screen once.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';

import 'fake_voice.dart';
import 'helpers.dart';

final _bytes = File('test/fixtures/chat_v7_stream_es.sse').readAsBytesSync();

/// The reply the fixture's events spell out (every `response` field, once).
String get _expected {
  final out = StringBuffer();
  for (final line in utf8.decode(_bytes).split('\n')) {
    if (!line.startsWith('data: {')) continue;
    final r = (jsonDecode(line.substring(6)) as Map)['response'];
    if (r is String) out.write(r);
  }
  return out.toString();
}

/// A client that streams the fixture, in [pieces] arbitrary byte pieces.
class _Wire {
  _Wire(this.script);

  /// One entry per HTTP request: a status and the chunks (null: connection error).
  final List<({int status, List<List<int>>? chunks, bool breakAfter})> script;
  var requests = 0;

  http.Client client() => MockClient.streaming((req, body) async {
        await body.drain<void>();
        final step = script[requests < script.length ? requests : script.length - 1];
        requests++;
        if (step.chunks == null) throw const SocketException('connection lost');
        final c = StreamController<List<int>>();
        () async {
          for (final chunk in step.chunks!) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
            c.add(chunk);
          }
          if (step.breakAfter) {
            c.addError(const SocketException('reset by peer'));
          }
          await c.close();
        }();
        return http.StreamedResponse(c.stream, step.status, headers: {'content-type': 'text/event-stream'});
      });
}

List<List<int>> _split(List<int> b, int n) => [for (var i = 0; i < b.length; i += n) b.sublist(i, i + n > b.length ? b.length : i + n)];

BackendAIService _ai(_Wire w) => BackendAIService(
      endpoint: 'https://coach.example.test/chat',
      clientFactory: w.client,
      retryDelay: const Duration(milliseconds: 1),
    );

Future<AppState> _state(BackendAIService ai) async {
  SharedPreferences.setMockInitialValues(onboardedPrefs(coach: 'sofia', language: 'es'));
  final storage = await StorageService.create();
  return AppState(storage: storage, ai: ai, store: FakeStoreService(entitled: true));
}

List<ChatMessage> _coachReplies(AppState s) => s.activeThread!.messages.where((m) => !m.isUser).toList();

void _expectNoRepeatedText(AppState s) {
  final seen = <String>{};
  for (final m in s.activeThread!.messages) {
    final t = m.text.trim();
    if (t.isEmpty) continue;
    expect(seen.add('${m.role.name}:$t'), isTrue, reason: 'the same ${m.role.name} text was added to the list twice: $t');
  }
}

void main() {
  test('the Worker bytes parse to the reply once, at any chunk size', () async {
    for (final n in [1, 2, 3, 7, 40, 1000]) {
      final tokens = await BackendAIService.parseSse(Stream.fromIterable(_split(_bytes, n))).toList();
      expect(tokens.join(), _expected, reason: 'chunk size $n');
    }
    // The final usage event ({"response":"", "usage":…}) adds nothing, and [DONE] ends the stream.
    expect(_expected, isNot(contains('prompt_tokens')));
    expect(_expected.split('Tu paso de hoy').length, 2, reason: 'the last sentence is in the text exactly once');
  });

  test('streamReply over the wire: one request, the reply once', () async {
    final w = _Wire([(status: 200, chunks: _split(_bytes, 53), breakAfter: false)]);
    final tokens = await _ai(w).streamReply(history: [ChatMessage(id: '1', role: MessageRole.user, text: 'Hola', createdAt: DateTime(2026))], tier: SubscriptionTier.magnet).toList();
    expect(tokens.join(), _expected);
    expect(w.requests, 1);
  });

  test('a conversation: one user message, one coach reply, the reply text once', () async {
    final w = _Wire([(status: 200, chunks: _split(_bytes, 41), breakAfter: false)]);
    final s = await _state(_ai(w));
    await s.sendMessage('Hola');
    final msgs = s.activeThread!.messages;
    // greeting, user, coach
    expect(msgs.map((m) => m.role.name), ['coach', 'user', 'coach']);
    expect(_coachReplies(s).last.text, _expected);
    expect(_coachReplies(s).last.status, MessageStatus.ok);
    expect(msgs.where((m) => m.text.contains('Tu paso de hoy')).length, 1);
    _expectNoRepeatedText(s);
    // And the saved copy is the same.
    final saved = StorageService(await SharedPreferences.getInstance()).loadThreads().first.messages;
    expect(saved.length, msgs.length);
    expect(saved.last.text, _expected);
  });

  test('retry before any text (HTTP 503, then 200): one reply, two requests at most', () async {
    final w = _Wire([
      (status: 503, chunks: [utf8.encode('{"error":"busy"}')], breakAfter: false),
      (status: 200, chunks: _split(_bytes, 60), breakAfter: false),
    ]);
    final s = await _state(_ai(w));
    await s.sendMessage('Hola');
    expect(w.requests, 2);
    expect(_coachReplies(s).last.text, _expected);
    expect(_coachReplies(s).length, 2, reason: 'greeting and one reply');
    _expectNoRepeatedText(s);
  });

  test('a connection error before text is retried once, still one reply', () async {
    final w = _Wire([
      (status: 200, chunks: null, breakAfter: false),
      (status: 200, chunks: _split(_bytes, 60), breakAfter: false),
    ]);
    final s = await _state(_ai(w));
    await s.sendMessage('Hola');
    expect(w.requests, 2);
    expect(_coachReplies(s).last.text, _expected);
    _expectNoRepeatedText(s);
  });

  test('a stream cut after the first words is never re-sent: no doubled text; "Try again" replaces the partial', () async {
    final head = _split(_bytes, 130).take(1).toList();
    final w = _Wire([
      (status: 200, chunks: head, breakAfter: true),
      (status: 200, chunks: _split(_bytes, 60), breakAfter: false),
    ]);
    final s = await _state(_ai(w));
    await s.sendMessage('Hola');
    expect(w.requests, 1, reason: 'a reply that started is not requested again by itself');
    final failed = _coachReplies(s).last;
    expect(failed.status, MessageStatus.failed);
    expect(failed.text, isNot(contains('Tu paso de hoy')));
    expect(s.canRetry, isTrue);

    await s.retryLastReply();
    expect(w.requests, 2);
    final replies = _coachReplies(s);
    expect(replies.length, 2, reason: 'the failed partial was replaced, not kept beside the new reply');
    expect(replies.last.text, _expected);
    _expectNoRepeatedText(s);
  });

  test('a stream that ends without [DONE] fails (truncated), it is not saved as a second copy', () async {
    final noDone = utf8.encode(utf8.decode(_bytes).replaceAll('data: [DONE]\n\n', ''));
    final w = _Wire([(status: 200, chunks: _split(noDone, 80), breakAfter: false)]);
    final s = await _state(_ai(w));
    await s.sendMessage('Hola');
    expect(w.requests, 1);
    expect(_coachReplies(s).last.status, MessageStatus.failed);
    expect(_coachReplies(s).length, 2);
  });

  test('two quick sends do not start two replies', () async {
    final w = _Wire([(status: 200, chunks: _split(_bytes, 20), breakAfter: false)]);
    final s = await _state(_ai(w));
    final a = s.sendMessage('Hola');
    final b = s.sendMessage('Hola otra vez');
    expect(await b, isFalse);
    await a;
    expect(w.requests, 1);
    expect(_coachReplies(s).length, 2);
    _expectNoRepeatedText(s);
  });

  Future<void> openVoice(WidgetTester t, TestApp app, ScriptedVoice voice) async {
    setSurface(t, const Size(393, 852), 1.0);
    await t.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat), speech: _Speech(), voice: voice));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('voice-mode')));
    await t.pumpAndSettle();
  }

  testWidgets('voice mode: the reply is spoken once and its full text is on screen once', (t) async {
    final w = _Wire([(status: 200, chunks: _split(_bytes, 60), breakAfter: false)]);
    SharedPreferences.setMockInitialValues({...onboardedPrefs(coach: 'sofia', language: 'es'), 'dw_voice_avatar_collapsed': false});
    final storage = await StorageService.create();
    final store = FakeStoreService(entitled: true);
    final state = AppState(storage: storage, ai: _ai(w), store: store);
    final voice = ScriptedVoice();
    await openVoice(t, TestApp(state, store, storage), voice);

    await t.runAsync(() => state.sendMessage('Hola'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(voice.spoken.length, 1, reason: 'spoken once');
    // Unrelated rebuilds (captions toggle, timer ticks) do not speak it again.
    await t.tap(find.byKey(const ValueKey('toggle-captions')));
    await t.pump(const Duration(seconds: 2));
    await t.tap(find.byKey(const ValueKey('toggle-captions')));
    await t.pump(const Duration(seconds: 2));
    expect(voice.spoken.length, 1);

    // A distinctive sentence from the end of the reply is on screen exactly once
    // (the message bubble); the subtitle is a short sentence, never the whole reply.
    final tail = RegExp(r'Tu paso de hoy');
    expect(find.textContaining(tail, findRichText: true).evaluate().length, 1);
    final caption = t.widget<Text>(find.byKey(const ValueKey('voice-caption'))).data!;
    expect(caption.length, lessThan(_expected.length ~/ 2));
    expect(_expected, contains(caption.replaceAll(RegExp(r'\s+'), ' ').split('…').first.trim()));
  });
}

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
