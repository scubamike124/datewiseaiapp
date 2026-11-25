import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../avatar/coach_stage_avatar.dart';
import '../avatar/lip_sync.dart';
import '../models/chat_message.dart';
import '../models/coach.dart';
import '../models/reply_options.dart';
import '../services/coach_limit_messages.dart';
import '../services/backend_ai_service.dart' show BackendAIService;
import '../services/coach_usage.dart';
import '../services/reply_language.dart';
import '../services/speech_service.dart';
import '../services/store_service.dart';
import '../services/voice_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/coach_text.dart';
import '../widgets/dw.dart';
import '../widgets/find_table_link.dart';
import '../widgets/subtitle_chunk.dart';
import 'get_help_screen.dart';
import 'paywall_screen.dart';
import 'shell.dart';
import '../l10n/l10n.dart';

/// Chat with the selected coach: real AI replies streamed from the backend,
/// saved on the device per coach. Voice mode (hold to talk, replies read
/// aloud, captions) appears only where on-device speech recognition works.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.active = true});

  /// Whether the Chat tab is on screen (voice sessions end when it is not).
  final bool active;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _focus = FocusNode();

  /// The conversation list (reversed: offset 0 is the newest message).
  final _scroll = ScrollController();

  /// How long a send or the microphone waits for the speech engine to report that it stopped. On iPhone the engine
  /// can fail to report it; an unbounded wait left the send button, the keyboard Send and the talk button dead.
  static const stopWait = Duration(milliseconds: 1500);

  /// Stops the coach's voice, waiting at most [stopWait].
  Future<void> _stopVoice() => _voice.stop().timeout(stopWait, onTimeout: () {});

  /// Brings the newest message into view (just above the composer and the keyboard).
  void _showNewest() {
    if (!_scroll.hasClients || _scroll.offset <= 0) return;
    _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  bool _voiceMode = false;
  bool _captions = true;
  bool _readAloud = true;
  bool _listening = false;
  String _partial = '';
  DateTime? _voiceStarted;
  Timer? _ticker;
  bool _wasResponding = false;

  /// True between pointer-down and pointer-up on the talk button, so a
  /// release that arrives while recognition is still starting stops it.
  bool _holding = false;

  /// True while recognition is starting (its result not back yet).
  bool _starting = false;

  /// Bumped on every start/stop so a late start result is ignored.
  int _listenGen = 0;

  /// The composer / talk dock, so snackbars float above it, not over it.
  final _dockKey = GlobalKey();

  late final AppState _state;

  /// The [AppState.dataEpoch] the composer was last checked against.
  late int _dataEpoch;
  late final AppLifecycleListener _lifecycle;
  late final VoiceService _voice;
  late final SpeechService _speech;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = context.read<AppState>();
    _voice = context.read<VoiceService>();
    _speech = context.read<SpeechService>();
    _dataEpoch = _state.dataEpoch;
    _state.addListener(_onState);
    // Opening the keyboard shows the newest message right above it.
    _focus.addListener(() {
      if (_focus.hasFocus) _showNewest();
    });
    // Back from the paywall that interrupted the chat: what the user was
    // typing or saying is in the composer again (never sent by itself).
    final draft = _state.takeDraft();
    if (draft != null) {
      _input.text = draft;
      _input.selection = TextSelection.collapsed(offset: draft.length);
    }
    // Back from Settings after denying the microphone: check again, so the
    // voice button returns once access is allowed.
    _lifecycle = AppLifecycleListener(onResume: () async {
      await _speech.recheckPermission();
      if (mounted) setState(() {});
    });
    if (widget.active) WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
    }
    if (!widget.active && old.active) {
      // Chat snackbars (Undo, Open Settings, voice notes) do not follow the
      // user to other tabs. After the frame: this runs during build.
      final messenger = ScaffoldMessenger.maybeOf(context);
      WidgetsBinding.instance.addPostFrameCallback((_) => messenger?.clearSnackBars());
      if (_voiceMode) _exitVoice();
      // Leaving the chat stops a reply that is still streaming (the HTTP
      // stream is closed); the message is kept and can be retried.
      _state.cancelReply();
    }
  }

  // The keyboard opening or closing: the Scaffold hides it from the body's
  // MediaQuery, so the voice stage is rebuilt from here.
  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // A lapsed subscription swapped the tabs for the paywall: keep what was
    // typed, plus whatever was recognized so far, for when the chat reopens.
    // Listening stops below (the microphone is released). Not after "Delete
    // my data" (no longer onboarded), which must leave nothing behind.
    if (_state.onboarded && !_state.canChat) {
      final draft = _input.text.trimRight();
      final words = _listening ? _partial.trim() : '';
      _state.keepDraft(draft.isEmpty || words.isEmpty ? '$draft$words' : '$draft $words');
    }
    _state.cancelReply();
    _state.removeListener(_onState);
    _lifecycle.dispose();
    _ticker?.cancel();
    _listenGen++;
    _voice.stop();
    _speech.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Reads a finished reply aloud during a voice session; clears the
  /// composer (a restored draft too) after "Delete all conversations" or
  /// "Delete my data".
  void _onState() {
    if (_state.dataEpoch != _dataEpoch) {
      _dataEpoch = _state.dataEpoch;
      _input.clear();
      // A transcript in progress belongs to the deleted data too: stop
      // recognition (a late result of this session is ignored) and drop
      // what was heard so far.
      final wasListening = _listening || _starting;
      _listenGen++;
      _holding = false;
      if (wasListening) _speech.cancel();
      _partial = '';
      if (_listening && mounted) setState(() => _listening = false);
    }
    final responding = _state.isResponding;
    if (_wasResponding && !responding && _voiceMode && _readAloud) {
      final last = _state.activeThread?.messages.lastOrNull;
      // Only a complete reply is read aloud, never a failed or stopped one.
      if (last != null && !last.isUser && last.status == MessageStatus.ok && last.text.trim().isNotEmpty) {
        _voice.speak(parseReply(last.text).body, _state.selectedCoach);
      }
    }
    _wasResponding = responding;
  }

  void _consumePending() {
    if (!mounted) return;
    final shell = context.read<ShellController>();
    final prompt = shell.takePrompt();
    final voice = shell.takeVoice();
    if (!_state.canChat) {
      if (prompt != null || voice) showPaywall(context);
      return;
    }
    if (voice && _speech.available) _enterVoice();
    if (prompt != null) _send(prompt);
  }

  /// Sends [text]. From the composer ([fromComposer]), the field is cleared
  /// only once the message is accepted: while a reply is still streaming
  /// nothing is sent and the text stays in the field. A voice transcript
  /// ([fromVoice]) that cannot be sent is put in the composer instead of
  /// being dropped.
  Future<void> _send(String text, {bool fromComposer = false, bool fromVoice = false}) async {
    if (text.trim().isEmpty) return;
    if (!_state.canChat) {
      // A lapsed subscription: what was said waits in the composer.
      if (fromVoice) _keepTranscript(text, note: false);
      showPaywall(context);
      return;
    }
    if (_state.isResponding) {
      if (fromVoice) _keepTranscript(text);
      return;
    }
    if (!_state.aiConsentGiven && !await _askAiConsent()) {
      // "Not now": nothing is sent; what was said waits in the composer.
      if (fromVoice) _keepTranscript(text, note: false);
      return;
    }
    // The speech engine can fail to report that it stopped (seen on iPhone): never let that block a send.
    await _stopVoice();
    // Left the chat while waiting: leaving stops a reply, so nothing is sent (the text stays in the composer).
    if (!mounted || !widget.active) return;
    final sent = await _state.sendMessage(text, onAccepted: () {
      if (fromComposer && mounted && _input.text == text) _input.clear();
      // The user's message and the reply appear at the bottom: show them even if the list was scrolled up.
      if (mounted) _showNewest();
    });
    if (!sent && fromVoice && mounted) _keepTranscript(text, note: _state.canChat);
  }

  /// "Try again": like sending, it first asks for the AI data-sharing
  /// consent when that was withdrawn (You › Privacy); "Not now" sends
  /// nothing (re-test R2).
  Future<void> _retry() async {
    if (_state.isResponding) return;
    if (!_state.aiConsentGiven && !await _askAiConsent()) return;
    await _state.retryLastReply();
  }

  /// Asks once, before anything is sent, for permission to share the user's
  /// messages with the third-party AI provider (App Store Guideline
  /// 5.1.2(i)). True (and stored) when the user agreed.
  Future<bool> _askAiConsent() async {
    final l = context.l10n;
    final ok = await showConfirmDialog(context, l.aiConsentTitle, l.aiConsentBody, l.aiConsentAgree,
        actionColor: AppColors.gold, cancelLabel: l.aiConsentNotNow);
    if (!ok || !mounted) return false;
    await _state.giveAiConsent();
    return true;
  }

  /// Puts a voice transcript that could not be sent into the composer (after
  /// any draft already there), so what the user said is never lost. [note]
  /// says so ("still replying"); not when the paywall explains instead.
  void _keepTranscript(String text, {bool note = true}) {
    if (!mounted) return;
    final words = text.trim();
    final draft = _input.text.trimRight();
    _input.text = draft.isEmpty ? words : '$draft $words';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    if (!note) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: const ValueKey('voice-kept-in-composer'),
      behavior: SnackBarBehavior.floating,
      margin: _aboveDock(),
      content: Text(context.l10n.voiceKeptInComposer),
    ));
  }

  /// How long a chat snackbar with an action stays up. It never persists:
  /// SnackBars with an action do by default, covering the composer.
  static const snackBarDuration = Duration(seconds: 5);

  /// A floating snackbar's margin that keeps it above the composer (or the
  /// talk dock) instead of over it; at most a third of the screen up.
  EdgeInsets _aboveDock() {
    final box = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    final dock = box != null && box.hasSize ? box.size.height : 0.0;
    final lift = dock.clamp(0.0, MediaQuery.sizeOf(context).height / 3);
    return EdgeInsets.fromLTRB(15, 5, 15, 10 + lift);
  }

  /// "I didn't catch that": listening ended with nothing heard.
  void _showNoSpeech() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: const ValueKey('voice-no-speech'),
      behavior: SnackBarBehavior.floating,
      margin: _aboveDock(),
      content: Text(context.l10n.voiceNoSpeech),
    ));
  }

  // --- Voice session ------------------------------------------------------

  Future<void> _enterVoice() async {
    if (!await _speech.ensureReady()) {
      if (mounted) {
        setState(() {});
        // Still "available" means permission is fine but the recognizer is
        // not (e.g. Siri & Dictation off): say so, not "permission needed".
        if (_speech.available) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.voiceRecognitionUnavailable)));
        } else {
          _showPermissionNeeded();
        }
      }
      return;
    }
    _focus.unfocus();
    setState(() {
      _voiceMode = true;
      _voiceStarted = DateTime.now();
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _exitVoice() {
    _ticker?.cancel();
    _ticker = null;
    _voice.stop();
    _listenGen++;
    _holding = false;
    if (_listening) _speech.cancel();
    setState(() {
      _voiceMode = false;
      _voiceStarted = null;
      _listening = false;
      _partial = '';
    });
  }

  /// Pointer down on the talk button (or a tap in accessibility mode). The
  /// listening state is set before anything is awaited, so a quick release
  /// is never lost: if the finger lifts while recognition is starting, it
  /// stops as soon as the start completes.
  Future<void> _startListening() async {
    if (_listening || _state.isResponding) return;
    final gen = ++_listenGen;
    _holding = true;
    setState(() {
      _listening = true;
      _partial = '';
    });
    HapticFeedback.lightImpact();
    // Starting from here: a release during the wait below finishes once recognition has started, instead of
    // stopping a recognizer that is not listening yet. The wait is only for a coach who is still speaking (so the
    // microphone does not hear the coach); otherwise recognition starts at once.
    _starting = true;
    if (_voice.speaking.value) {
      await _stopVoice();
    } else {
      unawaited(_stopVoice());
    }
    if (!mounted || gen != _listenGen) {
      _starting = false;
      return;
    }
    // The coach's language, or the other one if the user's last message was
    // in it; each with its regional fallbacks (es-MX → es-US → es-ES → es).
    final micLanguage = ReplyLanguage.forMic(_state.selectedCoach, _state.activeThread?.messages ?? const []);
    final locales = SpeechService.localesFor(micLanguage);
    final result = await _speech.start(
      localeId: locales.first,
      fallbackLocales: locales.sublist(1),
      onWords: (w) {
        if (mounted && gen == _listenGen) setState(() => _partial = w);
      },
      onUnsupported: () {
        if (mounted && gen == _listenGen) _listenFailed(SpeechStart.unsupported);
      },
      onEnded: (words) {
        if (mounted && gen == _listenGen) _listenEnded(words);
      },
    );
    _starting = false;
    if (!mounted || gen != _listenGen) {
      // The session ended (or the screen closed) while starting.
      if (result == SpeechStart.started) await _speech.cancel();
      return;
    }
    if (result != SpeechStart.started) {
      _listenFailed(result);
      return;
    }
    if (!_holding) await _finishListening(gen);
  }

  void _listenFailed(SpeechStart why) {
    _listenGen++;
    _holding = false;
    _speech.cancel();
    setState(() {
      _listening = false;
      _partial = '';
    });
    if (why == SpeechStart.denied) {
      _showPermissionNeeded();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.voiceLanguageUnsupported)));
    }
  }

  /// Recognition ended by itself (silence timeout, no match): what was
  /// heard is sent; nothing heard leaves "Listening…" with a gentle note.
  /// A permission error ends it as a denial (Open Settings).
  void _listenEnded(String words) {
    final text = words.trim().isNotEmpty ? words : _partial;
    _listenGen++;
    _holding = false;
    _speech.cancel();
    setState(() {
      _listening = false;
      _partial = '';
    });
    if (text.trim().isNotEmpty) {
      _send(text, fromVoice: true);
    } else if (_speech.permissionDenied) {
      _showPermissionNeeded();
    } else {
      _showNoSpeech();
    }
  }

  /// Microphone or speech permission denied: says so, with "Open Settings"
  /// where the system allows it.
  void _showPermissionNeeded() {
    final l = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: const ValueKey('voice-permission-snackbar'),
      persist: false,
      duration: snackBarDuration,
      behavior: SnackBarBehavior.floating,
      margin: _aboveDock(),
      content: Text(l.voicePermissionNeeded),
      action: _speech.canOpenSettings
          ? SnackBarAction(key: const ValueKey('voice-open-settings'), label: l.openSettings, onPressed: _speech.openSettings)
          : null,
    ));
  }

  /// Pointer up / cancel on the talk button.
  Future<void> _stopListening() async {
    if (!_holding) return;
    _holding = false;
    // Still starting: _startListening stops as soon as the start completes.
    if (!_starting) await _finishListening(_listenGen);
  }

  /// Accessibility (VoiceOver / TalkBack double-tap, or a switch): the talk
  /// button toggles instead of needing a hold.
  Future<void> _toggleListening() async {
    if (_listening) {
      _holding = false;
      if (!_starting) await _finishListening(_listenGen);
    } else {
      // Keeps listening (_holding stays true) until the next tap.
      await _startListening();
    }
  }

  Future<void> _finishListening(int gen) async {
    if (!_listening || gen != _listenGen) return;
    final mine = ++_listenGen;
    // A recognizer that never reports its result must not swallow what was said: after [stopWait] what was heard so
    // far is used, and recognition is canceled.
    final words = await _speech.stop().timeout(stopWait, onTimeout: () {
      _speech.cancel();
      return '';
    });
    // The session was ended meanwhile (voice closed, data deleted, a new press): nothing is sent or shown.
    if (!mounted || mine != _listenGen) return;
    final text = words.isNotEmpty ? words : _partial;
    setState(() {
      _listening = false;
      _partial = '';
    });
    if (text.trim().isNotEmpty) {
      await _send(text, fromVoice: true);
    } else {
      // Released having said nothing: the same gentle note as a timeout.
      _showNoSpeech();
    }
  }

  String get _elapsed {
    final start = _voiceStarted;
    if (start == null) return '00:00';
    final d = DateTime.now().difference(start);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // --- UI -----------------------------------------------------------------

  void _openMenu() {
    final coach = _state.selectedCoach;
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
         child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_state.canChat)
            _SheetTile(
              key: const ValueKey('menu-new'),
              icon: Icons.add_comment_outlined,
              label: l.newConversation,
              onTap: () {
                Navigator.pop(ctx);
                _state.createThread();
              },
            ),
            _SheetTile(
              key: const ValueKey('menu-history'),
              icon: Icons.history_rounded,
              label: l.pastConversationsWith(coach.name),
              onTap: () {
                Navigator.pop(ctx);
                _openHistory();
              },
            ),
            _SheetTile(
              key: const ValueKey('menu-switch'),
              icon: Icons.swap_horiz_rounded,
              label: l.switchCoach,
              onTap: () {
                Navigator.pop(ctx);
                context.read<ShellController>().go(AppTab.coaches);
              },
            ),
            _SheetTile(
              key: const ValueKey('menu-get-help'),
              icon: Icons.health_and_safety_outlined,
              label: l.getHelpNow,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(GetHelpScreen.route(firstCountry: _state.deviceCountry));
              },
            ),
            if (!_speech.available)
              Padding(
                key: const ValueKey('voice-unavailable'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.mic_off_outlined, size: 20, color: AppColors.faint),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // A denied permission is not "not available on
                          // this device": it can be allowed again in Settings.
                          Text(
                            _speech.permissionDenied ? l.voicePermissionDeniedNote(coach.name) : l.voiceUnavailableNote(coach.name),
                            key: const ValueKey('voice-unavailable-note'),
                            style: AppText.small,
                          ),
                          if (_speech.permissionDenied && _speech.canOpenSettings)
                            TextButton(
                              key: const ValueKey('menu-open-settings'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(44, 44),
                                foregroundColor: AppColors.gold,
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _speech.openSettings();
                              },
                              child: Text(l.openSettings),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
         ),
        ),
      ),
    );
  }

  void _openHistory() {
    final coach = _state.selectedCoach;
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final threads = _state.threadsFor(coach);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: threads.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.noSavedConversations, style: AppText.body),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Text(l.conversationsWith(coach.name), style: AppText.name.copyWith(fontSize: 22)),
                      ),
                      for (final t in threads)
                        ListTile(
                          minTileHeight: 56,
                          title: Text(AppState.threadTitle(t.title, l), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label),
                          // Plain text: no markdown markers or OPTIONS line,
                          // on screen or in what VoiceOver reads.
                          subtitle: Text(plainPreview(t.preview),
                              key: ValueKey('history-preview-${t.id}'),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small),
                          trailing: IconButton(
                            key: ValueKey('history-delete-${t.id}'),
                            tooltip: l.deleteConversation,
                            // 48x48 on every platform (desktop/web density
                            // would shrink it to 40x40).
                            visualDensity: VisualDensity.standard,
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.faint),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _deleteWithUndo(t.id);
                            },
                          ),
                          onTap: () {
                            _state.openThread(t.id);
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  /// Deletes a conversation from Past conversations at once, with Undo in a
  /// SnackBar (Undo saves it back).
  Future<void> _deleteWithUndo(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final wasOpen = _state.activeThread?.id == id;
    final margin = _aboveDock();
    final removed = await _state.deleteThread(id);
    if (removed == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('conversation-deleted'),
        // Closes by itself and floats above the composer; Undo is refused
        // after "Delete all conversations" or "Delete my data".
        persist: false,
        duration: snackBarDuration,
        behavior: SnackBarBehavior.floating,
        margin: margin,
        // Whole words at large text ("Conversación eliminada." never breaks
        // inside a word).
        content: WholeWordsText(l.conversationDeleted, key: const ValueKey('conversation-deleted-text')),
        action: SnackBarAction(
          key: const ValueKey('undo-delete'),
          label: l.undo,
          onPressed: () => _state.restoreThread(removed, reopen: wasOpen),
        ),
      ));
  }

  /// The on-screen keyboard is up. The Scaffold hides its inset from the body's
  /// MediaQuery, so this asks the view itself.
  static bool _keyboardOpen(BuildContext context) => MediaQueryData.fromView(View.of(context)).viewInsets.bottom > 0;

  /// Whether the avatar is hidden in the voice conversation: the user's saved
  /// choice, else by screen. A small phone (iPhone SE, 12 mini), a short
  /// (landscape) screen and large text start with the avatar hidden, so the
  /// conversation always has room; tall screens start with it shown.
  static bool avatarCollapsed(BuildContext context, bool? saved) {
    if (saved != null) return saved;
    final size = MediaQuery.sizeOf(context);
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return large || size.width <= kSmallPhoneWidth || size.height < kTallScreenHeight;
  }

  /// Widest phone treated as small (iPhone SE and 12 mini are 375 pt).
  static const double kSmallPhoneWidth = 380;

  /// Screens shorter than this start with the avatar hidden.
  static const double kTallScreenHeight = 800;

  /// Tallest the voice stage may be: with the keyboard up the controls row
  /// and a peek of the subtitle; otherwise half the screen (it scrolls
  /// beyond that, so the talk dock is never pushed off screen).
  double _stageCap(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (_keyboardOpen(context)) {
      final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
      return large ? _Stage.controlsHeight + _Stage.bottomMargin : math.max(size.height * 0.18, _Stage.controlsHeight + _Stage.bottomMargin + 8);
    }
    return size.height * 0.5;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Rebuild when the subscription changes; AppState.canChat reads it.
    context.watch<StoreService>();
    final coach = state.selectedCoach;
    final entitled = state.canChat;
    // A lapsed subscription locks the composer, but the user's own saved
    // conversations stay readable, and the menu (Past conversations, delete
    // one) stays usable (QA M-1).
    final readOnly = !entitled && state.threadsFor(coach).any((t) => t.messages.any((m) => m.isUser));
    final top = MediaQuery.paddingOf(context).top;
    final avatarHidden = avatarCollapsed(context, state.voiceAvatarCollapsed);

    return ValueListenableBuilder<bool>(
      valueListenable: _voice.speaking,
      builder: (context, speaking, _) {
        return Column(
          children: [
            // Opaque espresso header with a hairline: the thread scrolls
            // cleanly beneath it instead of showing through.
            DecoratedBox(
              key: const ValueKey('chat-header'),
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Column(
                children: [
                  SizedBox(height: top),
                  ContentWidth(
                    child: _Header(
                      coach: coach,
                      speaking: speaking,
                      onMenu: entitled || readOnly ? _openMenu : null,
                    ),
                  ),
                ],
              ),
            ),
            if (_voiceMode)
              // At large text the stage is capped and scrolls, instead of
              // pushing the talk dock off screen; normal text is unchanged.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _stageCap(context)),
                child: SingleChildScrollView(
                  key: const ValueKey('voice-stage-scroll'),
                  child: ContentWidth(
                    child: _Stage(
                      coach: coach,
                      speaking: speaking,
                      mood: CoachStageAvatar.moodFor(
                          speaking: speaking, listening: _listening, responding: state.isResponding),
                      lipSync: _voice is LipSyncSource ? (_voice as LipSyncSource).lipSync : null,
                      elapsed: _elapsed,
                      captions: _captions,
                      replyText: _latestReplyText(state),
                      responding: state.isResponding,
                      onToggleCaptions: () => setState(() => _captions = !_captions),
                      avatarHidden: avatarHidden,
                      onToggleAvatar: () => state.setVoiceAvatarCollapsed(!avatarHidden),
                      compact: _keyboardOpen(context),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: entitled || readOnly
                  ? _MessageList(
                      controller: _scroll,
                      coach: coach,
                      compact: _voiceMode,
                      onStarter: _send,
                      onRetry: _retry,
                      showIntro: !_voiceMode,
                      speaking: speaking,
                      readOnly: !entitled,
                    )
                  : _Locked(coach: coach),
            ),
            if (readOnly) ContentWidth(child: _LockedBar(coach: coach)),
            // With the keyboard up at large text the room is needed for the
            // conversation and the controls; the notice returns with it closed.
            if (entitled &&
                MediaQuery.sizeOf(context).height >= 500 &&
                !(_keyboardOpen(context) && MediaQuery.textScalerOf(context).scale(1) > 1.3))
              const ContentWidth(child: _UsageNotice()),
            if (entitled)
              ContentWidth(
                key: _dockKey,
                child: _voiceMode
                    ? _VoiceDock(
                        coach: coach,
                        listening: _listening,
                        partial: _partial,
                        busy: state.isResponding,
                        readAloud: _readAloud,
                        onHoldStart: _startListening,
                        onHoldEnd: _stopListening,
                        onToggle: _toggleListening,
                        onKeyboard: _exitVoice,
                        onToggleReadAloud: () {
                          setState(() => _readAloud = !_readAloud);
                          if (!_readAloud) _voice.stop();
                        },
                      )
                    : _Composer(
                        controller: _input,
                        focus: _focus,
                        hint: context.l10n.messageHint(coach.name),
                        busy: state.isResponding,
                        onSend: () => _send(_input.text, fromComposer: true),
                        onStop: _state.cancelReply,
                        onVoice: _speech.available ? _enterVoice : null,
                      ),
              ),
          ],
        );
      },
    );
  }

  /// The text of the coach's latest reply (or the greeting): the source of
  /// the live subtitle. The reply itself is shown in the message list only.
  String _latestReplyText(AppState state) {
    final msgs = state.activeThread?.messages ?? const <ChatMessage>[];
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (!msgs[i].isUser) return parseReply(msgs[i].text).body.replaceAll('**', '');
    }
    return state.selectedCoach.greeting.replaceAll('**', '');
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        minTileHeight: 52,
        leading: Icon(icon, color: AppColors.gold),
        title: Text(label, style: AppText.label),
        onTap: onTap,
      );
}

/// Largest text scale for the chat header's "AI dating coach · English" line.
const double kHeaderSubtitleMaxScale = 1.4;

class _Header extends StatelessWidget {
  const _Header({required this.coach, required this.speaking, required this.onMenu});
  final Coach coach;
  final bool speaking;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          CoachAvatar(coach: coach, size: 40, speaking: speaking, semanticLabel: l.coachPortrait(coach.name)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(coach.name,
                      style: const TextStyle(fontFamily: AppFonts.serif, fontSize: 21, fontWeight: FontWeight.w500, color: AppColors.text, height: 1.15)),
                ),
                // One line at any text size: the size is capped for this
                // subtitle only, and an ellipsis catches what is left (VoiceOver
                // still reads it in full). "AI" comes first, so it always shows.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: kHeaderSubtitleMaxScale,
                  child: Text(l.aiLabelShort,
                      key: const ValueKey('ai-label'),
                      semanticsLabel: l.aiLabel(coach),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
              ],
            ),
          ),
          if (onMenu != null)
            CircleIconButton(
              key: const ValueKey('chat-menu'),
              icon: Icons.more_horiz_rounded,
              tooltip: l.conversationOptions,
              onPressed: onMenu,
            ),
        ],
      ),
    );
  }
}

/// Voice-mode stage: the coach as an animated portrait (lib/avatar/:
/// on-device frame compositing with lip-sync to the device's speech; the
/// still portrait under Reduce Motion), a soft glow while speaking, the
/// session timer and a short live subtitle. Not video. The avatar can be
/// hidden ([avatarHidden]): the stage is then only the controls row and the
/// subtitle, and the coach stays as the circle in the header.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.coach,
    required this.speaking,
    required this.mood,
    required this.lipSync,
    required this.elapsed,
    required this.captions,
    required this.replyText,
    required this.responding,
    required this.onToggleCaptions,
    required this.avatarHidden,
    required this.onToggleAvatar,
    this.compact = false,
  });

  /// With the keyboard open the portrait is dropped (the controls row and
  /// subtitle stay), so the talk dock stays above the keyboard.
  final bool compact;
  static const double bottomMargin = 8;
  static const double controlsHeight = 44;

  final Coach coach;
  final bool speaking;
  final AvatarMood mood;
  final LipSyncDriver? lipSync;
  final String elapsed;
  final bool captions;

  /// The coach's latest reply: the subtitle shows one sentence of it.
  final String replyText;
  final bool responding;
  final VoidCallback onToggleCaptions;
  final bool avatarHidden;
  final VoidCallback onToggleAvatar;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final showPortrait = !compact && !avatarHidden;
    final controls = SizedBox(
      height: controlsHeight,
      child: Row(
        key: const ValueKey('voice-stage-controls'),
        children: [
          Expanded(
            // One line, scaled down to fit, so the row is always as tall as
            // the buttons at any text size.
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: GlassChip(key: const ValueKey('voice-timer'), label: l.voiceSession(elapsed)),
              ),
            ),
          ),
          CircleIconButton(
            key: const ValueKey('toggle-captions'),
            icon: captions ? Icons.closed_caption_rounded : Icons.closed_caption_off_outlined,
            tooltip: captions ? l.hideCaptions : l.showCaptions,
            onPressed: onToggleCaptions,
            filled: true,
            size: controlsHeight,
          ),
          const SizedBox(width: 4),
          CircleIconButton(
            key: const ValueKey('toggle-avatar'),
            icon: avatarHidden ? Icons.face_rounded : Icons.expand_less_rounded,
            tooltip: avatarHidden ? l.showAvatar : l.hideAvatar,
            onPressed: onToggleAvatar,
            filled: true,
            size: controlsHeight,
          ),
        ],
      ),
    );
    // A short (landscape) screen keeps its room for the conversation: no subtitle.
    final short = MediaQuery.sizeOf(context).height < 500;
    final subtitle = captions && !short
        ? Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _Subtitle(
              key: const ValueKey('voice-subtitle'),
              speaking: speaking,
              responding: responding,
              lipSync: lipSync,
              replyText: replyText,
            ),
          )
        : const SizedBox.shrink();
    return AnimatedContainer(
      // The speaking glow fades in, unless Reduce Motion is on.
      duration: motion(context, const Duration(milliseconds: 400)),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, bottomMargin),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: speaking ? const Color(0x99DDB67F) : AppColors.line),
        boxShadow: speaking ? const [BoxShadow(color: Color(0x40DDB67F), blurRadius: 28, spreadRadius: 1)] : const [],
      ),
      clipBehavior: Clip.antiAlias,
      child: showPortrait
          // The avatar window on the left (the whole face, from the hair to
          // the chin; nothing is drawn over it), the timer, buttons and the
          // live subtitle beside it.
          ? LayoutBuilder(builder: (context, box) {
              final win = CoachStageAvatar.windowSize(box.maxWidth, screenHeight: MediaQuery.sizeOf(context).height);
              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      key: const ValueKey('avatar-window'),
                      width: win.width,
                      height: win.height,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.line2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CoachStageAvatar(coach: coach, mood: mood, lipSync: lipSync),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          controls,
                          Padding(padding: const EdgeInsets.only(right: 8), child: subtitle),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            })
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(12, 0, 6, 0), child: controls),
                if (captions && !short) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 10), child: subtitle),
              ],
            ),
    );
  }
}

/// The live subtitle: the sentence being spoken, at most three lines, never
/// the whole reply (that is in the message list). It follows the speech
/// through the lip-sync timeline's word that is being said; before and
/// between speech it shows the first sentence of the latest reply, and
/// nothing while the coach is still writing. Its text size stops growing at
/// 1.3x so it stays short.
class _Subtitle extends StatefulWidget {
  const _Subtitle({super.key, required this.speaking, required this.responding, required this.lipSync, required this.replyText});
  final bool speaking;
  final bool responding;
  final LipSyncDriver? lipSync;
  final String replyText;

  static const double fontSize = 13.5;
  static const double lineHeight = 1.35;
  static const double maxTextScale = 1.3;
  static const int maxLines = 3;

  @override
  State<_Subtitle> createState() => _SubtitleState();
}

class _SubtitleState extends State<_Subtitle> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Subtitle old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Polls the speech position, only while something is being spoken.
  void _sync() {
    if (widget.speaking && _poll == null) {
      _poll = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
    } else if (!widget.speaking) {
      _poll?.cancel();
      _poll = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  String _text(int maxChars) {
    if (widget.responding) return '';
    final d = widget.lipSync;
    final tl = d?.timeline;
    if (widget.speaking && d != null && tl != null && d.active) {
      final t = d.planTime();
      if (t != null && tl.words.isNotEmpty) {
        var k = 0;
        for (var i = 0; i < tl.words.length; i++) {
          if (tl.words[i].start <= t) k = i;
        }
        return subtitleAt(tl.text, tl.words[k].charStart, maxChars: maxChars);
      }
    }
    return firstSubtitle(widget.replyText, maxChars: maxChars);
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _Subtitle.maxTextScale);
    final size = scaler.scale(_Subtitle.fontSize);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _Subtitle.maxTextScale,
      child: LayoutBuilder(builder: (context, box) {
        // About how many characters three lines hold here, so a chunk fits.
        final perLine = box.maxWidth / (size * 0.5);
        final maxChars = (perLine * _Subtitle.maxLines * 0.85).floor().clamp(24, 120);
        return ConstrainedBox(
          // Reserves two lines, so the stage does not jump between sentences.
          constraints: BoxConstraints(minHeight: size * _Subtitle.lineHeight * 2),
          child: Text(_text(maxChars),
              key: const ValueKey('voice-caption'),
              textAlign: TextAlign.start,
              maxLines: _Subtitle.maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: _Subtitle.fontSize, height: _Subtitle.lineHeight, color: AppColors.text)),
        );
      }),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.controller,
    required this.coach,
    required this.compact,
    required this.onStarter,
    required this.onRetry,
    required this.showIntro,
    required this.speaking,
    this.readOnly = false,
  });

  final ScrollController controller;
  final Coach coach;
  final bool compact;
  final ValueChanged<String> onStarter;

  /// "Try again" under a failed, stopped or interrupted reply.
  final VoidCallback onRetry;
  final bool showIntro;
  final bool speaking;

  /// Saved conversations shown without a subscription: no starters and no
  /// "Try again" (nothing can be sent).
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final thread = state.activeThread;
    final messages = thread?.messages ??
        [ChatMessage(id: 'greeting', role: MessageRole.coach, text: coach.greeting, createdAt: DateTime(2026))];
    final hasUser = messages.any((m) => m.isUser);
    // First-date plans: "Find a table" under the coach's latest reply.
    final datePlan = FindTableLink.available && FindTableLink.wantsTable(messages);

    final items = <Widget>[
      if (showIntro) _IntroCard(coach: coach),
      for (var i = 0; i < messages.length; i++)
        _Bubble(
          key: ValueKey('msg-${messages[i].id}'),
          message: messages[i],
          coach: coach,
          showOptions: i == messages.length - 1,
          showFindTable: datePlan && i == messages.length - 1,
          onRetry: !readOnly && i == messages.length - 1 && state.canRetry ? onRetry : null,
        ),
      if (!hasUser && !readOnly) _Starters(coach: coach, onTap: onStarter),
    ];

    // Newest at the bottom (reversed list), but a short conversation starts
    // right under the header instead of leaving a gap above it.
    return ContentWidth(
      child: Align(
        alignment: Alignment.topCenter,
        // Long-press selects and copies any part of a reply (SelectionArea),
        // and the list scrolls, so a long reply is never cut off.
        child: SelectionArea(
          child: ListView.builder(
            key: ValueKey('messages-${coach.id}'),
            controller: controller,
            reverse: true,
            shrinkWrap: true,
            // Dragging the conversation lowers the keyboard, so a reply is never stuck behind it.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            itemCount: items.length,
            itemBuilder: (_, i) => items[items.length - 1 - i],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.coach});
  final Coach coach;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 4),
      constraints: BoxConstraints(minHeight: large ? 240 : 190),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: CoachImage(coach: coach, semanticLabel: l.coachPortrait(coach.name))),
          const Positioned.fill(child: FadeToBackground(stops: [0.35, 1], color: Color(0xF2150C10))),
          Padding(
            padding: EdgeInsets.fromLTRB(16, large ? 90 : 110, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassChip(label: l.chip(coach)),
                const SizedBox(height: 8),
                Text(l.coachDescription(coach),
                    style: const TextStyle(fontSize: 14, height: 1.35, color: AppColors.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.coach,
    required this.showOptions,
    this.showFindTable = false,
    this.onRetry,
  });
  final ChatMessage message;
  final Coach coach;
  final bool showOptions;
  final bool showFindTable;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width.clamp(0, kContentMaxWidth) * 0.8;
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxW.toDouble()),
          margin: const EdgeInsets.only(bottom: 10, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: AppColors.userBubble,
            border: Border.all(color: const Color(0x59DDB67F)),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: message.isPhotoOnly
              ? Text(context.l10n.photoNoLongerAvailable,
                  key: const ValueKey('photo-placeholder'),
                  style: const TextStyle(fontSize: 14, height: 1.45, fontStyle: FontStyle.italic, color: Color(0xCCF6E6D2)))
              : Text(message.text, style: const TextStyle(fontSize: 15, height: 1.45, color: Color(0xFFF6E6D2))),
        ),
      );
    }
    final l = context.l10n;
    final parsed = parseReply(message.text);
    final waiting = message.isStreaming && parsed.body.isEmpty;
    final failed = message.status != MessageStatus.ok;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CoachAvatar(coach: coach, size: 30),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(maxWidth: maxW.toDouble()),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    border: Border.all(color: AppColors.line),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(18),
                    ),
                  ),
                  child: waiting
                      ? Semantics(
                          label: l.coachTyping(coach.name),
                          child: const Text('•••', style: TextStyle(color: AppColors.faint, letterSpacing: 2)),
                        )
                      : failed
                          ? _FailedReply(
                              partial: parsed.body,
                              status: message.status,
                              failure: message.failure,
                              code: message.failedCode,
                              onRetry: onRetry,
                              showPaywallAction: showOptions,
                            )
                          : message.isPhotoOnly
                              ? Text(l.photoNoLongerAvailable,
                                  key: const ValueKey('photo-placeholder'),
                                  style: const TextStyle(fontSize: 14, height: 1.45, fontStyle: FontStyle.italic, color: AppColors.textMuted))
                              : CoachText(parsed.body),
                ),
              ),
            ],
          ),
          if (showOptions && !message.isStreaming && !failed && parsed.options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 8),
              child: _ReplyOptions(options: parsed.options),
            ),
          if (showFindTable && !message.isStreaming && !failed && !message.isPhotoOnly && parsed.body.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 38, top: 8),
              child: FindTableLink(),
            ),
        ],
      ),
    );
  }
}

/// Reply suggestions, shown only when the coach's reply provided them.
/// Tapping one copies it, ready to paste into the dating app.
class _ReplyOptions extends StatelessWidget {
  const _ReplyOptions({required this.options});
  final List<ReplyOption> options;

  /// Copies [text] and says "Copied" only when the copy worked (QA m-1); a
  /// failure says so instead. The snackbar floats above the composer, like
  /// the other chat snackbars.
  static Future<void> _copy(BuildContext context, String text) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final margin = context.findAncestorStateOfType<_ChatScreenState>()?._aboveDock() ??
        const EdgeInsets.fromLTRB(15, 5, 15, 10);
    var ok = true;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      ok = false;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: ValueKey(ok ? 'copy-ok' : 'copy-failed'),
        behavior: SnackBarBehavior.floating,
        margin: margin,
        content: WholeWordsText(ok ? l.copiedReply : l.copyFailed),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          Semantics(
            button: true,
            label: context.l10n.copyReply(o.label, o.text),
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('option-${o.label}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => _copy(context, o.text),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44, maxWidth: 240),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xB3DDB67F)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (o.label.isNotEmpty)
                      Text(o.label.toUpperCase(), style: AppText.eyebrow.copyWith(fontSize: 10.5, letterSpacing: 1.2)),
                    const SizedBox(height: 2),
                    Text('“${o.text}”', style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Starters extends StatelessWidget {
  const _Starters({required this.coach, required this.onTap});
  final Coach coach;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 38, top: 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // Stadium buttons whose label wraps (an ActionChip label is one
          // line and cuts words off at large text). Wrap gives each one the
          // full row width at most, so a long starter fills it and wraps.
          for (final s in coach.starters)
            OutlinedButton(
              key: ValueKey('starter-$s'),
              onPressed: () => onTap(s),
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0x0DFFFFFF),
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.line2),
                shape: const StadiumBorder(),
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                tapTargetSize: MaterialTapTargetSize.padded,
                alignment: AlignmentDirectional.centerStart,
              ),
              child: Text(
                s,
                softWrap: true,
                style: const TextStyle(fontSize: 13.5, height: 1.3, color: AppColors.text, fontWeight: FontWeight.w400),
              ),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.hint,
    required this.busy,
    required this.onSend,
    required this.onStop,
    required this.onVoice,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback? onVoice;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.line2),
              ),
              child: TextField(
                key: const ValueKey('composer'),
                controller: controller,
                focusNode: focus,
                minLines: 1,
                // Three lines at large text, so the conversation keeps room above the keyboard.
                maxLines: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 3 : 5,
                // The Worker reads at most this much per message (code review m3); the
                // counter appears only near the limit.
                maxLength: BackendAIService.maxMessageChars,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                    maxLength != null && currentLength > maxLength - 500
                        ? Text('$currentLength/$maxLength',
                            key: const ValueKey('composer-counter'), style: AppText.small)
                        : null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                // While a reply streams, Enter does nothing: the text and the
                // keyboard stay, ready to send once the reply is done.
                onSubmitted: (_) {
                  if (!busy) onSend();
                },
                onEditingComplete: busy ? () {} : null,
                style: const TextStyle(fontSize: 15.5, color: AppColors.text, height: 1.35),
                decoration: InputDecoration(
                  hintText: hint,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
          if (onVoice != null) ...[
            const SizedBox(width: 8),
            CircleIconButton(
              key: const ValueKey('voice-mode'),
              icon: Icons.mic_none_rounded,
              tooltip: l.voiceMode,
              size: 48,
              onPressed: onVoice,
            ),
          ],
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: busy ? l.stopReply : l.send,
            excludeSemantics: true,
            child: Material(
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: const BoxDecoration(gradient: AppColors.goldGradient, shape: BoxShape.circle),
                child: InkWell(
                  key: ValueKey(busy ? 'stop' : 'send'),
                  onTap: busy ? onStop : onSend,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: busy
                        ? const Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldInk),
                              ),
                              Icon(Icons.stop_rounded, size: 14, color: AppColors.goldInk),
                            ],
                          )
                        : const Icon(Icons.arrow_upward_rounded, color: AppColors.goldInk),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceDock extends StatelessWidget {
  const _VoiceDock({
    required this.coach,
    required this.listening,
    required this.partial,
    required this.busy,
    required this.readAloud,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onToggle,
    required this.onKeyboard,
    required this.onToggleReadAloud,
  });

  final Coach coach;
  final bool listening;
  final String partial;
  final bool busy;
  final bool readAloud;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onToggle;
  final VoidCallback onKeyboard;
  final VoidCallback onToggleReadAloud;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // With VoiceOver/TalkBack on, a hold is impractical: tap to start, tap
    // again to send.
    final toggleMode = MediaQuery.accessibleNavigationOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (listening)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(partial.isEmpty ? l.listening : partial,
                  textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Color(0xFFF6E6D2))),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleIconButton(icon: Icons.keyboard_alt_outlined, tooltip: l.typeInstead, onPressed: onKeyboard),
              const SizedBox(width: 28),
              Semantics(
                button: true,
                label: listening ? l.tapToSend : l.holdToTalk,
                hint: listening ? null : l.tapToTalkHint,
                enabled: !busy,
                onTap: busy && !listening ? null : onToggle,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: toggleMode && !(busy && !listening) ? onToggle : null,
                  child: Listener(
                  onPointerDown: busy || toggleMode ? null : (_) => onHoldStart(),
                  onPointerUp: toggleMode ? null : (_) => onHoldEnd(),
                  onPointerCancel: toggleMode ? null : (_) => onHoldEnd(),
                  child: AnimatedContainer(
                    key: const ValueKey('hold-to-talk'),
                    duration: motion(context, const Duration(milliseconds: 200)),
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(0, -0.3),
                        colors: [Color(0xFFF0D3A3), AppColors.gold, AppColors.gold2],
                        stops: [0, 0.55, 1],
                      ),
                      boxShadow: [
                        BoxShadow(color: const Color(0x1FDDB67F), spreadRadius: listening ? 14 : 8),
                        BoxShadow(color: const Color(0x0DDDB67F), spreadRadius: listening ? 26 : 18),
                      ],
                    ),
                    child: Icon(listening ? Icons.graphic_eq_rounded : Icons.mic_rounded, size: 30,
                        color: busy ? AppColors.goldInk.withValues(alpha: 0.4) : AppColors.goldInk),
                  ),
                  ),
                ),
              ),
              const SizedBox(width: 28),
              CircleIconButton(
                icon: readAloud ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                tooltip: readAloud ? l.stopReadingAloud : l.readAloud,
                onPressed: onToggleReadAloud,
              ),
            ],
          ),
          // The hint is dropped on a short (landscape) screen, which needs the
          // room for the conversation.
          if (MediaQuery.sizeOf(context).height >= 500) ...[
          const SizedBox(height: 12),
          // With VoiceOver/TalkBack the talk button toggles with a tap.
          Text(
            MediaQuery.accessibleNavigationOf(context)
                ? l.tapToTalkFooter(coach.name, l.gender(coach))
                : l.holdToTalkFooter(coach.name, l.gender(coach)),
            key: const ValueKey('talk-footer'),
            textAlign: TextAlign.center,
            style: AppText.small,
          ),
          ],
        ],
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked({required this.coach});
  final Coach coach;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _IntroCard(coach: coach),
            DwCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.premiumEyebrow.toUpperCase(), style: AppText.eyebrow),
                  const SizedBox(height: 8),
                  Text(l.lockedTitle(coach.name), style: AppText.name.copyWith(fontSize: 24)),
                  const SizedBox(height: 8),
                  Text(l.lockedBody, style: AppText.body),
                  const SizedBox(height: 16),
                  DwButton(
                    key: const ValueKey('locked-subscribe'),
                    label: l.seePremium,
                    expand: true,
                    onPressed: () => showPaywall(context),
                  ),
                ],
              ),
            ),
            // A read-only preview of how the coach talks, below the premium
            // card so See Premium stays where it was: the built-in greeting,
            // rendered locally. No composer, no send, no AI call.
            const SizedBox(height: 20),
            Text(l.lockedPreviewLabel(coach.name).toUpperCase(),
                key: const ValueKey('locked-preview-label'), style: AppText.eyebrow),
            const SizedBox(height: 10),
            KeyedSubtree(
              key: const ValueKey('locked-preview-greeting'),
              child: _Bubble(
                message: ChatMessage(
                    id: 'preview-greeting', role: MessageRole.coach, text: coach.greeting, createdAt: DateTime(2026)),
                coach: coach,
                showOptions: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The premium card above the locked composer while saved conversations are
/// shown read-only (QA M-1).
class _LockedBar extends StatelessWidget {
  const _LockedBar({required this.coach});
  final Coach coach;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      key: const ValueKey('locked-bar'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: DwCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.premiumEyebrow.toUpperCase(), style: AppText.eyebrow),
            const SizedBox(height: 6),
            WholeWordsText(l.lockedHistoryNote(coach.name), key: const ValueKey('locked-history-note'), style: AppText.body),
            const SizedBox(height: 10),
            DwButton(
              key: const ValueKey('locked-subscribe'),
              label: l.seePremium,
              expand: true,
              onPressed: () => showPaywall(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// A reply that could not be delivered: the friendly notice (localized), any
/// text that arrived before the failure, "Try again", and for a subscription
/// refusal (see [CoachLimitCode.paywallAction]) a button that opens the
/// paywall with Subscribe and Restore purchases.
class _FailedReply extends StatelessWidget {
  const _FailedReply(
      {required this.partial,
      required this.status,
      required this.onRetry,
      this.failure,
      this.code,
      this.showPaywallAction = false});
  final String partial;

  /// Failed, stopped (by the user) or interrupted (the app restarted).
  final MessageStatus status;
  final ReplyFailure? failure;

  /// The backend's refusal code (chat-v7); a known one shows its limit notice.
  final String? code;
  final VoidCallback? onRetry;

  /// Only on the newest reply, like "Try again".
  final bool showPaywallAction;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final paywall = showPaywallAction && status == MessageStatus.failed && CoachLimitCode.paywallAction.contains(code);
    return Column(
      key: const ValueKey('reply-failed'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (partial.trim().isNotEmpty) ...[
          CoachText(partial),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.error_outline_rounded, size: 18, color: AppColors.rose),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                switch (status) {
                  MessageStatus.stopped => l.chatErrorStopped,
                  MessageStatus.interrupted => l.chatErrorInterrupted,
                  _ => coachLimitMessage(l, code) ??
                      switch (failure) {
                        ReplyFailure.busy => l.chatErrorBusy,
                        ReplyFailure.offline => l.chatErrorOffline,
                        ReplyFailure.server => l.chatErrorServer,
                        null => l.chatErrorUnavailable,
                      },
                },
                key: const ValueKey('reply-failed-notice'),
                style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.text),
              ),
            ),
          ],
        ),
        if (onRetry != null || paywall) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (paywall)
                DwButton(
                  key: const ValueKey('reply-paywall'),
                  // "Restore purchases" where the notice says to tap it;
                  // otherwise the paywall (Subscribe, Restore purchases).
                  label: code == CoachLimitCode.subscriptionInvalid ? l.restorePurchases : l.seePremium,
                  leading: Icons.workspace_premium_outlined,
                  onPressed: () => showPaywall(context),
                  style: DwButtonStyle.ghost,
                  height: 44,
                  fontSize: 14,
                  padding: 16,
                ),
              if (onRetry != null)
                DwButton(
                  key: const ValueKey('retry'),
                  label: l.retry,
                  leading: Icons.refresh_rounded,
                  onPressed: onRetry,
                  style: DwButtonStyle.ghost,
                  height: 44,
                  fontSize: 14,
                  padding: 16,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The soft fair-use notice ("You're close to today's fair-use limit") the
/// backend sends with a reply: a small line above the composer. Nothing is
/// shown when there is no notice.
class _UsageNotice extends StatelessWidget {
  const _UsageNotice();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CoachUsageState?>(
      valueListenable: CoachUsage.state,
      builder: (context, usage, _) {
        final text = coachUsageNotice(context.l10n, usage?.notice);
        if (text == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Row(
              key: const ValueKey('usage-notice'),
              children: [
                const ExcludeSemantics(child: Icon(Icons.info_outline_rounded, size: 15, color: AppColors.faint)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textMuted)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
