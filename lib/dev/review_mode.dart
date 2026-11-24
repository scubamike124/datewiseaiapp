import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/chat_message.dart';
import '../models/coach.dart';
import '../models/tier.dart';
import '../models/user_profile.dart';
import '../screens/onboarding_screen.dart';
import '../screens/shell.dart';
import '../services/ai_service.dart';
import '../services/backend_ai_service.dart';
import '../services/coach_usage.dart';
import '../services/store_service.dart';
import '../state/app_state.dart';

/// Review builds only (`--dart-define=DW_FAKE_STORE=true`, optionally
/// `DW_MOCK_AI=true`): opens a given screen with sample local data so the
/// design can be reviewed on the web. Never active in a release build
/// without those flags.
///
/// `?screen=welcome|onboarding|paywall|home|coaches|chat|chat-error|chat-limit|progress|settings`
/// `&step=1..4` (onboarding) `&lang=en|es` (UI language, and a Spanish coach).
class ReviewMode {
  ReviewMode._();

  /// Use the offline demo coach instead of the live backend.
  static const bool mockAI = bool.fromEnvironment('DW_MOCK_AI');

  static bool get _active => StoreConfig.useFakeStore && kIsWeb;

  static String? requestedScreen() => _active ? Uri.base.queryParameters['screen'] : null;

  static CoachLanguage get language =>
      Uri.base.queryParameters['lang'] == 'es' ? CoachLanguage.es : CoachLanguage.en;

  /// A screen shown instead of the welcome screen (onboarding steps).
  static Widget? home(String? screen) {
    if (screen != 'onboarding') return null;
    final step = int.tryParse(Uri.base.queryParameters['step'] ?? '') ?? 1;
    return OnboardingScreen(initialStep: (step - 1).clamp(0, 3));
  }

  /// The coach backend stand-in for `screen=chat-error` (always unreachable)
  /// and `screen=chat-limit` (always refuses with a limit code whose notice
  /// offers the paywall).
  static AIService? aiFor(String? screen) => switch (screen) {
        'chat-error' => _UnreachableCoach(),
        'chat-limit' => _UnreachableCoach(
            error: CoachUnavailableException('http', statusCode: 403, code: CoachLimitCode.subscriptionRevoked)),
        _ => null,
      };

  /// Seeds the state for [screen] and returns the tab to open.
  static Future<AppTab> seed(String screen, AppState state, StoreService store) async {
    final es = language == CoachLanguage.es;
    if (screen == 'welcome' || screen == 'onboarding') {
      if (es || Uri.base.queryParameters['lang'] == 'en') await state.setLanguage(language);
      return AppTab.home;
    }
    await state.completeOnboarding(
      goals: const [CoachingGoal.profile, CoachingGoal.conversations, CoachingGoal.dates],
      language: language,
      coachId: es ? Coaches.sofia.id : Coaches.ava.id,
      adultConfirmed: true,
    );
    if (screen == 'paywall') return AppTab.home;
    await store.buy();
    await state.togglePlanItem(0);
    await state.giveAiConsent();
    await state.sendMessage(es ? 'Dame un buen primer mensaje' : 'Give me a strong opener');
    return switch (screen) {
      'coaches' => AppTab.coaches,
      'chat' || 'chat-error' || 'chat-limit' => AppTab.chat,
      'progress' => AppTab.progress,
      'settings' || 'you' => AppTab.you,
      _ => AppTab.home,
    };
  }
}

class _UnreachableCoach implements AIService {
  _UnreachableCoach({this.error = const CoachUnavailableException('http', statusCode: 502)});
  final CoachUnavailableException error;

  @override
  String get providerLabel => 'review: unreachable coach';

  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) =>
      Stream.error(error);
}
