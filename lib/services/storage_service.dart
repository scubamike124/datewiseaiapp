import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_thread.dart';
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
  // v1 photo-analysis caches (photos and results). v2 has no photo
  // features; these are only ever removed.
  static const _kLegacyAnalysisCache = 'dw_analysis_cache';
  static const _kLegacyBatchCache = 'dw_batch_cache';
  static const _kCoach = 'dw_coach';
  static const _kPlan = 'dw_plan';
  static const _kMemoryOn = 'dw_memory_on';
  static const _kMemoryText = 'dw_memory_text';
  static const _kActiveDays = 'dw_active_days';
  static const _kUnderage = 'dw_underage';
  static const _kAiConsent = 'dw_ai_consent';
  static const _kAiConsentVersion = 'dw_ai_consent_version';

  /// Version of the AI data-sharing consent text (`aiConsentBody`). Raise it
  /// whenever that text discloses something new, so everyone who agreed to
  /// an older text is asked again before anything more is sent.
  /// 1: the first text (stored as a plain `dw_ai_consent` flag, no version).
  /// 2: also discloses the country sent for crisis lines (re-test R3).
  static const aiConsentVersion = 2;

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

  /// Set once the user agreed to share their messages with the AI provider
  /// (App Store Guideline 5.1.2(i)). Removed by "Delete my data".
  /// Only consent to the current text ([aiConsentVersion]) counts: an older
  /// agreement (no version stored, or a lower one) asks again.
  bool get aiConsent =>
      (_prefs.getBool(_kAiConsent) ?? false) && (_prefs.getInt(_kAiConsentVersion) ?? 1) >= aiConsentVersion;
  Future<void> setAiConsent() async {
    await _prefs.setInt(_kAiConsentVersion, aiConsentVersion);
    await _prefs.setBool(_kAiConsent, true);
  }

  /// Withdraws only that permission (You › Privacy); all other data stays.
  Future<void> clearAiConsent() async {
    await _prefs.remove(_kAiConsent);
    await _prefs.remove(_kAiConsentVersion);
  }

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

  // --- Upgrade from v1 (1.0.x) ------------------------------------------

  /// Run once per launch before anything is read. Makes the stored data
  /// match what v2 discloses:
  ///  * the v1 profile fields (age, gender, city, interested in, dating goal,
  ///    dating app) are deleted from `dw_profile`; a profile with nothing
  ///    else left is removed, so the app follows the device language;
  ///  * v1 photo caches are deleted;
  ///  * a v1 user (onboarded, but without the v2 goals/language profile)
  ///    goes through the v2 onboarding once (18+ confirmation, goals,
  ///    language, coach). Conversations are kept.
  void migrateFromV1() {
    _prefs.remove(_kLegacyAnalysisCache);
    _prefs.remove(_kLegacyBatchCache);
    final raw = _prefs.getString(_kProfile);
    Map<String, dynamic>? json;
    if (raw != null && raw.isNotEmpty) {
      try {
        json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        json = null;
      }
      if (json == null) {
        _prefs.remove(_kProfile);
      } else if (json.keys.any(legacyProfileKeys.contains)) {
        json.removeWhere((k, _) => legacyProfileKeys.contains(k));
        if (json.isEmpty) {
          _prefs.remove(_kProfile);
          json = null;
        } else {
          _prefs.setString(_kProfile, jsonEncode(json));
        }
      }
    }
    final isV2 = json != null && json.containsKey('goals') && json.containsKey('language');
    if (hasOnboarded && !isV2) _prefs.setBool(_kOnboarded, false);
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
      final threads = list
          .map((e) => ChatThread.fromJson(e as Map<String, dynamic>))
          .toList();
      // v1 kept photos (and photo critiques) inside messages: re-save without
      // them so no image data stays on the device.
      if (raw.contains('"imageBase64') || raw.contains('"analysis"') || raw.contains('"batchAnalysis"')) {
        saveThreads(threads);
      }
      return threads;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveThreads(List<ChatThread> threads) {
    final raw = jsonEncode(threads.map((t) => t.toJson()).toList());
    return _prefs.setString(_kThreads, raw);
  }

  /// Deletes every conversation (and any v1 photo cache), keeping settings.
  Future<void> clearConversations() async {
    await _prefs.remove(_kThreads);
    await _prefs.remove(_kLegacyAnalysisCache);
    await _prefs.remove(_kLegacyBatchCache);
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
