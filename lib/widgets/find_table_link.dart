import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_links.dart';
import '../l10n/l10n.dart';
import '../models/chat_message.dart';
import '../models/coach.dart';
import 'dw.dart';

/// "Find a table": the v1 booking option (owner decision, 2026-11-23). On a
/// first-date-plan conversation, a compact link under the coach's latest
/// reply opens an Apple Maps search for restaurants near the phone. No
/// accounts, no partner APIs, no in-app booking and no location permission:
/// Apple Maps uses its own location setting. Nothing from the chat is sent;
/// the link carries only the generic search term, and only on tap.
class FindTableLink extends StatelessWidget {
  const FindTableLink({super.key});

  /// Opens [uri] outside the app. Tests replace it to record the launch.
  @visibleForTesting
  static Future<bool> Function(Uri uri) launch =
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  /// Where Apple Maps exists: iPhone / iPad (and a Mac). Hidden on the web,
  /// where a map search could ask the browser for location, and on Android.
  static bool get available =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

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

  /// Restaurant or reservation words, English and Spanish, whole words only.
  static final RegExp _tableWords = RegExp(
    r"\b(reservations?|reserve|book(ing)? a table|restaurants?|dinner|table for|reservas?|reservar|restaurantes?|cena|cenar|mesa para)\b",
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

  Future<void> _open(BuildContext context) async {
    final uri = AppLinks.findTableUri(context.l10n.findTableQuery);
    final ok = await launch(uri).catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.couldNotOpen(uri.host))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Its own node (container), not merged into the coach's reply above it.
    return Semantics(
      container: true,
      link: true,
      label: l.findTableSemantics,
      onTap: () => _open(context),
      excludeSemantics: true,
      child: DwButton(
        key: const ValueKey('find-table'),
        label: l.findTable,
        leading: Icons.restaurant_outlined,
        trailing: Icons.north_east_rounded,
        style: DwButtonStyle.ghost,
        height: 44,
        fontSize: 14,
        padding: 16,
        onPressed: () => _open(context),
      ),
    );
  }
}
