import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/coach.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/coach/coach_avatar.dart';
import '../widgets/common/effects.dart';
import '../widgets/common/premium.dart';

/// "Choose your coach": the four DateWise coaches, filtered by language.
///
/// Used two ways: as the first thing a user sees in the Coach tab before they
/// have picked anyone ([CoachPicker] embedded, `onChosen` keeps them in place),
/// and as a pushed screen from the chat header to switch coach.
class CoachPickerScreen extends StatelessWidget {
  const CoachPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose your coach')),
      body: CoachPicker(onChosen: () => Navigator.of(context).maybePop()),
    );
  }
}

class CoachPicker extends StatefulWidget {
  const CoachPicker({
    super.key,
    required this.onChosen,
    this.showHeader = false,
  });

  /// Called after a coach is picked.
  final VoidCallback onChosen;

  /// Shows the title and intro above the cards (the embedded first-run view).
  final bool showHeader;

  @override
  State<CoachPicker> createState() => _CoachPickerState();
}

class _CoachPickerState extends State<CoachPicker> {
  late CoachLanguage _language =
      context.read<AppState>().selectedCoach.language;

  Future<void> _choose(Coach coach) async {
    await context.read<AppState>().selectCoach(coach.id);
    if (mounted) widget.onChosen();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final selectedId = state.hasChosenCoach ? state.selectedCoach.id : null;
    final coaches = Coaches.forLanguage(_language);
    final width = MediaQuery.sizeOf(context).width;
    // One column on phones, two side by side from tablet width up.
    final columns = width >= 700 ? 2 : 1;
    final es = _language == CoachLanguage.es;

    return AmbientBackground(
      intensity: widget.showHeader ? 1 : 0.7,
      child: SafeArea(
        top: widget.showHeader,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: width < 400 ? AppSpacing.md : AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              children: [
                if (widget.showHeader) ...[
                  Text(
                    'Choose your coach',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Four coaches, two languages. You can switch any time from the chat.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Center(
                  child: SegmentedButton<CoachLanguage>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: CoachLanguage.en,
                        label: Text('English'),
                      ),
                      ButtonSegment(
                        value: CoachLanguage.es,
                        label: Text('Español'),
                      ),
                    ],
                    selected: {_language},
                    onSelectionChanged:
                        (s) => setState(() => _language = s.first),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FadeSlideIn(
                  key: ValueKey(_language),
                  child:
                      columns == 1
                          ? Column(
                            children: [
                              for (final c in coaches)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.md,
                                  ),
                                  child: CoachCard(
                                    coach: c,
                                    selected: c.id == selectedId,
                                    onTap: () => _choose(c),
                                  ),
                                ),
                            ],
                          )
                          : IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < coaches.length; i++) ...[
                                  if (i > 0)
                                    const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: CoachCard(
                                      coach: coaches[i],
                                      selected: coaches[i].id == selectedId,
                                      onTap: () => _choose(coaches[i]),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                ),
                if (columns > 1) const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        es
                            ? 'Coaches de IA · tus chats se quedan en tu dispositivo'
                            : 'AI coaches · your chats stay on your device',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One coach: avatar, name, language, tagline, specialty, and the button to
/// start talking to them (in their language).
class CoachCard extends StatefulWidget {
  const CoachCard({
    super.key,
    required this.coach,
    required this.selected,
    required this.onTap,
  });

  final Coach coach;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<CoachCard> createState() => _CoachCardState();
}

class _CoachCardState extends State<CoachCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coach = widget.coach;
    final selected = widget.selected;
    final es = coach.language == CoachLanguage.es;
    // The coach colour lifted for legibility on the dark card (>= 4.5:1).
    final tint = Color.lerp(coach.color, Colors.white, 0.45)!;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.curve,
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        decoration: glassDecoration(
          radius: AppRadius.lg,
          borderColor:
              selected
                  ? tint.withValues(alpha: 0.8)
                  : _hover
                  ? AppColors.primaryLight.withValues(alpha: 0.45)
                  : null,
          borderWidth: selected ? 1.5 : 1,
          glowColor: selected || _hover ? coach.color : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('coach-card-${coach.id}'),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md + 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CoachAvatar(coach: coach, radius: 28, selected: selected),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    coach.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _LanguageBadge(coach: coach, color: tint),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              coach.tagline,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.accent,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.glassBorder),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                            color: tint,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            coach.specialty,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  GradientButton(
                    expand: true,
                    onPressed: widget.onTap,
                    label:
                        es
                            ? 'Hablar con ${coach.name}'
                            : 'Talk to ${coach.name}',
                    trailingIcon: Icons.arrow_forward_rounded,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageBadge extends StatelessWidget {
  const _LanguageBadge({required this.coach, required this.color});
  final Coach coach;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: coach.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        coach.language.code,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
