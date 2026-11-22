import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/batch_photo_analysis.dart';
import '../models/chat_thread.dart';
import '../models/photo_analysis.dart';
import '../models/tier.dart';
import '../models/coach.dart';
import '../models/user_profile.dart';
import '../models/weekly_plan.dart';

/// On-device persistence (PRD: all data stays on the device,
/// no cloud). On web, [SharedPreferences] is backed by window.localStorage.
class StorageService {
  StorageService(this._prefs);

  final SharedPreferences _prefs;

  static const _kTier = 'dw_tier';
  static const _kThreads = 'dw_threads';
  static const _kOnboarded = 'dw_onboarded';
  static const _kProfile = 'dw_profile';
  static const _kIntroSeen = 'dw_intro_seen';
  static const _kAnalysisCache = 'dw_analysis_cache';
  static const _kBatchCache = 'dw_batch_cache';
  static const _kCoach = 'dw_coach';
  static const _kPlan = 'dw_plan';
  static const _kMemoryOn = 'dw_memory_on';
  static const _kMemoryText = 'dw_memory_text';
  static const _kActiveDays = 'dw_active_days';
  static const _kUnderage = 'dw_underage';

  /// Cap on cached photo analyses; oldest entries are evicted past this (LRU).
  static const _maxCacheEntries = 50;

  /// Batch results carry thumbnails so they're heavier — keep fewer.
  static const _maxBatchCacheEntries = 20;

  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // --- Tier ---------------------------------------------------------------

  SubscriptionTier? loadTier() {
    final id = _prefs.getString(_kTier);
    if (id == null) return null;
    return SubscriptionTier.fromId(id);
  }

  Future<void> saveTier(SubscriptionTier tier) =>
      _prefs.setString(_kTier, tier.name);

  bool get hasOnboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded() => _prefs.setBool(_kOnboarded, true);

  /// Set when the user said they are under 18 (the app then stays closed).
  bool get underage => _prefs.getBool(_kUnderage) ?? false;
  Future<void> setUnderage() => _prefs.setBool(_kUnderage, true);

  // --- Intro slider (first-launch walkthrough) ----------------------------

  bool get hasSeenIntro => _prefs.getBool(_kIntroSeen) ?? false;
  Future<void> setIntroSeen() => _prefs.setBool(_kIntroSeen, true);

  // --- Coach --------------------------------------------------------------

  /// The coach new conversations start with, or null before the user picks
  /// one. Ids from the previous roster migrate (emily→ava, james→ethan,
  /// isabella→sofia, mateo→diego) and are re-saved under the new id.
  String? loadCoachId() {
    final raw = _prefs.getString(_kCoach);
    final id = Coaches.migrateId(raw);
    if (raw != null && id != null && id != raw) {
      _prefs.setString(_kCoach, id);
    }
    return id;
  }

  Future<void> saveCoachId(String id) => _prefs.setString(_kCoach, id);

  // --- Weekly plan --------------------------------------------------------

  WeeklyPlan? loadPlan() {
    final raw = _prefs.getString(_kPlan);
    if (raw == null || raw.isEmpty) return null;
    try {
      return WeeklyPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePlan(WeeklyPlan plan) =>
      _prefs.setString(_kPlan, jsonEncode(plan.toJson()));

  // --- Coach memory (OFF by default) --------------------------------------

  bool get memoryEnabled => _prefs.getBool(_kMemoryOn) ?? false;
  Future<void> setMemoryEnabled(bool on) => _prefs.setBool(_kMemoryOn, on);

  String get memoryText => _prefs.getString(_kMemoryText) ?? '';
  Future<void> saveMemoryText(String text) => _prefs.setString(_kMemoryText, text);

  // --- Days used (for the streak) -----------------------------------------

  Set<String> loadActiveDays() =>
      (_prefs.getStringList(_kActiveDays) ?? const <String>[]).toSet();

  Future<void> saveActiveDays(Set<String> days) {
    final sorted = days.toList()..sort();
    // Keep the last year only; the streak never needs more.
    final kept = sorted.length > 366 ? sorted.sublist(sorted.length - 366) : sorted;
    return _prefs.setStringList(_kActiveDays, kept);
  }

  // --- User profile -------------------------------------------------------

  UserProfile? loadProfile() {
    final raw = _prefs.getString(_kProfile);
    if (raw == null || raw.isEmpty) return null;
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(UserProfile profile) =>
      _prefs.setString(_kProfile, jsonEncode(profile.toJson()));

  // --- Threads ------------------------------------------------------------

  List<ChatThread> loadThreads() {
    final raw = _prefs.getString(_kThreads);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ChatThread.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveThreads(List<ChatThread> threads) {
    final raw = jsonEncode(threads.map((t) => t.toJson()).toList());
    return _prefs.setString(_kThreads, raw);
  }

  // --- Photo-analysis cache ----------------------------------------------
  //
  // Keyed by "<mode>_<sha256(image bytes)>" so re-uploading the same photo
  // (in the same mode) returns instantly without another API call. Stored as a
  // JSON list, ordered oldest→newest, so we can evict the oldest past the cap.

  /// All cached analyses as a `{ cacheKey -> PhotoAnalysis }` map for lookup.
  Map<String, PhotoAnalysis> loadAnalysisCache() {
    final raw = _prefs.getString(_kAnalysisCache);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List;
      final map = <String, PhotoAnalysis>{};
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        map[m['key'] as String] =
            PhotoAnalysis.fromJson(m['analysis'] as Map<String, dynamic>);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Upserts one analysis, moving it to newest and evicting the oldest past
  /// [_maxCacheEntries].
  Future<void> saveAnalysisCacheEntry(String key, PhotoAnalysis analysis) async {
    final raw = _prefs.getString(_kAnalysisCache);
    final list = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List) {
          final m = e as Map<String, dynamic>;
          if (m['key'] != key) list.add(m); // drop any prior copy of this key
        }
      } catch (_) {
        // Corrupt cache → start fresh.
      }
    }
    list.add({'key': key, 'analysis': analysis.toJson()});
    final trimmed = list.length > _maxCacheEntries
        ? list.sublist(list.length - _maxCacheEntries)
        : list;
    await _prefs.setString(_kAnalysisCache, jsonEncode(trimmed));
  }

  // --- Batch (rank & compare) cache --------------------------------------
  //
  // Keyed by "<mode>_batch_<combined hash>". Same list-with-LRU shape as the
  // single-photo cache, but a smaller cap because entries carry thumbnails.

  Map<String, BatchPhotoAnalysis> loadBatchCache() {
    final raw = _prefs.getString(_kBatchCache);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List;
      final map = <String, BatchPhotoAnalysis>{};
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        map[m['key'] as String] =
            BatchPhotoAnalysis.fromJson(m['analysis'] as Map<String, dynamic>);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveBatchCacheEntry(
      String key, BatchPhotoAnalysis analysis) async {
    final raw = _prefs.getString(_kBatchCache);
    final list = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List) {
          final m = e as Map<String, dynamic>;
          if (m['key'] != key) list.add(m);
        }
      } catch (_) {
        // Corrupt cache → start fresh.
      }
    }
    list.add({'key': key, 'analysis': analysis.toJson()});
    final trimmed = list.length > _maxBatchCacheEntries
        ? list.sublist(list.length - _maxBatchCacheEntries)
        : list;
    await _prefs.setString(_kBatchCache, jsonEncode(trimmed));
  }

  /// Deletes every conversation (and cached photo results), keeping settings.
  Future<void> clearConversations() async {
    await _prefs.remove(_kThreads);
    await _prefs.remove(_kAnalysisCache);
    await _prefs.remove(_kBatchCache);
  }

  /// "Delete my data": removes everything DateWise stored on this device
  /// (every `dw_` key: conversations, profile, plan, memory, stats and the
  /// legacy subscription-tier flag). The 18+ block survives, so "Delete my
  /// data" cannot be used to get around it.
  Future<void> clearAll() async {
    final blocked = underage;
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith('dw_')) await _prefs.remove(key);
    }
    if (blocked) await setUnderage();
  }
}
