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

// Legacy fields from the first onboarding (kept so older saves still load and
// are still sent to the coach; the v2 onboarding no longer asks for them).
enum Gender {
  male('Male'),
  female('Female'),
  nonbinary('Non-binary');

  const Gender(this.label);
  final String label;
}

enum InterestedIn {
  women('Women'),
  men('Men'),
  everyone('Everyone');

  const InterestedIn(this.label);
  final String label;
}

enum DatingGoal {
  serious('Something serious'),
  casual('Casual dating'),
  moreMatches('More matches'),
  unsure('Still figuring it out');

  const DatingGoal(this.label);
  final String label;
}

enum DatingApp {
  hinge('Hinge'),
  tinder('Tinder'),
  bumble('Bumble'),
  raya('Raya'),
  other('Other');

  const DatingApp(this.label);
  final String label;
}

T? _enumOrNull<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

class UserProfile {
  const UserProfile({
    this.goals = const [],
    this.language = CoachLanguage.en,
    this.memory,
    this.gender,
    this.age,
    this.interestedIn,
    this.goal,
    this.app,
    this.city,
  });

  /// What the user wants help with, in the order they picked.
  final List<CoachingGoal> goals;

  /// Preferred coaching language (suggests coaches, plan wording, speech).
  final CoachLanguage language;

  /// The user's "Coach memory" summary. Only ever set on the copy sent to the
  /// coach, and only while Coach memory is ON (see AppState.profileForCoach).
  final String? memory;

  final Gender? gender;
  final int? age;
  final InterestedIn? interestedIn;
  final DatingGoal? goal;
  final DatingApp? app;
  final String? city;

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
        gender: gender,
        age: age,
        interestedIn: interestedIn,
        goal: goal,
        app: app,
        city: city,
      );

  /// A one-line summary the coach uses to personalize its advice.
  String get summary {
    final parts = <String>[];
    if (age != null && age! > 0) parts.add('$age years old');
    if (gender != null) parts.add(gender!.label.toLowerCase());
    if (city != null && city!.trim().isNotEmpty) parts.add('in ${city!.trim()}');
    if (interestedIn != null) parts.add('interested in ${interestedIn!.label.toLowerCase()}');
    if (goal != null) parts.add('looking for ${goal!.label.toLowerCase()}');
    if (app != null) parts.add('on ${app!.label}');
    if (goals.isNotEmpty) {
      parts.add('wants help with: ${goals.map((g) => g.label.toLowerCase()).join(', ')}');
    }
    parts.add('prefers ${language.label}');
    return parts.join('; ');
  }

  Map<String, dynamic> toJson() => {
        'goals': goals.map((g) => g.name).toList(),
        'language': language.name,
        if (memory != null && memory!.trim().isNotEmpty) 'memory': memory!.trim(),
        if (gender != null) 'gender': gender!.name,
        if (age != null) 'age': age,
        if (interestedIn != null) 'interestedIn': interestedIn!.name,
        if (goal != null) 'goal': goal!.name,
        if (app != null) 'app': app!.name,
        if (city != null) 'city': city,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        goals: [
          for (final g in (json['goals'] as List? ?? const []))
            if (_enumOrNull(CoachingGoal.values, g) case final goal?) goal,
        ],
        language: CoachLanguage.fromCode(json['language'] as String?),
        // A stored profile never carries memory; it lives in its own setting.
        gender: _enumOrNull(Gender.values, json['gender']),
        age: (json['age'] as num?)?.toInt(),
        interestedIn: _enumOrNull(InterestedIn.values, json['interestedIn']),
        goal: _enumOrNull(DatingGoal.values, json['goal']),
        app: _enumOrNull(DatingApp.values, json['app']),
        city: json['city'] as String?,
      );
}
