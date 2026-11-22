import 'coach.dart';
import 'user_profile.dart';

/// One item of "Your plan this week", seeded from an onboarding goal.
class PlanItem {
  PlanItem({required this.goal, this.done = false});

  final CoachingGoal goal;
  bool done;

  /// The task, in [lang], mentioning [coach] where it reads naturally.
  String title(CoachLanguage lang, Coach coach) {
    final es = lang == CoachLanguage.es;
    switch (goal) {
      case CoachingGoal.conversations:
        return es ? 'Practica un primer mensaje con ${coach.name}' : 'Practise an opener with ${coach.name}';
      case CoachingGoal.profile:
        return es ? 'Reescribe tu biografía con ${coach.name}' : 'Rewrite your bio with ${coach.name}';
      case CoachingGoal.dates:
        return es ? 'Planea una primera cita' : 'Plan a first date idea';
      case CoachingGoal.confidence:
        return es ? 'Habla de lo que te pone nervioso' : 'Talk through what makes you nervous';
      case CoachingGoal.relationship:
        return es ? 'Practica decir lo que sientes' : 'Practise saying how you feel';
    }
  }

  /// The message that starts a chat about this item.
  String prompt(CoachLanguage lang) {
    final es = lang == CoachLanguage.es;
    switch (goal) {
      case CoachingGoal.conversations:
        return es ? 'Ayúdame a practicar un primer mensaje para alguien con quien hice match.' : 'Help me practise an opener for someone I matched with.';
      case CoachingGoal.profile:
        return es ? 'Reescribe mi biografía de citas.' : 'Rewrite my dating bio.';
      case CoachingGoal.dates:
        return es ? 'Ayúdame a planear una buena primera cita.' : 'Help me plan a great first date.';
      case CoachingGoal.confidence:
        return es ? 'Me pongo nervioso antes de una cita. ¿Me ayudas?' : 'I get nervous before dates. Can you help?';
      case CoachingGoal.relationship:
        return es ? 'Ayúdame a decirle a mi pareja cómo me siento.' : 'Help me tell my partner how I feel.';
    }
  }

  Map<String, dynamic> toJson() => {'goal': goal.name, 'done': done};

  static PlanItem? fromJson(Map<String, dynamic> json) {
    for (final g in CoachingGoal.values) {
      if (g.name == json['goal']) return PlanItem(goal: g, done: json['done'] == true);
    }
    return null;
  }
}

/// Three tickable items for the current week (Monday to Sunday). Ticks reset
/// when a new week starts; the items stay.
class WeeklyPlan {
  WeeklyPlan({required this.weekStart, required this.items});

  final DateTime weekStart;
  final List<PlanItem> items;

  static const int size = 3;

  int get doneCount => items.where((i) => i.done).length;

  /// Monday 00:00 of the week containing [day].
  static DateTime weekOf(DateTime day) {
    return DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));
  }

  /// Builds the plan from the user's goals, topping up to [size] items.
  factory WeeklyPlan.fromGoals(List<CoachingGoal> goals, DateTime now) {
    final picked = <CoachingGoal>[...goals];
    for (final g in CoachingGoal.values) {
      if (picked.length >= size) break;
      if (!picked.contains(g)) picked.add(g);
    }
    return WeeklyPlan(
      weekStart: weekOf(now),
      items: [for (final g in picked.take(size)) PlanItem(goal: g)],
    );
  }

  /// The same items for the week of [now], unticked if the week changed.
  WeeklyPlan forWeekOf(DateTime now) {
    final start = weekOf(now);
    if (start == weekStart) return this;
    return WeeklyPlan(
      weekStart: start,
      items: [for (final i in items) PlanItem(goal: i.goal)],
    );
  }

  Map<String, dynamic> toJson() => {
        'weekStart': weekStart.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
      };

  static WeeklyPlan? fromJson(Map<String, dynamic> json) {
    final start = DateTime.tryParse(json['weekStart'] as String? ?? '');
    if (start == null) return null;
    final items = <PlanItem>[
      for (final e in (json['items'] as List? ?? const []))
        if (e is Map<String, dynamic>)
          if (PlanItem.fromJson(e) case final item?) item,
    ];
    if (items.isEmpty) return null;
    return WeeklyPlan(weekStart: start, items: items);
  }
}

/// Consecutive days, ending today (or yesterday, if today has no use yet),
/// on which the user messaged a coach. [days] are `yyyy-mm-dd` keys.
int currentStreak(Set<String> days, DateTime now) {
  var day = DateTime(now.year, now.month, now.day);
  if (!days.contains(dayKey(day))) {
    day = DateTime(day.year, day.month, day.day - 1);
  }
  var streak = 0;
  while (days.contains(dayKey(day))) {
    streak++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
