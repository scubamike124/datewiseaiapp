import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/chat_message.dart';
import '../models/coach.dart';
import 'dw.dart';
import 'plan_table_sheet.dart';

/// "Find a table" / "Buscar mesa": the v1 restaurant option (owner decisions,
/// 2026-11-23 and 2026-11-25). Under the coach's latest reply on a date-plan
/// conversation, or when the user's latest message asks about a restaurant or
/// a reservation, a compact button opens the "Plan a table" sheet
/// (plan_table_sheet.dart): area, cuisine, budget, date, time and party size,
/// then search links that open outside the app (OpenTable, Google Maps, and
/// Apple Maps where it exists). It works the same in text chat and in the
/// voice conversation (the message list is shown in both), on every platform.
///
/// No accounts, no partner APIs, no in-app booking and no location
/// permission. Nothing from the chat is sent: the links carry only what the
/// user typed into the sheet, and open only on tap.
class FindTableLink extends StatelessWidget {
  const FindTableLink({super.key});

  /// The prompts that start the first-date-plan path: Home's "Prepare for a
  /// date" quick action, the weekly plan's "Plan a first date" prompt (both in
  /// either language) and every coach starter worded like the plan's "Plan a
  /// first date" item (derived, so a reworded starter cannot drift).
  static final Set<String> _datePlanPrompts = () {
    final locales = [lookupAppLocalizations(const Locale('en')), lookupAppLocalizations(const Locale('es'))];
    final planItems = {for (final l in locales) l.planItemDates};
    return {
      for (final l in locales) ...[l.quickDatePrompt, l.planPromptDates],
      for (final c in Coaches.all)
        for (final s in c.starters)
          if (planItems.contains(s)) s,
    };
  }();

  /// Whether [messages] is a first-date-plan conversation: its first user
  /// message is one of the date-plan prompts.
  static bool isDatePlan(List<ChatMessage> messages) {
    for (final m in messages) {
      if (m.isUser) return _datePlanPrompts.contains(m.text.trim());
    }
    return false;
  }

  /// Restaurant, meal or reservation words, English and Spanish, as whole
  /// words. Dart's `\b` is ASCII-only (it fails next to the "ó" of
  /// "reservación"), so the word edges are Unicode lookarounds: no letter,
  /// digit or underscore on either side. A false positive only shows a
  /// harmless button.
  static final RegExp _tableWords = RegExp(
    r'(?<![\p{L}\p{N}_])('
    r'reservations?|reserve|book(ing)?( us)? a table|get us a table|a table|table for'
    r'|restaurants?|dinner|brunch|lunch|drinks'
    r'|reservas?|reservar|reservación|reservaciones|mesa|restaurantes?'
    r'|cena|cenar|cenamos|almuerzo|almorzar|comida'
    r')(?![\p{L}\p{N}_])',
    caseSensitive: false,
    unicode: true,
  );

  /// Whether the link belongs under the latest reply: a first-date-plan
  /// conversation, or the user's latest message asks about a restaurant or a
  /// reservation (so the coach's "tap Find a table" advice always has the button).
  static bool wantsTable(List<ChatMessage> messages) {
    if (isDatePlan(messages)) return true;
    for (final m in messages.reversed) {
      if (m.isUser) return _tableWords.hasMatch(m.text);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Its own node (container), not merged into the coach's reply above it.
    return Semantics(
      container: true,
      button: true,
      label: l.findTableSemantics,
      onTap: () => showPlanTableSheet(context),
      excludeSemantics: true,
      child: DwButton(
        key: const ValueKey('find-table'),
        label: l.findTable,
        leading: Icons.restaurant_outlined,
        style: DwButtonStyle.ghost,
        height: 44,
        fontSize: 14,
        padding: 16,
        onPressed: () => showPlanTableSheet(context),
      ),
    );
  }
}
