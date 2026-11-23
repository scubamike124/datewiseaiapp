import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_thread.dart';
import '../models/coach.dart';
import '../models/tier.dart';
import '../models/user_profile.dart';
import '../models/weekly_plan.dart';
import '../services/ai_service.dart';
import '../services/backend_ai_service.dart' show CoachUnavailableException;
import '../services/coach_usage.dart' show CoachLimitCode;
import '../services/persona.dart';
import '../services/storage_service.dart';
import '../services/store_service.dart';

/// Central app state: onboarding, the chosen coach, conversations (saved on
/// the device, per coach), the weekly plan, Coach memory and usage stats.
/// Backed by [StorageService]; replies come from an [AIService] (the secure
/// backend in production, the offline mock in tests); chat is gated by the
/// [StoreService] subscription.
class AppState extends ChangeNotifier {
  AppState({
    required StorageService storage,
    required AIService ai,
    StoreService? store,
    DateTime Function()? clock,
  })  : _storage = storage,
        _ai = ai,
        _store = store,
        _clock = clock ?? DateTime.now {
    _load();
  }

  final StorageService _storage;
  final AIService _ai;
  final StoreService? _store;
  final DateTime Function() _clock;
  final _uuid = const Uuid();

  /// DateWise has one premium plan; the backend protocol still names a tier,
  /// and the full-toolkit tier is the honest one to send.
  static const SubscriptionTier aiTier = SubscriptionTier.magnet;

  String get providerLabel => _ai.providerLabel;

  /// Chat needs an active subscription. Without a store (tests that do not
  /// care about billing) chat is allowed.
  bool get canChat => _store?.isEntitled ?? true;

  // --- Onboarding ---------------------------------------------------------

  bool _onboarded = false;
  bool get onboarded => _onboarded;

  /// Set when the user closes the paywall this session (not persisted, so a
  /// non-subscriber sees it again on the next launch).
  bool _paywallDismissed = false;
  bool get paywallDismissed => _paywallDismissed;
  void dismissPaywall() {
    _paywallDismissed = true;
    notifyListeners();
  }

  UserProfile? _profile;
  UserProfile? get profile => _profile;
  CoachLanguage get language => _profile?.language ?? selectedCoach.language;

  /// The language the user chose (onboarding or You › Language), or null
  /// before they choose; the app then follows the device language.
  CoachLanguage? get chosenLanguage => _profile?.language;

  // --- 18+ gate -----------------------------------------------------------

  bool _underage = false;

  /// True once the user said they are under 18. Persisted: the app stays on
  /// the "only for adults" screen, across restarts, with no way forward.
  bool get underageBlocked => _underage;

  Future<void> markUnderage() async {
    _underage = true;
    await _storage.setUnderage();
    notifyListeners();
  }

  /// Finishes onboarding: goals, language, 18+ confirmed, coach chosen.
  /// Refused (returns false, nothing saved) unless [adultConfirmed] is true
  /// and the user has not said they are under 18.
  Future<bool> completeOnboarding({
    required List<CoachingGoal> goals,
    required CoachLanguage language,
    required String coachId,
    required bool adultConfirmed,
  }) async {
    if (!adultConfirmed || _underage) return false;
    _profile = (_profile ?? const UserProfile()).copyWith(goals: goals, language: language);
    await _storage.saveProfile(_profile!);
    _plan = WeeklyPlan.fromGoals(goals, _clock());
    await _storage.savePlan(_plan!);
    await selectCoach(coachId);
    _onboarded = true;
    await _storage.setOnboarded();
    notifyListeners();
    return true;
  }

  Future<void> setLanguage(CoachLanguage lang) async {
    _profile = (_profile ?? const UserProfile()).copyWith(language: lang);
    await _storage.saveProfile(_profile!);
    notifyListeners();
  }

  // --- Coach --------------------------------------------------------------

  String? _coachId;
  Coach get selectedCoach => Coaches.byId(_coachId);
  bool get hasChosenCoach => _coachId != null;

  Future<void> selectCoach(String id) async {
    final coach = Coaches.byId(id);
    _coachId = coach.id;
    await _storage.saveCoachId(coach.id);
    final latest = latestThreadFor(coach);
    _activeThreadId = latest?.id;
    notifyListeners();
  }

  // --- Coach memory (OFF by default) --------------------------------------

  bool _memoryEnabled = false;
  bool get memoryEnabled => _memoryEnabled;
  String _memoryText = '';
  String get memoryText => _memoryText;

  /// Turning memory OFF also deletes the note from the device.
  Future<void> setMemoryEnabled(bool on) async {
    _memoryEnabled = on;
    await _storage.setMemoryEnabled(on);
    if (!on && _memoryText.isNotEmpty) await clearMemory();
    notifyListeners();
  }

  static const int memoryMaxLength = 500;

  Future<void> saveMemory(String text) async {
    final t = text.trim();
    _memoryText = t.length > memoryMaxLength ? t.substring(0, memoryMaxLength) : t;
    await _storage.saveMemoryText(_memoryText);
    notifyListeners();
  }

  Future<void> clearMemory() => saveMemory('');

  /// The profile sent with each chat request. The memory summary is included
  /// only while Coach memory is ON.
  UserProfile? get profileForCoach {
    final base = _profile;
    final memory = _memoryEnabled && _memoryText.trim().isNotEmpty ? _memoryText.trim() : null;
    if (base == null) return memory == null ? null : UserProfile(memory: memory);
    return memory == null ? base.copyWith(clearMemory: true) : base.copyWith(memory: memory);
  }

  // --- Weekly plan --------------------------------------------------------

  WeeklyPlan? _plan;
  WeeklyPlan? get plan => _plan;

  Future<void> togglePlanItem(int index) async {
    final p = _plan;
    if (p == null || index < 0 || index >= p.items.length) return;
    p.items[index].done = !p.items[index].done;
    await _storage.savePlan(p);
    notifyListeners();
  }

  // --- Usage (Progress tab) -----------------------------------------------

  Set<String> _activeDays = {};
  int get streakDays => currentStreak(_activeDays, _clock());
  int get daysUsed => _activeDays.length;

  /// Conversations in which the user has sent at least one message.
  int get conversationCount => _threads.where((t) => t.messages.any((m) => m.isUser)).length;

  Future<void> _recordActiveDay() async {
    if (_activeDays.add(dayKey(_clock()))) {
      await _storage.saveActiveDays(_activeDays);
    }
  }

  // --- Threads ------------------------------------------------------------

  final List<ChatThread> _threads = [];
  List<ChatThread> get threads => List.unmodifiable(_threads);

  List<ChatThread> threadsFor(Coach coach) =>
      _threads.where((t) => t.coachId == coach.id).toList();

  ChatThread? latestThreadFor(Coach coach) {
    for (final t in _threads) {
      if (t.coachId == coach.id) return t;
    }
    return null;
  }

  String? _activeThreadId;

  /// The open conversation, always one with the selected coach.
  ChatThread? get activeThread {
    for (final t in _threads) {
      if (t.id == _activeThreadId && t.coachId == selectedCoach.id) return t;
    }
    return null;
  }

  bool _isResponding = false;
  bool get isResponding => _isResponding;

  void _load() {
    // v1 upgraders: drop the v1 profile fields and route through the v2
    // onboarding once (see StorageService.migrateFromV1).
    _storage.migrateFromV1();
    _underage = _storage.underage;
    _onboarded = _storage.hasOnboarded && !_underage;
    _profile = _storage.loadProfile();
    _coachId = _storage.loadCoachId();
    _memoryEnabled = _storage.memoryEnabled;
    _memoryText = _storage.memoryText;
    _activeDays = _storage.loadActiveDays();
    final plan = _storage.loadPlan();
    _plan = plan?.forWeekOf(_clock());
    if (plan != null && !identical(plan, _plan)) _storage.savePlan(_plan!);
    if (_plan == null && _onboarded) {
      _plan = WeeklyPlan.fromGoals(_profile?.goals ?? const [], _clock());
    }
    _threads
      ..clear()
      ..addAll(_storage.loadThreads());
    _threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _markInterruptedReplies();
    _activeThreadId = latestThreadFor(selectedCoach)?.id;
  }

  /// A conversation saved before its reply arrived (the app closed or
  /// restarted mid-reply, before any reply was saved) ends on the user's
  /// message: it gets an interrupted reply, so it shows "Try again" instead
  /// of waiting forever. (A reply saved mid-stream already loads as
  /// interrupted.)
  void _markInterruptedReplies() {
    for (final t in _threads) {
      final last = t.messages.lastOrNull;
      if (last == null || !last.isUser) continue;
      t.messages.add(ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.coach,
        text: '',
        createdAt: last.createdAt,
        status: MessageStatus.interrupted,
      ));
    }
  }

  /// Starts a new conversation with the selected coach, opening with the
  /// coach's greeting.
  Future<ChatThread> createThread() async {
    final now = _clock();
    final coach = selectedCoach;
    final thread = ChatThread(
      id: _uuid.v4(),
      title: defaultThreadTitle(coach),
      createdAt: now,
      updatedAt: now,
      coachId: coach.id,
    );
    thread.messages.add(ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.coach,
      text: CoachPersona.greeting(aiTier, coach: coach),
      createdAt: now,
    ));
    // An untouched greeting-only conversation is replaced, not stacked.
    _threads.removeWhere((t) => t.coachId == coach.id && !t.messages.any((m) => m.isUser));
    _threads.insert(0, thread);
    _activeThreadId = thread.id;
    await _persist();
    notifyListeners();
    return thread;
  }

  void openThread(String id) {
    for (final t in _threads) {
      if (t.id == id) {
        _coachId = t.coachId;
        _storage.saveCoachId(t.coachId);
        _activeThreadId = id;
        notifyListeners();
        return;
      }
    }
  }

  /// Deletes a conversation (from the device too) and returns it, so the
  /// caller can offer Undo ([restoreThread]); null when there was none.
  Future<ChatThread?> deleteThread(String id) async {
    if (_isResponding && _activeThreadId == id) await cancelReply();
    final i = _threads.indexWhere((t) => t.id == id);
    if (i < 0) return null;
    final removed = _threads.removeAt(i);
    if (_activeThreadId == id) _activeThreadId = latestThreadFor(selectedCoach)?.id;
    await _persist();
    notifyListeners();
    return removed;
  }

  /// Undo for [deleteThread]: puts the conversation back (saved again) in
  /// its place by date; [reopen] opens it again when it was the open one.
  Future<void> restoreThread(ChatThread thread, {bool reopen = false}) async {
    if (_threads.any((t) => t.id == thread.id)) return;
    _threads
      ..add(thread)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (reopen && thread.coachId == selectedCoach.id) _activeThreadId = thread.id;
    await _persist();
    notifyListeners();
  }

  // --- Messaging ----------------------------------------------------------

  /// Sends a user message to the selected coach and streams the reply.
  /// Returns false (and sends nothing) without an active subscription or
  /// while another reply is streaming. [onAccepted] is called as soon as the
  /// message is added to the conversation (the returned future completes
  /// only when the reply has finished).
  Future<bool> sendMessage(String text, {void Function()? onAccepted}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    // A reply that is being stopped finishes stopping first.
    final stopping = _stopping;
    if (stopping != null) await stopping;
    if (_isResponding) return false;
    if (!canChat) return false;
    // Claimed before anything is awaited, so a second send cannot slip in.
    _isResponding = true;

    final thread = activeThread ?? await createThread();
    final now = _clock();
    thread.messages.add(ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      text: trimmed,
      createdAt: now,
    ));
    thread.updatedAt = now;
    _autoTitle(thread);
    _bumpToTop(thread);
    onAccepted?.call();
    await _streamCoachReply(thread);
    return true;
  }

  StreamSubscription<String>? _replySub;
  Completer<void>? _replyDone;
  ChatMessage? _replyMsg;
  Future<void>? _replyTask;
  Future<void>? _stopping;

  Future<void> _streamCoachReply(ChatThread thread) {
    final task = _runReply(thread);
    _replyTask = task;
    return task;
  }

  Future<void> _runReply(ChatThread thread) async {
    _isResponding = true;
    final coachMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.coach,
      text: '',
      createdAt: _clock(),
      isStreaming: true,
    );
    thread.messages.add(coachMsg);
    _replyMsg = coachMsg;
    notifyListeners();
    // The user's message and this placeholder are saved before the request
    // starts: if the app closes or restarts mid-reply, the conversation
    // reloads with an interrupted reply and "Try again" (a reply still
    // streaming is saved as interrupted; see ChatMessage.toJson).
    await _persist();
    await _recordActiveDay();

    final done = Completer<void>();
    _replyDone = done;
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    // Stopped while the placeholder was being saved: no request is made.
    if (coachMsg.status != MessageStatus.ok) {
      finish();
    } else {
      try {
        _replySub = _ai
            .streamReply(
              history: [for (final m in thread.messages) if (m.isComplete) m],
              tier: aiTier,
              profile: profileForCoach,
              coach: Coaches.byId(thread.coachId),
            )
            .listen(
              (chunk) {
                coachMsg.text += chunk;
                notifyListeners();
              },
              onError: (Object e) {
                coachMsg.status = MessageStatus.failed;
                coachMsg.failedStatus = e is CoachUnavailableException ? e.statusCode : null;
                coachMsg.failedCode = e is CoachUnavailableException ? e.code : null;
                coachMsg.failure = replyFailureFor(e);
                finish();
              },
              onDone: finish,
              cancelOnError: true,
            );
      } catch (_) {
        coachMsg.status = MessageStatus.failed;
        finish();
      }
    }
    await done.future;

    _replySub = null;
    _replyDone = null;
    _replyMsg = null;
    _replyTask = null;
    coachMsg.isStreaming = false;
    if (coachMsg.status == MessageStatus.ok && coachMsg.text.trim().isEmpty) {
      coachMsg.status = MessageStatus.failed;
    }
    _isResponding = false;
    thread.updatedAt = _clock();
    await _persist();
    notifyListeners();
  }

  /// Which notice a failed reply shows: busy (HTTP 429), offline (network
  /// error or timeout), server down (HTTP 5xx), else the generic one.
  static ReplyFailure? replyFailureFor(Object error) {
    if (error is! CoachUnavailableException) return null;
    final code = error.statusCode;
    if (code == 429) return ReplyFailure.busy;
    if (code != null && code >= 500) return ReplyFailure.server;
    if (error.reason.startsWith('network') || error.reason == 'timeout') return ReplyFailure.offline;
    return null;
  }

  /// Stops the reply that is streaming (Stop, or the user left the chat).
  /// The request is aborted at once (the HTTP client is closed; nothing
  /// waits for the network); the user's message is kept and the reply can
  /// be retried. Completes when the stopped reply is saved and the app is
  /// ready for the next message.
  Future<void> cancelReply() {
    final msg = _replyMsg;
    if (msg == null || msg.status != MessageStatus.ok) return _stopping ?? Future<void>.value();
    final sub = _replySub;
    _replySub = null;
    msg.status = MessageStatus.stopped;
    // Not awaited: the backend aborts synchronously, and a misbehaving
    // stream must never hold up Stop or a delete. (No subscription yet: the
    // reply is still being set up and makes no request.)
    if (sub != null) unawaited(sub.cancel().catchError((Object _) {}));
    final done = _replyDone;
    if (done != null && !done.isCompleted) done.complete();
    final task = _replyTask ?? Future<void>.value();
    final stopping = _stopping = task.whenComplete(() => _stopping = null);
    return stopping;
  }

  /// Whether the open conversation ends with a failed, stopped or
  /// interrupted reply.
  bool get canRetry {
    final last = activeThread?.messages.lastOrNull;
    return !_isResponding &&
        last != null &&
        !last.isUser &&
        last.status != MessageStatus.ok &&
        // A daily or monthly cap (or a revoked purchase, or an app too old)
        // will refuse again at once: no instant retry.
        !CoachLimitCode.noInstantRetry.contains(last.failedCode);
  }

  /// Asks the coach again for the last message after a failed, stopped or
  /// interrupted reply. That reply is replaced.
  Future<bool> retryLastReply() async {
    final stopping = _stopping;
    if (stopping != null) await stopping;
    final thread = activeThread;
    if (thread == null || !canRetry || !canChat) return false;
    thread.messages.removeLast();
    await _streamCoachReply(thread);
    return true;
  }

  // --- Deleting -----------------------------------------------------------

  Future<void> deleteAllConversations() async {
    await cancelReply();
    _threads.clear();
    _activeThreadId = null;
    await _storage.clearConversations();
    notifyListeners();
  }

  /// "Delete my data": wipes everything DateWise stored on this device
  /// (conversations, plan, progress, Coach memory, settings and any saved
  /// subscription flags) and returns the app to the welcome screen. The App
  /// Store subscription itself is managed by Apple and is not canceled;
  /// Restore Purchases brings an active one back.
  Future<void> deleteMyData() async {
    await cancelReply();
    await _storage.clearAll();
    _threads.clear();
    _activeThreadId = null;
    _profile = null;
    _coachId = null;
    _plan = null;
    _memoryEnabled = false;
    _memoryText = '';
    _activeDays = {};
    _onboarded = false;
    _paywallDismissed = false;
    notifyListeners();
  }

  // --- Helpers ------------------------------------------------------------

  static String defaultThreadTitle(Coach coach) =>
      coach.language == CoachLanguage.es ? 'Nueva conversación' : 'New conversation';

  static final Set<String> _defaultTitles = {
    for (final c in Coaches.all) defaultThreadTitle(c),
  };

  /// Whether [title] is an untouched "New conversation" title (shown in the
  /// UI language).
  static bool isDefaultTitle(String title) => _defaultTitles.contains(title);

  void _autoTitle(ChatThread thread) {
    if (!_defaultTitles.contains(thread.title)) return;
    for (final m in thread.messages) {
      if (m.isUser && m.text.trim().isNotEmpty) {
        final words = m.text.trim().split(RegExp(r'\s+'));
        thread.title = words.take(5).join(' ') + (words.length > 5 ? '…' : '');
        return;
      }
    }
  }

  void _bumpToTop(ChatThread thread) {
    _threads.removeWhere((t) => t.id == thread.id);
    _threads.insert(0, thread);
  }

  Future<void> _persist() => _storage.saveThreads(_threads);
}
