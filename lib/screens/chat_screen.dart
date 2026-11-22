import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_thread.dart';
import '../models/coach.dart';
import '../models/tier.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/chat/chat_input.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/suggestion_chips.dart';
import '../widgets/chat/thread_sidebar.dart';
import '../widgets/coach/coach_avatar.dart';
import '../widgets/common/effects.dart';
import '../widgets/common/premium.dart';
import 'coach_picker_screen.dart';
import 'landing_screen.dart';

/// AI coaching chat (PRD section 5.2): threaded conversations with DateWise AI,
/// a persistent sidebar on wide screens, and a Drawer on mobile.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleSend(
    BuildContext context, {
    String text = '',
    List<String>? images,
  }) {
    context.read<AppState>().sendMessage(text: text, images: images);
    _scrollToBottom();
  }

  void _showUpgradeSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const _UpgradeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final state = context.watch<AppState>();

    // Auto-scroll as the active thread grows / streams.
    _scrollToBottom();

    final chatArea = _ChatArea(
      key: ValueKey(state.activeThreadId),
      thread: state.activeThread,
      scrollController: _scrollController,
      isResponding: state.isResponding,
      canSendPhoto: state.photoCoachUnlocked,
      onSend:
          ({String text = '', List<String>? images}) =>
              _handleSend(context, text: text, images: images),
      onPhotoBlocked: () => _showUpgradeSheet(context),
      onOpenMenu: isWide ? null : () => _scaffoldKey.currentState?.openDrawer(),
      // A new conversation continues with the coach on screen.
      onNewThread:
          () => context.read<AppState>().createThread(coach: state.activeCoach),
    );

    // First visit: the user picks one of the four coaches before chatting.
    if (!state.hasChosenCoach) {
      return Scaffold(body: CoachPicker(showHeader: true, onChosen: () {}));
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: isWide ? null : const Drawer(child: ThreadSidebar()),
      body: Row(
        children: [
          if (isWide) ...[
            const ThreadSidebar(),
            const VerticalDivider(width: 1, color: AppColors.cardBorder),
          ],
          Expanded(child: AmbientBackground(intensity: 0.55, child: chatArea)),
        ],
      ),
    );
  }
}

class _ChatArea extends StatelessWidget {
  const _ChatArea({
    super.key,
    required this.thread,
    required this.scrollController,
    required this.isResponding,
    required this.canSendPhoto,
    required this.onSend,
    required this.onPhotoBlocked,
    required this.onOpenMenu,
    required this.onNewThread,
  });

  final ChatThread? thread;
  final ScrollController scrollController;
  final bool isResponding;
  final bool canSendPhoto;
  final void Function({String text, List<String>? images}) onSend;
  final VoidCallback onPhotoBlocked;
  final VoidCallback? onOpenMenu;
  final VoidCallback onNewThread;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // A conversation the user hasn't replied to yet shows the welcome state
    // and starter prompts (mirrors the PRD's coaching entry points).
    final isFresh = thread != null && !thread!.messages.any((m) => m.isUser);
    final coach = state.activeCoach;
    const emojis = ['✍️', '🔥', '💬', '📸'];

    return Column(
      children: [
        _TopBar(
          title: thread?.title ?? 'DateWise AI',
          subtitle:
              coach.language == CoachLanguage.es
                  ? 'con ${coach.name} · ${coach.language.label}'
                  : 'with ${coach.name} · ${coach.language.label}',
          coach: coach,
          replying: isResponding,
          onOpenMenu: onOpenMenu,
          onNewThread: onNewThread,
        ),
        Expanded(
          child:
              thread == null
                  ? _NoThread(onNewThread: onNewThread)
                  : isFresh
                  ? _WelcomeState(
                    coach: coach,
                    // Starter prompts scroll with the welcome text, so a
                    // small screen or large text never overflows.
                    starters:
                        isResponding
                            ? null
                            : SuggestionChips(
                              centered: true,
                              suggestions: [
                                for (var i = 0; i < coach.starters.length; i++)
                                  Suggestion(
                                    emojis[i % emojis.length],
                                    coach.starters[i],
                                    requiresPhoto:
                                        i == coach.starters.length - 1,
                                  ),
                              ],
                              canSendPhoto: canSendPhoto,
                              onPhotoBlocked: onPhotoBlocked,
                              onSelect: (text) => onSend(text: text),
                            ),
                  )
                  : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    itemCount: thread!.messages.length,
                    itemBuilder: (context, i) {
                      final message = thread!.messages[i];
                      final bubble = Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: MessageBubble(message: message, coach: coach),
                        ),
                      );
                      // The newest message eases in; older ones stay still
                      // as they scroll back into view.
                      return i == thread!.messages.length - 1
                          ? FadeSlideIn(
                            key: ValueKey('in-${message.id}'),
                            offset: const Offset(0, 0.12),
                            child: bubble,
                          )
                          : bubble;
                    },
                  ),
        ),
        ChatInput(
          hintText:
              coach.language == CoachLanguage.es
                  ? 'Escríbele a ${coach.name}…'
                  : 'Message ${coach.name}…',
          enabled: !isResponding && thread != null,
          canSendPhoto: canSendPhoto,
          onPhotoBlocked: onPhotoBlocked,
          onSend: onSend,
          analysisMode: state.analysisMode,
          onAnalysisModeChanged:
              (m) => context.read<AppState>().setAnalysisMode(m),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.coach,
    required this.replying,
    required this.onOpenMenu,
    required this.onNewThread,
  });

  final String title;
  final String subtitle;
  final Coach coach;

  /// The coach is writing a reply: the avatar glows.
  final bool replying;
  final VoidCallback? onOpenMenu;
  final VoidCallback onNewThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        border: const Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (onOpenMenu != null)
              IconButton(
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'Conversations',
                onPressed: onOpenMenu,
              )
            else
              const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: 'Switch coach',
              child: InkWell(
                key: const ValueKey('switch-coach'),
                customBorder: const CircleBorder(),
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CoachPickerScreen(),
                      ),
                    ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CoachAvatar(coach: coach, radius: 19, glowing: replying),
                      // Presence dot: rose gold while replying, green at rest.
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: AnimatedContainer(
                          duration: AppMotion.medium,
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color:
                                replying ? AppColors.accent : AppColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.surface,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // On web the chat is reached from the marketing landing page, so we
            // keep a way back to it. On mobile the chat lives inside the native
            // tab shell — there is no website to return to, so we offer a
            // "New conversation" action instead.
            kIsWeb
                ? IconButton(
                  tooltip: 'Back to home',
                  icon: const Icon(Icons.home_outlined),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LandingScreen()),
                    );
                  },
                )
                : IconButton(
                  tooltip: 'New conversation',
                  icon: const Icon(Icons.edit_square),
                  onPressed: onNewThread,
                ),
          ],
        ),
      ),
    );
  }
}

class _NoThread extends StatelessWidget {
  const _NoThread({required this.onNewThread});
  final VoidCallback onNewThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      // Scrolls on the smallest phones with large text instead of overflowing.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GradientIcon(icon: Icons.auto_awesome, size: 64),
            const SizedBox(height: AppSpacing.md),
            Text('Start a conversation', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your coach is ready when you are.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            GradientButton(
              onPressed: onNewThread,
              icon: Icons.add_rounded,
              label: 'New conversation',
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered welcome shown for a fresh conversation, above the starter chips.
class _WelcomeState extends StatelessWidget {
  const _WelcomeState({required this.coach, this.starters});
  final Coach coach;
  final Widget? starters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: FadeSlideIn(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: coach.color.withValues(alpha: 0.35),
                        blurRadius: 40,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CoachAvatar(coach: coach, radius: 36, selected: true),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  coach.welcomeTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  coach.welcomeBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                if (starters != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  starters!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpgradeSheet extends StatelessWidget {
  const _UpgradeSheet();

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final theme = Theme.of(context);
    final magnet = TierInfo.magnet;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GradientIcon(icon: Icons.bolt_rounded, size: 36),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'Unlock the AI Photo Coach',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Photo scoring, KEEP / RESHOOT / DELETE verdicts, and match-rate '
            'predictions are part of the Magnet plan (${magnet.priceLabel}/wk).',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: GradientButton(
                  onPressed: () async {
                    await state.selectTier(SubscriptionTier.magnet);
                    if (context.mounted) Navigator.pop(context);
                  },
                  label: 'Upgrade to Magnet',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
