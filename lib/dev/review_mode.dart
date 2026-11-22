import 'package:flutter/foundation.dart';

import '../models/coach.dart';
import '../models/user_profile.dart';
import '../screens/shell.dart';
import '../services/store_service.dart';
import '../state/app_state.dart';

/// Review builds only (`--dart-define=DW_FAKE_STORE=true`, optionally
/// `DW_MOCK_AI=true`): opens a given screen with sample local data so the
/// design can be reviewed on the web. Never active in a release build
/// without those flags.
class ReviewMode {
  ReviewMode._();

  /// Use the offline demo coach instead of the live backend.
  static const bool mockAI = bool.fromEnvironment('DW_MOCK_AI');

  /// `?screen=home|coaches|chat|progress|settings|paywall|welcome` on web.
  static String? requestedScreen() {
    if (!StoreConfig.useFakeStore || !kIsWeb) return null;
    return Uri.base.queryParameters['screen'];
  }

  /// Seeds the state for [screen] and returns the tab to open.
  static Future<AppTab> seed(String screen, AppState state, StoreService store) async {
    if (screen == 'welcome') return AppTab.home;
    await state.completeOnboarding(
      goals: const [CoachingGoal.profile, CoachingGoal.conversations, CoachingGoal.dates],
      language: CoachLanguage.en,
      coachId: Coaches.ava.id,
    );
    if (screen == 'paywall') return AppTab.home;
    await store.buy();
    await state.togglePlanItem(0);
    await state.sendMessage('Give me a strong opener');
    return switch (screen) {
      'coaches' => AppTab.coaches,
      'chat' => AppTab.chat,
      'progress' => AppTab.progress,
      'settings' || 'you' => AppTab.you,
      _ => AppTab.home,
    };
  }
}
