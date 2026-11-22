import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/coach.dart';
import '../models/reply_options.dart';
import '../services/speech_service.dart';
import '../services/store_service.dart';
import '../services/voice_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/coach_text.dart';
import '../widgets/dw.dart';
import 'paywall_screen.dart';
import 'shell.dart';

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

  late final AppState _state;
  late final VoiceService _voice;
  late final SpeechService _speech;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _voice = context.read<VoiceService>();
    _speech = context.read<SpeechService>();
    _state.addListener(_onState);
    if (widget.active) WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
    }
    if (!widget.active && old.active && _voiceMode) _exitVoice();
  }

  @override
  void dispose() {
    _state.removeListener(_onState);
    _ticker?.cancel();
    if (_voiceMode) _voice.stop();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Reads a finished reply aloud during a voice session.
  void _onState() {
    final responding = _state.isResponding;
    if (_wasResponding && !responding && _voiceMode && _readAloud) {
      final last = _state.activeThread?.messages.lastOrNull;
      if (last != null && !last.isUser) {
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Voice needs microphone and speech recognition access. You can allow it in Settings.'),
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
    if (_listening) _speech.stop();
    setState(() {
      _voiceMode = false;
      _voiceStarted = null;
      _listening = false;
      _partial = '';
    });
  }

  Future<void> _startListening() async {
    if (_listening || _state.isResponding) return;
    await _voice.stop();
    HapticFeedback.lightImpact();
    setState(() {
      _listening = true;
      _partial = '';
    });
    await _speech.start(
      localeId: _state.selectedCoach.language.locale,
      onWords: (w) {
        if (mounted) setState(() => _partial = w);
      },
    );
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    final words = await _speech.stop();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _partial = '';
    });
    final text = words.isNotEmpty ? words : _partial;
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
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetTile(
              icon: Icons.add_comment_outlined,
              label: 'New conversation',
              onTap: () {
                Navigator.pop(ctx);
                _state.createThread();
              },
            ),
            _SheetTile(
              icon: Icons.history_rounded,
              label: 'Past conversations with ${coach.name}',
              onTap: () {
                Navigator.pop(ctx);
                _openHistory();
              },
            ),
            _SheetTile(
              icon: Icons.swap_horiz_rounded,
              label: 'Switch coach',
              onTap: () {
                Navigator.pop(ctx);
                context.read<ShellController>().go(AppTab.coaches);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openHistory() {
    final coach = _state.selectedCoach;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final threads = _state.threadsFor(coach);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: threads.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No saved conversations yet.', style: AppText.body),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Text('Conversations with ${coach.name}', style: AppText.name.copyWith(fontSize: 22)),
                      ),
                      for (final t in threads)
                        ListTile(
                          minTileHeight: 56,
                          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label),
                          subtitle: Text(parseReply(t.preview).body,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small),
                          trailing: IconButton(
                            tooltip: 'Delete conversation',
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
            SizedBox(height: top),
            ContentWidth(
              child: _Header(
                coach: coach,
                speaking: speaking,
                onMenu: entitled ? _openMenu : null,
              ),
            ),
            if (_voiceMode)
              ContentWidth(
                child: _Stage(
                  coach: coach,
                  speaking: speaking,
                  elapsed: _elapsed,
                  captions: _captions,
                  caption: _currentCaption(state),
                  onToggleCaptions: () => setState(() => _captions = !_captions),
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
                        onKeyboard: _exitVoice,
                        onToggleReadAloud: () {
                          setState(() => _readAloud = !_readAloud);
                          if (!_readAloud) _voice.stop();
                        },
                      )
                    : _Composer(
                        controller: _input,
                        focus: _focus,
                        hint: coach.composerHint,
                        busy: state.isResponding,
                        onSend: () => _send(_input.text),
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
        final body = parseReply(msgs[i].text).body.replaceAll(RegExp(r'\*\*'), '').replaceAll('\n', ' ');
        return body.length > 240 ? '…${body.substring(body.length - 240)}' : body;
      }
    }
    return state.selectedCoach.greeting.replaceAll('**', '').replaceAll('\n', ' ');
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({required this.icon, required this.label, required this.onTap});
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          CoachAvatar(coach: coach, size: 40, speaking: speaking),
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
                Text(coach.aiLabel, key: const ValueKey('ai-label'), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (onMenu != null)
            CircleIconButton(
              key: const ValueKey('chat-menu'),
              icon: Icons.more_horiz_rounded,
              tooltip: 'Conversation options',
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
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
            height: 170,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CoachImage(coach: coach, semanticLabel: '${coach.name}, AI coach (still portrait)'),
                const FadeToBackground(stops: [0.6, 1], color: AppColors.surface),
                Positioned(top: 12, left: 12, child: GlassChip(key: const ValueKey('voice-timer'), label: 'Voice session · $elapsed')),
                Positioned(
                  top: 6,
                  right: 6,
                  child: CircleIconButton(
                    icon: captions ? Icons.closed_caption_rounded : Icons.closed_caption_off_outlined,
                    tooltip: captions ? 'Hide captions' : 'Show captions',
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
                  Text(caption, maxLines: 4, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.text)),
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
        ),
      if (!hasUser) _Starters(coach: coach, onTap: onStarter),
    ];

    return ContentWidth(
      child: ListView.builder(
        key: ValueKey('messages-${coach.id}'),
        reverse: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        itemCount: items.length,
        itemBuilder: (_, i) => items[items.length - 1 - i],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.coach});
  final Coach coach;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 4),
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoachImage(coach: coach, semanticLabel: '${coach.name}, AI coach portrait'),
          const FadeToBackground(stops: [0.35, 1], color: Color(0xF2150C10)),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassChip(label: '${coach.name} · AI coach · ${coach.language.label}'),
                const SizedBox(height: 8),
                Text(coach.description, maxLines: 2, overflow: TextOverflow.ellipsis,
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
  const _Bubble({super.key, required this.message, required this.coach, required this.showOptions});
  final ChatMessage message;
  final Coach coach;
  final bool showOptions;

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
          child: Text(message.text, style: const TextStyle(fontSize: 15, height: 1.45, color: Color(0xFFF6E6D2))),
        ),
      );
    }
    final parsed = parseReply(message.text);
    final waiting = message.isStreaming && parsed.body.isEmpty;
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
                          label: '${coach.name} is typing',
                          child: const Text('•••', style: TextStyle(color: AppColors.faint, letterSpacing: 2)),
                        )
                      : CoachText(parsed.body),
                ),
              ),
            ],
          ),
          if (showOptions && !message.isStreaming && parsed.options.isNotEmpty)
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
            label: 'Copy ${o.label} reply: ${o.text}',
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('option-${o.label}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Clipboard.setData(ClipboardData(text: o.text));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied. Paste it into your dating app.')));
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
          for (final s in coach.starters)
            ActionChip(
              key: ValueKey('starter-$s'),
              label: Text(s),
              onPressed: () => onTap(s),
              backgroundColor: const Color(0x0DFFFFFF),
              side: const BorderSide(color: AppColors.line2),
              shape: const StadiumBorder(),
              labelStyle: const TextStyle(fontSize: 13.5, color: AppColors.text),
              materialTapTargetSize: MaterialTapTargetSize.padded,
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
    required this.onVoice,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback? onVoice;

  @override
  Widget build(BuildContext context) {
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
              tooltip: 'Voice mode',
              size: 48,
              onPressed: onVoice,
            ),
          ],
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Send',
            child: Material(
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: const BoxDecoration(gradient: AppColors.goldGradient, shape: BoxShape.circle),
                child: InkWell(
                  key: const ValueKey('send'),
                  onTap: busy ? null : onSend,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldInk),
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
  final VoidCallback onKeyboard;
  final VoidCallback onToggleReadAloud;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (listening)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(partial.isEmpty ? 'Listening…' : partial,
                  textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Color(0xFFF6E6D2))),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleIconButton(icon: Icons.keyboard_alt_outlined, tooltip: 'Type instead', onPressed: onKeyboard),
              const SizedBox(width: 28),
              Semantics(
                button: true,
                label: 'Hold to talk',
                child: Listener(
                  onPointerDown: busy ? null : (_) => onHoldStart(),
                  onPointerUp: (_) => onHoldEnd(),
                  onPointerCancel: (_) => onHoldEnd(),
                  child: AnimatedContainer(
                    key: const ValueKey('hold-to-talk'),
                    duration: const Duration(milliseconds: 200),
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
              const SizedBox(width: 28),
              CircleIconButton(
                icon: readAloud ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                tooltip: readAloud ? 'Stop reading replies aloud' : 'Read replies aloud',
                onPressed: onToggleReadAloud,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Hold to talk · ${coach.name} is an AI coach', textAlign: TextAlign.center, style: AppText.small),
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
                  Text('DATEWISE PREMIUM', style: AppText.eyebrow),
                  const SizedBox(height: 8),
                  Text('Chat with ${coach.name} is part of DateWise Premium.', style: AppText.name.copyWith(fontSize: 24)),
                  const SizedBox(height: 8),
                  const Text('Subscribe to talk with all four AI coaches. Your conversations stay on this device.', style: AppText.body),
                  const SizedBox(height: 16),
                  DwButton(
                    key: const ValueKey('locked-subscribe'),
                    label: 'See DateWise Premium',
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
