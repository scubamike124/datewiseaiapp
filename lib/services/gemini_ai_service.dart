import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/batch_photo_analysis.dart';
import '../models/chat_message.dart';
import '../models/coach.dart';
import '../models/photo_analysis.dart';
import '../models/tier.dart';
import '../models/user_profile.dart';
import 'ai_service.dart';

/// Real AI coach backed by Google Gemini (PRD section 6.2 names a Gemini flash
/// model behind the Lovable AI Gateway). Wired automatically when an API key is
/// configured; otherwise the app uses [MockAIService].
class GeminiAIService implements AIService {
  GeminiAIService({
    required String apiKey,
    required String model,
    required this.systemPromptBuilder,
  })  : _apiKey = apiKey,
        _modelName = model;

  final String _apiKey;
  final String _modelName;
  final String Function(SubscriptionTier, {UserProfile? profile, Coach? coach})
      systemPromptBuilder;

  @override
  String get providerLabel => 'Gemini ($_modelName)';

  GenerativeModel _modelFor(SubscriptionTier tier,
          {UserProfile? profile, Coach? coach}) =>
      GenerativeModel(
        model: _modelName,
        apiKey: _apiKey,
        systemInstruction: Content.system(
            systemPromptBuilder(tier, profile: profile, coach: coach)),
      );

  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) async* {
    final model = _modelFor(tier, profile: profile, coach: coach);
    final contents = history
        .where((m) => m.text.trim().isNotEmpty || m.imageBase64 != null)
        .map(_toContent)
        .toList();

    try {
      final stream = model.generateContentStream(contents);
      await for (final chunk in stream) {
        final text = chunk.text;
        if (text != null && text.isNotEmpty) yield text;
      }
    } catch (e) {
      yield "I hit a snag reaching my brain just now. Mind trying that again in a moment?";
    }
  }

  Content _toContent(ChatMessage m) {
    final role = m.isUser ? 'user' : 'model';
    final parts = <Part>[];
    if (m.imageBase64 != null) {
      parts.add(DataPart('image/jpeg', base64Decode(m.imageBase64!)));
    }
    if (m.text.trim().isNotEmpty) {
      parts.add(TextPart(m.text));
    }
    if (parts.isEmpty) parts.add(TextPart(' '));
    return Content(role, parts);
  }

  @override
  Future<PhotoAnalysis> analyzePhoto({
    required String imageBase64,
    required SubscriptionTier tier,
    String? userNote,
    AnalysisMode mode = AnalysisMode.deep,
  }) async {
    final model = _modelFor(tier);
    final note =
        userNote != null && userNote.isNotEmpty ? 'User note: $userNote' : '';
    // Quick mode keeps the response tiny (no dimension breakdown, one tip) to
    // save tokens; deep mode returns the full critique.
    final prompt = mode == AnalysisMode.quick
        ? '''
Analyse this dating-profile photo as DateWise AI. Respond with ONLY valid JSON, no
markdown, matching exactly this shape (keep it terse):
{
  "overallScore": <int 1-10>,
  "verdict": "KEEP" | "RESHOOT" | "DELETE",
  "headline": "<one punchy sentence>",
  "matchRateDelta": <int, predicted % match-rate change if tips applied>,
  "dimensions": [],
  "tips": ["<one actionable tip>"]
}
$note'''
        : '''
Analyse this dating-profile photo as DateWise AI. Respond with ONLY valid JSON, no
markdown, matching exactly this shape:
{
  "overallScore": <int 1-10>,
  "verdict": "KEEP" | "RESHOOT" | "DELETE",
  "headline": "<one punchy sentence>",
  "matchRateDelta": <int, predicted % match-rate change if tips applied>,
  "dimensions": [
    {"name":"Lighting","score":<1-10>,"note":"<short>"},
    {"name":"Expression","score":<1-10>,"note":"<short>"},
    {"name":"Outfit","score":<1-10>,"note":"<short>"},
    {"name":"Framing","score":<1-10>,"note":"<short>"},
    {"name":"Overall vibe","score":<1-10>,"note":"<short>"}
  ],
  "tips": ["<actionable>", "<actionable>", "<actionable>"]
}
$note''';

    final response = await model.generateContent([
      Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', base64Decode(imageBase64)),
      ]),
    ]);

    final raw = (response.text ?? '').trim();
    final jsonStr = _extractJson(raw);
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return PhotoAnalysis.fromJson(map);
  }

  @override
  Future<BatchPhotoAnalysis> analyzePhotos({
    required List<String> imageBase64s,
    required SubscriptionTier tier,
    String? userNote,
    AnalysisMode mode = AnalysisMode.deep,
  }) async {
    // Analyse each photo, then rank by score. (The Cloudflare backend is the
    // default provider; this keeps the direct-Gemini path functional too.)
    final results = await Future.wait(imageBase64s.map(
      (b64) => analyzePhoto(
        imageBase64: b64,
        tier: tier,
        userNote: userNote,
        mode: AnalysisMode.quick,
      ),
    ));

    final order = List.generate(results.length, (i) => i)
      ..sort((a, b) => results[b].overallScore.compareTo(results[a].overallScore));

    final photos = <RankedPhoto>[];
    for (var rank = 0; rank < order.length; rank++) {
      final i = order[rank];
      final r = results[i];
      photos.add(RankedPhoto(
        imageIndex: i,
        rank: rank + 1,
        overallScore: r.overallScore,
        verdict: r.verdict,
        headline: r.headline,
        why: r.tips.isNotEmpty ? r.tips.first : r.headline,
      ));
    }

    final best = order.isEmpty ? 0 : order.first;
    return BatchPhotoAnalysis(
      photos: photos,
      bestIndex: best,
      recommendation: 'Lead with photo #${best + 1}.',
      thumbnails: imageBase64s,
    );
  }

  /// Strips ```json fences or surrounding prose the model may add.
  String _extractJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return raw;
    return raw.substring(start, end + 1);
  }
}
