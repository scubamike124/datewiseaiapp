import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/speech_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dw.dart';
import 'shell.dart';
import '../l10n/l10n.dart';

/// A quick action on Home: opens the chat with a starter prompt (both in the
/// UI language; the coach answers in its own language unless the user writes
/// in another).
class QuickAction {
  const QuickAction(this.id, this.icon);
  final String id;
  final IconData icon;

  String label(AppLocalizations l) => switch (id) {
        'practice' => l.quickPractice,
        'profile' => l.quickProfile,
        'date' => l.quickDate,
        _ => l.quickReply,
      };

  String prompt(AppLocalizations l) => switch (id) {
        'practice' => l.quickPracticePrompt,
        'profile' => l.quickProfilePrompt,
        'date' => l.quickDatePrompt,
        _ => l.quickReplyPrompt,
      };

  static const all = [
    QuickAction('practice', Icons.mic_none_rounded),
    QuickAction('profile', Icons.account_box_outlined),
    QuickAction('date', Icons.calendar_today_outlined),
    QuickAction('reply', Icons.chat_bubble_outline_rounded),
  ];
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final shell = context.read<ShellController>();
    final speech = context.read<SpeechService>();
    final coach = state.selectedCoach;
    final last = state.latestThreadFor(coach);
    final resume = last != null && last.messages.any((m) => m.isUser) ? last.title : null;
    final top = MediaQuery.paddingOf(context).top;
    final l = context.l10n;

    return SingleChildScrollView(
      key: const PageStorageKey('home-scroll'),
      child: ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero: portrait on the right, fading into the page.
            Stack(
              children: [
                Positioned(
                  right: -36,
                  top: 0,
                  width: 300,
                  height: 330 + top,
                  // Fade the photo's left and bottom edges into the page.
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      colors: [Color(0x00000000), Color(0xFF000000)],
                      stops: [0, 0.4],
                    ).createShader(rect),
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF000000), Color(0x00000000)],
                        stops: [0.55, 0.92],
                      ).createShader(rect),
                      child: CoachImage(coach: coach, semanticLabel: l.coachPortrait(coach.name)),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.background, Color(0xB8120C0E), Color(0x00120C0E)],
                        stops: [0.22, 0.48, 0.72],
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x80150C10), Color(0x00150C10), Color(0x00150C10), Color(0xD9150C10), AppColors.background],
                        stops: [0, 0.2, 0.42, 0.78, 0.92],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, top + 12, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 44, child: Align(alignment: Alignment.centerLeft, child: BrandMark())),
                      const SizedBox(height: 22),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(l.greetingFor(DateTime.now()),
                                  style: AppText.display.copyWith(fontSize: 34, height: 1.05)),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              resume == null
                                  ? l.homeReady(coach.name, l.gender(coach))
                                  : l.homeResume(coach.name, l.gender(coach), resume),
                              style: AppText.body.copyWith(fontSize: 15, height: 1.45),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Flexible(
                            child: DwButton(
                              key: const ValueKey('home-talk'),
                              label: l.talkTo(coach.name),
                              onPressed: () => shell.openChat(),
                              height: 50,
                              fontSize: 15,
                              padding: 22,
                            ),
                          ),
                          if (speech.available) ...[
                            const SizedBox(width: 10),
                            CircleIconButton(
                              key: const ValueKey('home-voice'),
                              icon: Icons.mic_none_rounded,
                              tooltip: l.voiceChatWith(coach.name),
                              size: 50,
                              onPressed: () => shell.openChat(voice: true),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _PlanCard(),
                  const SizedBox(height: 14),
                  const _QuickTiles(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final plan = state.plan;
    final coach = state.selectedCoach;
    final l = context.l10n;
    if (plan == null) return const SizedBox.shrink();
    final nextIndex = plan.items.indexWhere((i) => !i.done);
    return DwCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.planThisWeek.toUpperCase(), style: AppText.eyebrow.copyWith(fontSize: 13, letterSpacing: 1.6)),
          const SizedBox(height: 6),
          for (var i = 0; i < plan.items.length; i++) ...[
            if (i > 0) const Divider(),
            _PlanRow(
              key: ValueKey('plan-$i'),
              title: l.planItemTitle(plan.items[i].goal, coach),
              done: plan.items[i].done,
              isNext: i == nextIndex,
              onToggle: () => state.togglePlanItem(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({super.key, required this.title, required this.done, required this.isNext, required this.onToggle});
  final String title;
  final bool done;
  final bool isNext;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: done,
      label: title,
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: motion(context, const Duration(milliseconds: 200)),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? const Color(0x298CC9A3) : null,
                    border: done ? null : Border.all(color: isNext ? AppColors.gold : AppColors.line2, width: 1.5),
                  ),
                  child: done ? const Icon(Icons.check_rounded, size: 15, color: AppColors.ok) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: TextStyle(fontFamily: AppFonts.sans, fontSize: 15, height: 1.3, color: done ? AppColors.textMuted : AppColors.text)),
                ),
                const SizedBox(width: 8),
                Text(done ? context.l10n.planDone : (isNext ? context.l10n.planNext : ''), style: const TextStyle(fontSize: 13, color: AppColors.faint)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickTiles extends StatelessWidget {
  const _QuickTiles();

  static const _backgrounds = [
    RadialGradient(center: Alignment.topLeft, radius: 1.2, colors: [Color(0x33DDB67F), Color(0x001E1518)]),
    RadialGradient(center: Alignment.topRight, radius: 1.2, colors: [Color(0x38E2899E), Color(0x001E1518)]),
    RadialGradient(center: Alignment.bottomRight, radius: 1.3, colors: [Color(0x598E3550), Color(0x001E1518)]),
    RadialGradient(center: Alignment.bottomLeft, radius: 1.2, colors: [Color(0x29DDB67F), Color(0x001E1518)]),
  ];

  @override
  Widget build(BuildContext context) {
    final shell = context.read<ShellController>();
    final l = context.l10n;
    Widget tile(int i) {
      final a = QuickAction.all[i];
      return _Tile(
        key: ValueKey('tile-${a.id}'),
        icon: a.icon,
        label: a.label(l),
        glow: _backgrounds[i],
        onTap: () => shell.openChat(prompt: a.prompt(l)),
      );
    }

    Widget row(int a, int b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: tile(a)), const SizedBox(width: 10), Expanded(child: tile(b))],
          ),
        );
    return Column(children: [row(0, 1), const SizedBox(height: 10), row(2, 3)]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.icon, required this.label, required this.glow, required this.onTap});
  final IconData icon;
  final String label;
  final Gradient glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 100),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.line),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A1C20), AppColors.surface]),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(gradient: glow),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0x8C120C0E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line2),
                    ),
                    child: Icon(icon, size: 19, color: AppColors.gold),
                  ),
                  const SizedBox(height: 10),
                  Text(label, style: AppText.label.copyWith(height: 1.25)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
