import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/coach.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/coach/coach_avatar.dart';

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
  const CoachPicker({super.key, required this.onChosen, this.showHeader = false});

  /// Called after a coach is picked.
  final VoidCallback onChosen;

  /// Shows the title and intro above the cards (the embedded first-run view).
  final bool showHeader;

  @override
  State<CoachPicker> createState() => _CoachPickerState();
}

class _CoachPickerState extends State<CoachPicker> {
  late CoachLanguage _language = context.read<AppState>().selectedCoach.language;

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

    return SafeArea(
      top: widget.showHeader,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (widget.showHeader) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Choose your coach',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Four coaches, two languages. You can switch any time from the chat.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Center(
                child: SegmentedButton<CoachLanguage>(
                  segments: const [
                    ButtonSegment(value: CoachLanguage.en, label: Text('English')),
                    ButtonSegment(value: CoachLanguage.es, label: Text('Español')),
                  ],
                  selected: {_language},
                  onSelectionChanged: (s) => setState(() => _language = s.first),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (columns == 1)
                for (final c in coaches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: CoachCard(coach: c, selected: c.id == selectedId, onTap: () => _choose(c)),
                  )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < coaches.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: CoachCard(
                            coach: coaches[i], selected: coaches[i].id == selectedId, onTap: () => _choose(coaches[i])),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One coach: avatar, name, language, tagline, specialty, and the button to
/// start talking to them (in their language).
class CoachCard extends StatelessWidget {
  const CoachCard({super.key, required this.coach, required this.selected, required this.onTap});

  final Coach coach;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final es = coach.language == CoachLanguage.es;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        key: ValueKey('coach-card-${coach.id}'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: selected ? coach.color : AppColors.cardBorder, width: selected ? 2 : 1),
          ),
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
                              child: Text(coach.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            _LanguageBadge(coach: coach),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(coach.tagline,
                            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  if (selected) Icon(Icons.check_circle, color: coach.color),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(coach.specialty, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: coach.color),
                  onPressed: onTap,
                  child: Text(es ? 'Hablar con ${coach.name}' : 'Talk to ${coach.name}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageBadge extends StatelessWidget {
  const _LanguageBadge({required this.coach});
  final Coach coach;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: coach.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(coach.language.code,
          style: TextStyle(color: coach.color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
