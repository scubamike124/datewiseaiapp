import '../models/batch_photo_analysis.dart';
import '../models/chat_message.dart';
import '../models/coach.dart';
import '../models/photo_analysis.dart';
import '../models/tier.dart';
import '../models/user_profile.dart';
import 'ai_config.dart';
import 'backend_ai_service.dart';
import 'mock_ai_service.dart';

/// Abstraction over the AI coach so the UI never depends on a concrete
/// provider. The secure backend client and the offline mock both implement this.
abstract class AIService {
  /// Streams the coach's reply token-by-token for real-time rendering
  /// (PRD non-functional requirement: responses stream in real-time).
  ///
  /// [history] is the full thread (oldest first), with the latest user message
  /// already appended. [tier] gates which capabilities the coach will use.
  /// [profile] (when known) lets the coach ground advice in the user's specifics.
  /// [coach] (default Ava) sets who answers and in which language.
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  });

  /// Analyzes an uploaded photo (not used by the v2 app UI). Returns a structured
  /// score/verdict/feedback result. [mode] selects a fast/cheap pass vs the
  /// full breakdown (see [AnalysisMode]).
  Future<PhotoAnalysis> analyzePhoto({
    required String imageBase64,
    required SubscriptionTier tier,
    String? userNote,
    AnalysisMode mode = AnalysisMode.deep,
  });

  /// Analyzes several photos together (Magnet tier), scoring each and ranking
  /// the set best→worst with an overall recommendation (rank & compare).
  Future<BatchPhotoAnalysis> analyzePhotos({
    required List<String> imageBase64s,
    required SubscriptionTier tier,
    String? userNote,
    AnalysisMode mode = AnalysisMode.deep,
  });

  /// Human-readable provider label for diagnostics / settings.
  String get providerLabel;
}

/// Decides which [AIService] implementation to use based on [AIConfig].
class AIServiceFactory {
  static AIService create() {
    // Production: the secure coach backend (HTTPS; the model and any keys
    // stay server-side). Without a configured URL the offline demo coach runs.
    if (AIConfig.hasCoachBackend) {
      return BackendAIService(endpoint: AIConfig.coachBackendUrl);
    }
    return MockAIService();
  }
}
