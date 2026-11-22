import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../models/batch_photo_analysis.dart';
import '../models/chat_message.dart';
import '../models/coach.dart';
import '../models/photo_analysis.dart';
import '../models/tier.dart';
import '../models/user_profile.dart';
import 'ai_service.dart';
import 'persona.dart';

/// Thrown when the coach backend cannot produce a reply: network error,
/// timeout, a non-200 response or an empty stream. The chat shows a friendly,
/// localized notice with "Try again"; the user's message is kept.
class CoachUnavailableException implements Exception {
  const CoachUnavailableException(this.reason, {this.statusCode});
  final String reason;
  final int? statusCode;
  @override
  String toString() => 'CoachUnavailableException($reason${statusCode == null ? '' : ', HTTP $statusCode'})';
}

/// Talks to the secure DateWise coach backend (a Cloudflare Worker,
/// `backend/worker.js`). The app holds no API keys: it only knows the
/// Worker's public HTTPS URL, and the model runs server-side.
///
/// Chat request (chat-v6): `POST {messages:[{role,content}...], coachId,
/// profile, tier}`. chat-v6 reads only `messages` (system prompt first) and
/// ignores the other fields; a later Worker may use `coachId`/`profile` to
/// build the prompt itself.
///
/// Reply: Server-Sent Events, `data: {"response":"…"}` lines ending with
/// `data: [DONE]` (Workers AI format; OpenAI-style `choices[0].delta.content`
/// is accepted too).
class BackendAIService implements AIService {
  BackendAIService({
    required this.endpoint,
    http.Client Function()? clientFactory,
    this.connectTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 30),
  }) : _clientFactory = clientFactory ?? http.Client.new {
    final uri = Uri.parse(endpoint);
    if (uri.scheme != 'https') {
      throw ArgumentError.value(endpoint, 'endpoint', 'The coach backend must use HTTPS');
    }
  }

  final String endpoint;
  final http.Client Function() _clientFactory;

  /// Time allowed until the response headers arrive.
  final Duration connectTimeout;

  /// Longest silence allowed between two chunks of the stream.
  final Duration idleTimeout;

  @override
  String get providerLabel => 'DateWise coach · secure backend';

  /// Streams the coach's reply token by token. Errors surface as
  /// [CoachUnavailableException] (never as fake coaching text). Canceling
  /// the subscription closes the HTTP connection.
  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) async* {
    final payload = jsonEncode(buildPayload(history, tier, profile, coach));
    final client = _clientFactory();
    try {
      final req = http.Request('POST', Uri.parse(endpoint))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = payload;
      final http.StreamedResponse res;
      try {
        res = await client.send(req).timeout(connectTimeout);
      } on TimeoutException {
        throw const CoachUnavailableException('timeout');
      } catch (e) {
        throw CoachUnavailableException('network: $e');
      }

      if (res.statusCode != 200) {
        // Read (a bounded amount of) the error body so the connection is freed.
        await res.stream.drain<void>().timeout(const Duration(seconds: 5), onTimeout: () {});
        throw CoachUnavailableException('http', statusCode: res.statusCode);
      }

      var emitted = false;
      try {
        await for (final token in parseSse(res.stream.timeout(idleTimeout))) {
          emitted = true;
          yield token;
        }
      } on CoachUnavailableException {
        rethrow;
      } on TimeoutException {
        throw const CoachUnavailableException('timeout');
      } catch (e) {
        throw CoachUnavailableException('stream: $e');
      }
      if (!emitted) throw const CoachUnavailableException('empty');
    } finally {
      client.close();
    }
  }

  /// Parses a Server-Sent Events byte stream into reply tokens. Handles
  /// `\n`, `\r\n` and `\r` line endings, events and UTF-8 characters split
  /// across chunks, `data:` with or without a space, comments/keep-alives,
  /// a final line without a newline, and stops at `data: [DONE]`. An
  /// in-stream `{"error": …}` event throws [CoachUnavailableException].
  static Stream<String> parseSse(Stream<List<int>> bytes) async* {
    final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue; // comments, event:, id:, blanks
      var data = line.substring(5);
      if (data.startsWith(' ')) data = data.substring(1);
      data = data.trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') return;
      final token = tokenFrom(data);
      if (token != null && token.isNotEmpty) yield token;
    }
  }

  /// The text in one SSE `data:` payload, or null for keep-alives and
  /// non-JSON lines.
  @visibleForTesting
  static String? tokenFrom(String data) {
    Object? obj;
    try {
      obj = jsonDecode(data);
    } catch (_) {
      return null;
    }
    if (obj is! Map) return null;
    if (obj['error'] != null) throw CoachUnavailableException('stream error: ${obj['error']}');
    final r = obj['response'];
    if (r is String) return r;
    final choices = obj['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final delta = (choices.first as Map)['delta'];
      if (delta is Map && delta['content'] is String) return delta['content'] as String;
    }
    return null;
  }

  /// The chat request body. `coachId` and the structured `profile` let a
  /// later Worker build the coach's system prompt itself (it then ignores
  /// ours); the system message stays so an older Worker keeps working.
  @visibleForTesting
  Map<String, Object> buildPayload(
    List<ChatMessage> history,
    SubscriptionTier tier,
    UserProfile? profile, [
    Coach? coach,
  ]) =>
      {
        'tier': tier.name,
        'coachId': (coach ?? Coaches.fallback).id,
        if (profile != null) 'profile': profile.toJson(),
        'messages': buildMessages(history, tier, profile, coach),
      };

  /// Builds the OpenAI-style message list for the worker: a system prompt
  /// (DateWise persona + the user's profile) followed by the conversation.
  @visibleForTesting
  List<Map<String, String>> buildMessages(
    List<ChatMessage> history,
    SubscriptionTier tier,
    UserProfile? profile, [
    Coach? coach,
  ]) {
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': CoachPersona.systemPrompt(tier, profile: profile, coach: coach),
      },
    ];
    for (final m in history) {
      if (!m.isComplete) continue; // failed / stopped / streaming replies
      var text = m.text.trim();
      if (text.isEmpty) {
        // Keep photo-only turns in the thread so the model has context.
        final hasPhoto =
            m.imageBase64 != null || (m.imageBase64s?.isNotEmpty ?? false);
        if (!hasPhoto) continue;
        text = m.isUser ? '[shared a photo for review]' : '[gave a photo critique]';
      }
      messages.add({'role': m.isUser ? 'user' : 'assistant', 'content': text});
    }
    return messages;
  }

  @override
  Future<PhotoAnalysis> analyzePhoto({
    required String imageBase64,
    required SubscriptionTier tier,
    String? userNote,
    AnalysisMode mode = AnalysisMode.deep,
  }) async {
    final res = await http
        .post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'imageBase64': imageBase64,
            'mimeType': 'image/jpeg',
            'tier': tier.name,
            'mode': mode.name,
            if (userNote != null && userNote.isNotEmpty) 'userNote': userNote,
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (res.statusCode != 200) {
      throw Exception(
        'Photo coach backend error (${res.statusCode}): ${res.body}',
      );
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return PhotoAnalysis.fromJson(map);
  }

  @override
  Future<BatchPhotoAnalysis> analyzePhotos({
    required List<String> imageBase64s,
    required SubscriptionTier tier,
    String? userNote,
    AnalysisMode mode = AnalysisMode.deep,
  }) async {
    final res = await http
        .post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'images': imageBase64s,
            'mimeType': 'image/jpeg',
            'tier': tier.name,
            'mode': mode.name,
            if (userNote != null && userNote.isNotEmpty) 'userNote': userNote,
          }),
        )
        // Batch runs several vision passes server-side; allow extra time.
        .timeout(const Duration(seconds: 90));

    if (res.statusCode != 200) {
      throw Exception(
        'Photo coach backend error (${res.statusCode}): ${res.body}',
      );
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    // Carry the uploaded images so the result card can show thumbnails.
    return BatchPhotoAnalysis.fromJson(map)
        .copyWithThumbnails(imageBase64s);
  }
}
