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

/// Routes the premium **AI Photo Coach** through a secure backend (a Cloudflare
/// Worker that holds the Gemini key server-side), while delegating chat replies
/// to [chatFallback] (the offline mock by default).
///
/// This keeps the API key out of the web build entirely — the app only knows
/// the Worker's public URL.
class BackendAIService implements AIService {
  BackendAIService({required this.endpoint, required this.chatFallback});

  final String endpoint;
  final AIService chatFallback;

  @override
  String get providerLabel => 'Gemini · secure backend';

  /// Streams a real coaching reply from the backend's free text model. The
  /// reply arrives as Server-Sent Events (`data: {"response":"…"}` lines); we
  /// parse out each token and yield it. Any network/parse failure before the
  /// first token degrades gracefully to the offline [chatFallback] so the user
  /// always gets an answer.
  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) async* {
    final payload = jsonEncode(buildPayload(history, tier, profile, coach));

    final client = http.Client();
    var emittedAny = false;
    try {
      final req = http.Request('POST', Uri.parse(endpoint))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = payload;
      final res = await client.send(req).timeout(const Duration(seconds: 45));

      if (res.statusCode != 200) {
        await res.stream.drain<void>();
        // Production must never silently substitute mock coaching for live AI.
        yield unavailableMessage(coach);
        return;
      }

      final lines =
          res.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        final token = _tokenFrom(data);
        if (token != null && token.isNotEmpty) {
          emittedAny = true;
          yield token;
        }
      }

      if (!emittedAny) {
        yield unavailableMessage(coach);
      }
    } catch (_) {
      if (!emittedAny) {
        yield unavailableMessage(coach);
      }
    } finally {
      client.close();
    }
  }

  /// Shown when the live coach cannot be reached, in the coach's language.
  static String unavailableMessage(Coach? coach) => coach?.language == CoachLanguage.es
      ? 'Ahora mismo no puedo conectar con tu coach de DateWise. '
          'Inténtalo de nuevo en un momento: es un problema temporal de conexión, no un consejo.'
      : "I'm having trouble reaching the DateWise coach right now. "
          "Please try again in a moment — this is a temporary connection issue, not advice.";

  /// Extracts the incremental text from one SSE `data:` payload, ignoring
  /// keep-alives and any partial/non-JSON lines.
  String? _tokenFrom(String data) {
    try {
      final obj = jsonDecode(data);
      if (obj is Map && obj['response'] is String) return obj['response'] as String;
    } catch (_) {/* ignore non-JSON keep-alive lines */}
    return null;
  }

  /// The chat request body. `coachId` and the structured `profile` let a
  /// chat-v7 Worker build the coach's system prompt itself (it then ignores
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
