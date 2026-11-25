import 'package:flutter/material.dart' show TimeOfDay;

import '../app_links.dart';
import '../l10n/l10n.dart';

/// What the user typed into "Plan a table": the only data the restaurant
/// search links carry. Nothing from the chat goes in here.
///
/// DateWise cannot see availability or book (no partner API, no accounts):
/// these criteria only build honest search links that open outside the app,
/// where the partner's own page shows live tables and the user books there.
class TablePlan {
  TablePlan({
    String area = '',
    String cuisine = '',
    this.budget = 0,
    required this.date,
    required this.time,
    this.partySize = defaultPartySize,
  }) : area = clean(area),
       cuisine = clean(cuisine),
       assert(budget >= 0 && budget <= 4),
       assert(partySize >= minPartySize && partySize <= maxPartySize);

  static const int minPartySize = 1;
  static const int maxPartySize = 20;
  static const int defaultPartySize = 2;

  /// Longest area or cuisine kept (a search term, not a message).
  static const int maxTextLength = 80;

  /// Area / neighborhood / city, trimmed (may be empty: then the map apps
  /// search near the phone with their own location setting).
  final String area;

  /// Optional cuisine, trimmed.
  final String cuisine;

  /// 0 = no budget, 1 to 4 = $ to $$$$.
  final int budget;

  /// The day (its time of day is ignored) and the time of the reservation.
  final DateTime date;
  final TimeOfDay time;

  final int partySize;

  /// One line, single spaces, at most [maxTextLength] characters.
  static String clean(String s) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= maxTextLength ? one : one.substring(0, maxTextLength).trim();
  }

  /// The default date and time for [now]: today at 19:30, or the next half
  /// hour when it is already past 19:30; tomorrow at 19:30 once no half hour
  /// is left today.
  static (DateTime, TimeOfDay) defaultsFor(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    const dinner = TimeOfDay(hour: 19, minute: 30);
    if (!now.isAfter(DateTime(now.year, now.month, now.day, dinner.hour, dinner.minute))) return (today, dinner);
    final next = ((now.hour * 60 + now.minute) ~/ 30 + 1) * 30;
    if (next >= 24 * 60) return (DateTime(now.year, now.month, now.day + 1), dinner);
    return (today, TimeOfDay(hour: next ~/ 60, minute: next % 60));
  }

  /// The local reservation date and time.
  DateTime get dateTime => DateTime(date.year, date.month, date.day, time.hour, time.minute);

  /// OpenTable's free-text search term: cuisine and area ("Italian Chicago").
  String get openTableTerm => [cuisine, area].where((s) => s.isNotEmpty).join(' ');

  /// The map search in the UI language, e.g. "moderately priced Italian
  /// restaurants in Chicago" / "restaurantes italiana de precio medio en
  /// Chicago"; just "restaurants" when nothing was typed.
  String mapsQuery(AppLocalizations l) {
    final what =
        l
            .planTableMapsWhat(budget == 0 ? '' : l.planTableBudgetQuery('$budget'), cuisine)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    return area.isEmpty ? what : l.planTableMapsWhere(what, area);
  }

  /// OpenTable search: party size, date and time, and the term.
  Uri get openTableUri => AppLinks.openTableSearchUri(covers: partySize, dateTime: dateTime, term: openTableTerm);

  /// Google Maps search URL (no API key).
  Uri googleMapsUri(AppLocalizations l) => AppLinks.googleMapsSearchUri(mapsQuery(l));

  /// Apple Maps search (iPhone, iPad, Mac).
  Uri appleMapsUri(AppLocalizations l) => AppLinks.findTableUri(mapsQuery(l));
}
