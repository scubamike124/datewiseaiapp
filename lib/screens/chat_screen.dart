import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/coach.dart';
import '../models/reply_options.dart';
import '../services/coach_limit_messages.dart';
import '../services/coach_usage.dart';
import '../services/reply_language.dart';
import '../services/speech_service.dart';
import '../services/store_service.dart';
import '../services/voice_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/coach_text.dart';
import '../widgets/dw.dart';
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

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();

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

  late final AppState _state;
  late final AppLifecycleListener _lifecycle;
  late final VoiceService _voice;
  late final SpeechService _speech;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _voice = context.read<VoiceService>();
    _speech = context.read<SpeechService>();
    _state.addListener(_onState);
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
      if (_voiceMode) _exitVoice();
      // Leaving the chat stops a reply that is still streaming (the HTTP
      // stream is closed); the message is kept and can be retried.
      _state.cancelReply();
    }
  }

  @override
  void dispose() {
    _state.cancelReply();
    _state.removeListener(_onState);
    _lifecycle.dispose();
    _ticker?.cancel();
    _listenGen++;
    _voice.stop();
    _speech.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Reads a finished reply aloud during a voice session.
  void _onState() {
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

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    if (!_state.canChat) {
      showPaywall(context);
      return;
    }
    _input.clear();
    await _voice.stop();
    await _state.sendMessage(text);
  }

  // --- Voice session ------------------------------------------------------

  Future<void> _enterVoice() async {
    if (!await _speech.ensureReady()) {
      if (mounted) {
        setState(() {});
        // Still "available" means permission is fine but the recognizer is
        // not (e.g. Siri & Dictation off): say so, not "permission needed".
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_speech.available ? context.l10n.voiceRecognitionUnavailable : context.l10n.voicePermissionNeeded),
        ));
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
    await _voice.stop();
    if (!mounted || gen != _listenGen) return;
    _starting = true;
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
    final l = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(why == SpeechStart.denied ? l.voicePermissionNeeded : l.voiceLanguageUnsupported),
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
    _listenGen++;
    final words = await _speech.stop();
    if (!mounted) return;
    final text = words.isNotEmpty ? words : _partial;
    setState(() {
      _listening = false;
      _partial = '';
    });
    if (text.trim().isNotEmpty) await _send(text);
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
            if (!_speech.available)
              Padding(
                key: const ValueKey('voice-unavailable'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.mic_off_outlined, size: 20, color: AppColors.faint),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l.voiceUnavailableNote(coach.name), style: AppText.small)),
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
                          title: Text(AppState.isDefaultTitle(t.title) ? l.newConversation : t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label),
                          subtitle: Text(parseReply(t.preview).body,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small),
                          trailing: IconButton(
                            tooltip: l.deleteConversation,
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.faint),
                            onPressed: () {
                              _state.deleteThread(t.id);
                              Navigator.pop(ctx);
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Rebuild when the subscription changes; AppState.canChat reads it.
    context.watch<StoreService>();
    final coach = state.selectedCoach;
    final entitled = state.canChat;
    final top = MediaQuery.paddingOf(context).top;

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
                      onMenu: entitled ? _openMenu : null,
                    ),
                  ),
                ],
              ),
            ),
            if (_voiceMode)
              // At large text the stage is capped and scrolls, instead of
              // pushing the talk dock off screen; normal text is unchanged.
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.textScalerOf(context).scale(1) > 1.3
                        ? MediaQuery.sizeOf(context).height * 0.18
                        : double.infinity),
                child: SingleChildScrollView(
                  key: const ValueKey('voice-stage-scroll'),
                  child: ContentWidth(
                    child: _Stage(
                      coach: coach,
                      speaking: speaking,
                      elapsed: _elapsed,
                      captions: _captions,
                      caption: _currentCaption(state),
                      onToggleCaptions: () => setState(() => _captions = !_captions),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: entitled
                  ? _MessageList(
                      coach: coach,
                      compact: _voiceMode,
                      onStarter: _send,
                      showIntro: !_voiceMode,
                      speaking: speaking,
                    )
                  : _Locked(coach: coach),
            ),
            if (entitled) const ContentWidth(child: _UsageNotice()),
            if (entitled)
              ContentWidth(
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
                        onSend: () => _send(_input.text),
                        onStop: _state.cancelReply,
                        onVoice: _speech.available ? _enterVoice : null,
                      ),
              ),
          ],
        );
      },
    );
  }

  String _currentCaption(AppState state) {
    final msgs = state.activeThread?.messages ?? const <ChatMessage>[];
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (!msgs[i].isUser) {
        // The whole reply: the caption box scrolls instead of cutting it.
        return parseReply(msgs[i].text).body.replaceAll(RegExp(r'\*\*'), '').replaceAll('\n', ' ');
      }
    }
    return state.selectedCoach.greeting.replaceAll('**', '').replaceAll('\n', ' ');
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
                Text(l.aiLabel(coach), key: const ValueKey('ai-label'), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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

/// Voice-mode stage: the coach's still portrait (a soft glow while speaking;
/// no video, no lip-sync), the session timer and the live captions.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.coach,
    required this.speaking,
    required this.elapsed,
    required this.captions,
    required this.caption,
    required this.onToggleCaptions,
  });

  final Coach coach;
  final bool speaking;
  final String elapsed;
  final bool captions;
  final String caption;
  final VoidCallback onToggleCaptions;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AnimatedContainer(
      // The speaking glow fades in, unless Reduce Motion is on.
      duration: motion(context, const Duration(milliseconds: 400)),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: speaking ? const Color(0x99DDB67F) : AppColors.line),
        boxShadow: speaking ? const [BoxShadow(color: Color(0x40DDB67F), blurRadius: 28, spreadRadius: 1)] : const [],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            // A shorter portrait at large text leaves room for the captions.
            height: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 110 : 170,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CoachImage(coach: coach, semanticLabel: l.coachPortraitStill(coach.name)),
                const FadeToBackground(stops: [0.6, 1], color: AppColors.surface),
                Positioned(top: 12, left: 12, child: GlassChip(key: const ValueKey('voice-timer'), label: l.voiceSession(elapsed))),
                Positioned(
                  top: 6,
                  right: 6,
                  child: CircleIconButton(
                    icon: captions ? Icons.closed_caption_rounded : Icons.closed_caption_off_outlined,
                    tooltip: captions ? l.hideCaptions : l.showCaptions,
                    onPressed: onToggleCaptions,
                    filled: true,
                  ),
                ),
              ],
            ),
          ),
          if (captions)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(coach.name.toUpperCase(), style: AppText.eyebrow.copyWith(fontSize: 11)),
                  const SizedBox(height: 4),
                  // The whole reply, never truncated: it scrolls inside a
                  // capped height, so long replies at large text stay readable.
                  // It starts at the end, the part being read aloud last.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.22),
                    child: SingleChildScrollView(
                      key: const ValueKey('voice-caption-scroll'),
                      reverse: true,
                      child: Text(caption,
                          key: const ValueKey('voice-caption'),
                          style: const TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.text)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.coach,
    required this.compact,
    required this.onStarter,
    required this.showIntro,
    required this.speaking,
  });

  final Coach coach;
  final bool compact;
  final ValueChanged<String> onStarter;
  final bool showIntro;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final thread = state.activeThread;
    final messages = thread?.messages ??
        [ChatMessage(id: 'greeting', role: MessageRole.coach, text: coach.greeting, createdAt: DateTime(2026))];
    final hasUser = messages.any((m) => m.isUser);

    final items = <Widget>[
      if (showIntro) _IntroCard(coach: coach),
      for (var i = 0; i < messages.length; i++)
        _Bubble(
          key: ValueKey('msg-${messages[i].id}'),
          message: messages[i],
          coach: coach,
          showOptions: i == messages.length - 1,
          onRetry: i == messages.length - 1 && state.canRetry ? state.retryLastReply : null,
        ),
      if (!hasUser) _Starters(coach: coach, onTap: onStarter),
    ];

    // Newest at the bottom (reversed list), but a short conversation starts
    // right under the header instead of leaving a gap above it.
    return ContentWidth(
      child: Align(
        alignment: Alignment.topCenter,
        child: ListView.builder(
          key: ValueKey('messages-${coach.id}'),
          reverse: true,
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          itemCount: items.length,
          itemBuilder: (_, i) => items[items.length - 1 - i],
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
  const _Bubble({super.key, required this.message, required this.coach, required this.showOptions, this.onRetry});
  final ChatMessage message;
  final Coach coach;
  final bool showOptions;
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
                              stopped: message.status == MessageStatus.stopped,
                              failure: message.failure,
                              code: message.failedCode,
                              onRetry: onRetry,
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
              onTap: () {
                Clipboard.setData(ClipboardData(text: o.text));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.copiedReply)));
              },
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
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
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
          ],
        ),
      ),
    );
  }
}

/// A reply that could not be delivered: the friendly notice (localized), any
/// text that arrived before the failure, and "Try again".
class _FailedReply extends StatelessWidget {
  const _FailedReply({required this.partial, required this.stopped, required this.onRetry, this.failure, this.code});
  final String partial;
  final bool stopped;
  final ReplyFailure? failure;

  /// The backend's refusal code (chat-v7); a known one shows its limit notice.
  final String? code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
                stopped
                    ? l.chatErrorStopped
                    : coachLimitMessage(l, code) ??
                        switch (failure) {
                          ReplyFailure.busy => l.chatErrorBusy,
                          ReplyFailure.offline => l.chatErrorOffline,
                          ReplyFailure.server => l.chatErrorServer,
                          null => l.chatErrorUnavailable,
                        },
                key: const ValueKey('reply-failed-notice'),
                style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.text),
              ),
            ),
          ],
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
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
