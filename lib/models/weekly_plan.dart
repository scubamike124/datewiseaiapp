import 'user_profile.dart';

/// One item of "Your plan this week", seeded from an onboarding goal.
class PlanItem {
  PlanItem({required this.goal, this.done = false});

  final CoachingGoal goal;
  bool done;

  // The task's wording (and the chat prompt it starts) is localized in the
  // UI: see `AppLocalizations.planItemTitle` / `planItemPrompt`.

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
