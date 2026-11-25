import 'package:flutter/widgets.dart';

import '../models/coach.dart';
import '../models/user_profile.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// `context.l10n.getStarted` instead of `AppLocalizations.of(context)...`.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// The two app languages. The UI language is the user's choice (onboarding or
/// You › Language) and, before they choose, the device language: any Spanish
/// locale (es, es-MX, es-US, es-ES…) gives Spanish, everything else English.
class AppLocales {
  AppLocales._();

  static const en = Locale('en');
  static const es = Locale('es');
  static const supported = [en, es];

  static Locale of(CoachLanguage language) => language == CoachLanguage.es ? es : en;

  static CoachLanguage languageOf(Locale locale) =>
      locale.languageCode == 'es' ? CoachLanguage.es : CoachLanguage.en;

  /// The device's preferred language among English and Spanish: the first
  /// preferred locale that is either; English when there is none.
  static Locale resolve(List<Locale>? preferred) {
    for (final l in preferred ?? const <Locale>[]) {
      if (l.languageCode == 'es') return es;
      if (l.languageCode == 'en') return en;
    }
    return en;
  }
}

/// Coach copy shown in the app chrome, in the UI language. (What a coach says
/// in chat, its greeting and starters, stays in the coach's own language.)
extension CoachL10n on AppLocalizations {
  String coachDescription(Coach coach) => switch (coach.id) {
        'ethan' => coachDescEthan,
        'sofia' => coachDescSofia,
        'diego' => coachDescDiego,
        _ => coachDescAva,
      };

  /// "English" / "Spanish" in English, "Inglés" / "Español" in Spanish.
  String languageName(CoachLanguage language) =>
      language == CoachLanguage.es ? languageNameEs : languageNameEn;

  /// The coaches who speak [language] ("Coaches: Ava and Ethan").
  String coachesFor(CoachLanguage language) =>
      language == CoachLanguage.es ? coachesForEs : coachesForEn;

  String aiLabel(Coach coach) => coachAiLabel(languageName(coach.language));

  /// The chat header's subtitle: no language, so it never truncates (the
  /// language is in [aiLabel], read by VoiceOver, and in the coach's chip).
  String get aiLabelShort => coachAiLabelShort;

  String chip(Coach coach) => coachChip(coach.name, languageName(coach.language));

  /// `female` / `male`, for the Spanish adjective agreement in a few strings.
  String gender(Coach coach) => coach.gender.name;

  String goal(CoachingGoal goal) => switch (goal) {
        CoachingGoal.conversations => goalConversations,
        CoachingGoal.profile => goalProfile,
        CoachingGoal.dates => goalDates,
        CoachingGoal.confidence => goalConfidence,
        CoachingGoal.relationship => goalRelationship,
      };

  String planItemTitle(CoachingGoal goal, Coach coach) => switch (goal) {
        CoachingGoal.conversations => planItemConversations(coach.name),
        CoachingGoal.profile => planItemProfile(coach.name),
        CoachingGoal.dates => planItemDates,
        CoachingGoal.confidence => planItemConfidence,
        CoachingGoal.relationship => planItemRelationship,
      };

  String planItemPrompt(CoachingGoal goal) => switch (goal) {
        CoachingGoal.conversations => planPromptConversations,
        CoachingGoal.profile => planPromptProfile,
        CoachingGoal.dates => planPromptDates,
        CoachingGoal.confidence => planPromptConfidence,
        CoachingGoal.relationship => planPromptRelationship,
      };

  String greetingFor(DateTime now) {
    final h = now.hour;
    if (h < 5) return greetingEvening;
    if (h < 12) return greetingMorning;
    if (h < 18) return greetingAfternoon;
    return greetingEvening;
  }
}
