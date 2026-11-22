import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/batch_photo_analysis.dart';
import '../models/chat_thread.dart';
import '../models/photo_analysis.dart';
import '../models/tier.dart';
import '../models/user_profile.dart';

/// Browser-localStorage-style persistence (PRD: all data stays on the device,
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

  // --- Intro slider (first-launch walkthrough) ----------------------------

  bool get hasSeenIntro => _prefs.getBool(_kIntroSeen) ?? false;
  Future<void> setIntroSeen() => _prefs.setBool(_kIntroSeen, true);

  // --- Coach --------------------------------------------------------------

  /// The coach new conversations start with, or null before the user picks one.
  String? loadCoachId() => _prefs.getString(_kCoach);
  Future<void> saveCoachId(String id) => _prefs.setString(_kCoach, id);

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

  Future<void> clearAll() async {
    await _prefs.remove(_kThreads);
    await _prefs.remove(_kTier);
    await _prefs.remove(_kOnboarded);
    await _prefs.remove(_kProfile);
    await _prefs.remove(_kIntroSeen);
    await _prefs.remove(_kAnalysisCache);
    await _prefs.remove(_kBatchCache);
  }
}
