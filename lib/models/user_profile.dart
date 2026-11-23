// The user's coaching profile, collected during onboarding so the coach can
// ground advice in what they want help with. Stored only on the device.

import 'coach.dart';

/// What the user wants help with (onboarding "goals" step). Each goal also
/// seeds one item of "Your plan this week".
enum CoachingGoal {
  conversations('Better conversations'),
  profile('A stronger profile'),
  dates('Great first dates'),
  confidence('More confidence'),
  relationship('A healthier relationship');

  const CoachingGoal(this.label);

  /// English name, used in the profile summary sent to the coach model (the
  /// UI shows the localized name, see `AppLocalizations.goal`).
  final String label;
}

T? _enumOrNull<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// Keys the v1 app (1.0.x) stored in `dw_profile`: age, gender, city, who
/// the user is interested in, dating goal and dating app. v2 never reads,
/// sends or keeps them; [StorageService.loadProfile] removes them from
/// storage on the first launch after the update.
const legacyProfileKeys = ['gender', 'age', 'interestedIn', 'goal', 'app', 'city'];

/// The v2 profile: only the coaching goals and the language (plus the Coach
/// memory note on the copy sent to the coach while memory is ON).
class UserProfile {
  const UserProfile({
    this.goals = const [],
    this.language = CoachLanguage.en,
    this.memory,
  });

  /// What the user wants help with, in the order they picked.
  final List<CoachingGoal> goals;

  /// Preferred coaching language (suggests coaches, plan wording, speech).
  final CoachLanguage language;

  /// The user's "Coach memory" summary. Only ever set on the copy sent to the
  /// coach, and only while Coach memory is ON (see AppState.profileForCoach).
  final String? memory;

  UserProfile copyWith({
    List<CoachingGoal>? goals,
    CoachLanguage? language,
    String? memory,
    bool clearMemory = false,
  }) =>
      UserProfile(
        goals: goals ?? this.goals,
        language: language ?? this.language,
        memory: clearMemory ? null : (memory ?? this.memory),
      );

  /// A one-line summary the coach uses to personalize its advice.
  String get summary {
    final parts = <String>[];
    if (goals.isNotEmpty) {
      parts.add('wants help with: ${goals.map((g) => g.label.toLowerCase()).join(', ')}');
    }
    // Only the interface language: the coach's LANGUAGE rule decides the
    // reply language, so this must not read as a competing instruction.
    parts.add('uses the app in ${language.label} (follow your LANGUAGE rule for replies)');
    return parts.join('; ');
  }

  Map<String, dynamic> toJson() => {
        'goals': goals.map((g) => g.name).toList(),
        'language': language.name,
        if (memory != null && memory!.trim().isNotEmpty) 'memory': memory!.trim(),
      };

  /// Reads only the v2 fields; any legacy v1 key in [json] is ignored.
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        goals: [
          for (final g in (json['goals'] as List? ?? const []))
            if (_enumOrNull(CoachingGoal.values, g) case final goal?) goal,
        ],
        language: CoachLanguage.fromCode(json['language'] as String?),
        // A stored profile never carries memory; it lives in its own setting.
      );
}
