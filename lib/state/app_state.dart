import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../app_flags.dart';
import '../models/batch_photo_analysis.dart';
import '../models/chat_message.dart';
import '../models/chat_thread.dart';
import '../models/photo_analysis.dart';
import '../models/tier.dart';
import '../models/user_profile.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/persona.dart';
import '../services/storage_service.dart';

/// Max photo analyses that trigger a real API call per app session (cache hits
/// don't count). Resets on restart — a cheap guard against runaway API cost.
const int kMaxPhotoAnalysesPerSession = 10;

/// Central app state: subscription tier, coaching threads, and orchestration of
/// streaming AI replies. Backed by [StorageService] for local persistence and
/// an [AIService] (real Gemini or offline mock) for coaching.
class AppState extends ChangeNotifier {
  AppState({
    required StorageService storage,
    required AIService ai,
    AuthService? auth,
  })  : _storage = storage,
        _ai = ai,
        _auth = auth ?? AuthService() {
    _load();
    _listenToAuth();
  }

  final StorageService _storage;
  final AIService _ai;
  final AuthService _auth;
  final _uuid = const Uuid();

  StreamSubscription<dynamic>? _authSub;

  // --- Accounts (optional Supabase backend) -------------------------------

  /// Whether account/sign-in features are switched on for this build.
  bool get authEnabled => _auth.isConfigured;
  bool get isSignedIn => _auth.isSignedIn;
  String? get userEmail => _auth.email;
  AuthService get auth => _auth;

  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  String? _displayName;
  String? get displayName => _displayName;

  String? _avatarUrl;
  String? get avatarUrl => _avatarUrl;

  void _listenToAuth() {
    final stream = _auth.onAuthStateChange;
    if (stream == null) return;
    _authSub = stream.listen((_) async {
      if (!_auth.isSignedIn) {
        _isAdmin = false;
        _displayName = null;
        _avatarUrl = null;
        notifyListeners();
        return;
      }
      // Load profile to learn role + suspension; sign out suspended accounts.
      final me = await _auth.loadMyProfile();
      if (me != null && me.suspended) {
        await _auth.signOut();
        _isAdmin = false;
        _displayName = null;
        _avatarUrl = null;
        notifyListeners();
        return;
      }
      _isAdmin = me?.isAdmin ?? false;
      _displayName = me?.displayName;
      _avatarUrl = me?.avatarUrl;

      // On sign-in, prefer the plan saved server-side (syncs across devices).
      final serverTier = await _auth.loadSelectedTier();
      if (serverTier != null) {
        _tier = serverTier;
        await _storage.saveTier(serverTier);
      }
      notifyListeners();
    });
  }

  /// Re-reads the current user's profile from the backend (after edits).
  Future<void> refreshProfile() async {
    final me = await _auth.loadMyProfile();
    _displayName = me?.displayName;
    _avatarUrl = me?.avatarUrl;
    _isAdmin = me?.isAdmin ?? false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  // --- Tier ---------------------------------------------------------------

  SubscriptionTier? _tier;
  SubscriptionTier? get tier => _tier;
  bool get hasTier => _tier != null;
  TierInfo get tierInfo => TierInfo.of(_tier ?? SubscriptionTier.spark);

  String get providerLabel => _ai.providerLabel;

  // --- First-launch intro slider ------------------------------------------

  /// Whether the user has already seen the one-time intro walkthrough.
  bool get hasSeenIntro => _storage.hasSeenIntro;

  /// Records that the intro slider has been completed/skipped so it won't
  /// show again on subsequent launches.
  Future<void> markIntroSeen() => _storage.setIntroSeen();

  bool can(Capability capability) =>
      AppFlags.freeLaunch || tierInfo.can(capability);

  /// Tier the AI persona/coach should speak as. During the free launch every
  /// feature is unlocked, so the coach speaks as Magnet (the full toolkit) —
  /// this also suppresses the upsell/price text the persona and mock emit for
  /// lower tiers. Read-only: the user's stored [tier] is never mutated, so the
  /// paid revert stays clean.
  SubscriptionTier get _aiTier => AppFlags.freeLaunch
      ? SubscriptionTier.magnet
      : (_tier ?? SubscriptionTier.spark);

  /// Whether the AI Photo Coach is usable. Normally Magnet-only, but the
  /// testing flag unlocks it on every tier (see [AppFlags]).
  bool get photoCoachUnlocked =>
      AppFlags.unlockPhotoCoachForTesting || can(Capability.photoCoach);

  // --- Photo analysis: mode, cache, session limit -------------------------

  AnalysisMode _analysisMode = AnalysisMode.deep;

  /// Selected depth for the next photo analysis (quick = fast/cheap, deep = full).
  AnalysisMode get analysisMode => _analysisMode;

  void setAnalysisMode(AnalysisMode mode) {
    if (_analysisMode == mode) return;
    _analysisMode = mode;
    notifyListeners();
  }

  /// SHA256-keyed cache of past analyses (loaded from storage at startup) so the
  /// same photo is never analysed twice. Keyed by `mode_hash`.
  Map<String, PhotoAnalysis> _analysisCache = {};

  /// Same idea for multi-photo (rank & compare) results. Keyed by
  /// `mode_batch_combinedHash`.
  Map<String, BatchPhotoAnalysis> _batchCache = {};

  /// Real API calls made this session; cache hits don't count toward the limit.
  int _sessionPhotoCount = 0;

  // --- User profile -------------------------------------------------------

  UserProfile? _profile;
  UserProfile? get profile => _profile;
  bool get hasProfile => _profile != null;

  /// Saves the onboarding profile and creates the first personalised thread.
  Future<void> completeOnboarding(UserProfile profile) async {
    _profile = profile;
    await _storage.saveProfile(profile);
    await ensureStarterThread();
    notifyListeners();
  }

  /// Creates the initial "Profile Setup" thread if the user has none yet.
  Future<void> ensureStarterThread() async {
    if (_threads.isEmpty) {
      await createThread(title: 'Profile Setup', greet: true);
    }
  }

  // --- Threads ------------------------------------------------------------

  final List<ChatThread> _threads = [];
  List<ChatThread> get threads => List.unmodifiable(_threads);

  String? _activeThreadId;
  String? get activeThreadId => _activeThreadId;

  ChatThread? get activeThread {
    if (_activeThreadId == null) return null;
    for (final t in _threads) {
      if (t.id == _activeThreadId) return t;
    }
    return null;
  }

  bool _isResponding = false;
  bool get isResponding => _isResponding;

  void _load() {
    _tier = _storage.loadTier();
    _profile = _storage.loadProfile();
    _analysisCache = _storage.loadAnalysisCache();
    _batchCache = _storage.loadBatchCache();
    _threads
      ..clear()
      ..addAll(_storage.loadThreads());
    _threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_threads.isNotEmpty) _activeThreadId = _threads.first.id;
    notifyListeners();
  }

  // --- Tier selection -----------------------------------------------------

  /// Records the chosen tier. The starter thread is created after onboarding
  /// (see [completeOnboarding]) so the greeting can be personalised.
  Future<void> selectTier(SubscriptionTier tier) async {
    _tier = tier;
    await _storage.saveTier(tier);
    notifyListeners();
    // Mirror the choice into the backend (no-op when unconfigured / signed out)
    // so it appears in the admin dashboard and syncs across devices.
    await _auth.saveSelectedTier(tier);
  }

  /// Signs the user out (when accounts are enabled). Local device data is kept.
  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }

  /// Requests account deletion and wipes all local device data. The auth user's
  /// final removal is completed server-side (see [AuthService.requestAccountDeletion]).
  Future<void> deleteAccount() async {
    if (authEnabled) {
      await _auth.requestAccountDeletion();
    }
    await resetAll();
    _profile = null;
    notifyListeners();
  }

  // --- Thread CRUD --------------------------------------------------------

  Future<ChatThread> createThread({String? title, bool greet = true}) async {
    final now = _now();
    final thread = ChatThread(
      id: _uuid.v4(),
      title: title ?? 'New conversation',
      createdAt: now,
      updatedAt: now,
    );
    if (greet) {
      thread.messages.add(
        ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.coach,
          text: CoachPersona.greeting(
            _aiTier,
            profile: _profile,
          ),
          createdAt: now,
        ),
      );
    }
    _threads.insert(0, thread);
    _activeThreadId = thread.id;
    await _persist();
    notifyListeners();
    return thread;
  }

  void selectThread(String id) {
    _activeThreadId = id;
    notifyListeners();
  }

  Future<void> renameThread(String id, String title) async {
    final t = _threadById(id);
    if (t == null) return;
    t.title = title.trim().isEmpty ? t.title : title.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> deleteThread(String id) async {
    _threads.removeWhere((t) => t.id == id);
    if (_activeThreadId == id) {
      _activeThreadId = _threads.isEmpty ? null : _threads.first.id;
    }
    await _persist();
    notifyListeners();
  }

  // --- Messaging ----------------------------------------------------------

  /// Sends a user message (optionally with one or more photos) and produces the
  /// coach reply: a single analysis for one photo, a rank & compare result for
  /// 2-4, or a streamed text reply when there are no photos.
  Future<void> sendMessage({String text = '', List<String>? images}) async {
    if (_isResponding) return;
    final tier = _aiTier;

    var thread = activeThread;
    thread ??= await createThread(title: 'New conversation', greet: false);

    final imgs = images ?? const <String>[];
    final now = _now();
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      text: text.trim(),
      createdAt: now,
      imageBase64: imgs.length == 1 ? imgs.first : null,
      imageBase64s: imgs.length > 1 ? imgs : null,
    );
    thread.messages.add(userMsg);
    thread.updatedAt = now;
    _autoTitle(thread);
    _bumpToTop(thread);
    notifyListeners();

    // Photo coach: produce a structured analysis card (Magnet, or any tier
    // while the testing flag is on).
    if (imgs.isNotEmpty && photoCoachUnlocked) {
      if (imgs.length == 1) {
        await _runPhotoAnalysis(thread, imgs.first, text);
      } else {
        await _runBatchPhotoAnalysis(thread, imgs, text);
      }
      return;
    }

    await _streamCoachReply(thread, tier);
  }

  Future<void> _streamCoachReply(ChatThread thread, SubscriptionTier tier) async {
    _isResponding = true;
    final coachMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.coach,
      text: '',
      createdAt: _now(),
      isStreaming: true,
    );
    thread.messages.add(coachMsg);
    notifyListeners();

    try {
      await for (final chunk in _ai.streamReply(
        history: List.of(thread.messages.where((m) => !m.isStreaming)),
        tier: tier,
        profile: _profile,
      )) {
        coachMsg.text += chunk;
        notifyListeners();
      }
    } catch (_) {
      coachMsg.text = coachMsg.text.isEmpty
          ? "Something interrupted me there — try sending that again?"
          : coachMsg.text;
    } finally {
      coachMsg.isStreaming = false;
      _isResponding = false;
      thread.updatedAt = _now();
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _runPhotoAnalysis(
    ChatThread thread,
    String imageBase64,
    String note,
  ) async {
    _isResponding = true;
    final coachMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.coach,
      text: '',
      createdAt: _now(),
      isStreaming: true,
      isAnalyzing: true,
    );
    thread.messages.add(coachMsg);
    notifyListeners();

    final mode = _analysisMode;
    final cacheKey =
        '${mode.name}_${sha256.convert(base64Decode(imageBase64))}';

    try {
      // 1) Cache hit → reuse instantly, no API call, doesn't touch the limit.
      PhotoAnalysis? analysis = _analysisCache[cacheKey];

      // 2) Cache miss → enforce the per-session cap before spending an API call.
      if (analysis == null) {
        if (_sessionPhotoCount >= kMaxPhotoAnalysesPerSession) {
          thread.messages.remove(coachMsg);
          thread.messages.add(
            ChatMessage(
              id: _uuid.v4(),
              role: MessageRole.coach,
              text:
                  "You've hit this session's photo-analysis limit "
                  '($kMaxPhotoAnalysesPerSession). Reopen the app to analyse more — '
                  'or re-check a photo you already sent (that part is free).',
              createdAt: _now(),
            ),
          );
          return;
        }

        // When testing-unlocked on a lower tier, present as Magnet so the
        // backend (which gates on tier) accepts the request.
        final effectiveTier = photoCoachUnlocked && !can(Capability.photoCoach)
            ? SubscriptionTier.magnet
            : (_tier ?? SubscriptionTier.magnet);
        analysis = await _ai.analyzePhoto(
          imageBase64: imageBase64,
          tier: effectiveTier,
          userNote: note,
          mode: mode,
        );
        _sessionPhotoCount++;
        _analysisCache[cacheKey] = analysis;
        await _storage.saveAnalysisCacheEntry(cacheKey, analysis);
      }

      final verdict = analysis.verdict.label;
      thread.messages.remove(coachMsg);
      thread.messages.add(
        ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.coach,
          text:
              '**${analysis.overallScore}/10 · $verdict** — ${analysis.headline}',
          createdAt: _now(),
          analysis: analysis,
        ),
      );
    } catch (_) {
      coachMsg.text = "I couldn't read that image — try a JPG or PNG under ~5MB?";
      coachMsg.isStreaming = false;
      coachMsg.isAnalyzing = false;
    } finally {
      _isResponding = false;
      thread.updatedAt = _now();
      await _persist();
      notifyListeners();
    }
  }

  /// Multi-photo (rank & compare) path: scores 2-4 photos and ranks them.
  Future<void> _runBatchPhotoAnalysis(
    ChatThread thread,
    List<String> images,
    String note,
  ) async {
    _isResponding = true;
    final coachMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.coach,
      text: '',
      createdAt: _now(),
      isStreaming: true,
      isAnalyzing: true,
    );
    thread.messages.add(coachMsg);
    notifyListeners();

    final mode = _analysisMode;
    // Order-independent? No — order matters for "photo #N", so hash in order.
    final combined =
        images.map((b) => sha256.convert(base64Decode(b)).toString()).join('_');
    final cacheKey = '${mode.name}_batch_${sha256.convert(utf8.encode(combined))}';

    try {
      BatchPhotoAnalysis? analysis = _batchCache[cacheKey];

      if (analysis == null) {
        if (_sessionPhotoCount >= kMaxPhotoAnalysesPerSession) {
          thread.messages.remove(coachMsg);
          thread.messages.add(
            ChatMessage(
              id: _uuid.v4(),
              role: MessageRole.coach,
              text:
                  "You've hit this session's photo-analysis limit "
                  '($kMaxPhotoAnalysesPerSession). Reopen the app to analyse more — '
                  'or re-check a set you already sent (that part is free).',
              createdAt: _now(),
            ),
          );
          return;
        }

        final effectiveTier = photoCoachUnlocked && !can(Capability.photoCoach)
            ? SubscriptionTier.magnet
            : (_tier ?? SubscriptionTier.magnet);
        analysis = await _ai.analyzePhotos(
          imageBase64s: images,
          tier: effectiveTier,
          userNote: note,
          mode: mode,
        );
        _sessionPhotoCount++;
        _batchCache[cacheKey] = analysis;
        await _storage.saveBatchCacheEntry(cacheKey, analysis);
      }

      thread.messages.remove(coachMsg);
      thread.messages.add(
        ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.coach,
          text: '**Ranked ${analysis.photos.length} photos** — '
              '${analysis.recommendation}',
          createdAt: _now(),
          batchAnalysis: analysis,
        ),
      );
    } catch (_) {
      coachMsg.text =
          "I couldn't analyse those photos — try JPG or PNG images under ~5MB each?";
      coachMsg.isStreaming = false;
      coachMsg.isAnalyzing = false;
    } finally {
      _isResponding = false;
      thread.updatedAt = _now();
      await _persist();
      notifyListeners();
    }
  }

  // --- Helpers ------------------------------------------------------------

  void _autoTitle(ChatThread thread) {
    final isDefault = thread.title == 'New conversation';
    final firstUser = thread.messages.firstWhere(
      (m) => m.isUser && m.text.trim().isNotEmpty,
      orElse: () => ChatMessage(
        id: '',
        role: MessageRole.user,
        text: '',
        createdAt: _now(),
      ),
    );
    if (isDefault && firstUser.text.trim().isNotEmpty) {
      final words = firstUser.text.trim().split(RegExp(r'\s+'));
      thread.title = words.take(5).join(' ');
      if (words.length > 5) thread.title += '…';
    }
  }

  void _bumpToTop(ChatThread thread) {
    _threads.removeWhere((t) => t.id == thread.id);
    _threads.insert(0, thread);
  }

  ChatThread? _threadById(String id) {
    for (final t in _threads) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _persist() => _storage.saveThreads(_threads);

  Future<void> resetAll() async {
    await _storage.clearAll();
    _threads.clear();
    _activeThreadId = null;
    _tier = null;
    _profile = null;
    _analysisCache = {};
    _batchCache = {};
    _sessionPhotoCount = 0;
    notifyListeners();
  }

  // Date.now() is unavailable in some sandboxes but fine in-app at runtime.
  DateTime _now() => DateTime.now();
}
