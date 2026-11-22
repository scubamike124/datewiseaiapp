import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/coach.dart';
import '../models/user_profile.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/coach_card.dart';
import '../widgets/dw.dart';
import 'coaches_screen.dart';

/// Onboarding after the welcome screen: goals, language, 18+ confirmation,
/// then choosing a coach. Finishing it hands over to the paywall (root).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.initialStep = 0});
  final int initialStep;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with VoicePreview {
  static const _steps = 4;
  late int _step = widget.initialStep;
  final List<CoachingGoal> _goals = [];
  CoachLanguage _language = CoachLanguage.en;
  bool _adult = false;
  bool _underage = false;

  void _back() {
    if (_underage) {
      setState(() => _underage = false);
    } else if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _step--);
    }
  }

  void _next() => setState(() => _step++);

  Future<void> _choose(Coach coach) async {
    stopPreview();
    final state = context.read<AppState>();
    final nav = Navigator.of(context);
    await state.completeOnboarding(goals: List.of(_goals), language: _language, coachId: coach.id);
    // The root now shows the paywall / app; close the onboarding route.
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final (Widget body, Widget? action) = _underage ? (_underageBody(), null) : _stepBody();

    return Scaffold(
      key: ValueKey('onboarding-$_step'),
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SizedBox(height: top),
          ContentWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('onboarding-back'),
                    tooltip: 'Back',
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: _back,
                    icon: const Icon(Icons.chevron_left_rounded, size: 30, color: AppColors.text),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < _steps; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 4,
                              decoration: BoxDecoration(
                                color: i <= _step ? AppColors.gold : AppColors.line2,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: ContentWidth(child: body),
            ),
          ),
          if (action != null)
            ContentWidth(
              child: Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 16), child: action),
            ),
        ],
      ),
    );
  }

  (Widget, Widget?) _stepBody() {
    switch (_step) {
      case 0:
        return (
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LargeTitle(
                eyebrow: 'Step 1 of 4',
                title: 'What would you like help with?',
                subtitle: 'Pick up to three. They become your plan for the week.',
              ),
              const SizedBox(height: 20),
              for (final g in CoachingGoal.values)
                _OptionTile(
                  key: ValueKey('goal-${g.name}'),
                  icon: _goalIcon(g),
                  title: g.label,
                  selected: _goals.contains(g),
                  onTap: () => setState(() {
                    if (_goals.contains(g)) {
                      _goals.remove(g);
                    } else if (_goals.length < 3) {
                      _goals.add(g);
                    }
                  }),
                ),
            ],
          ),
          DwButton(
            key: const ValueKey('onboarding-continue'),
            label: 'Continue',
            expand: true,
            onPressed: _goals.isEmpty ? null : _next,
          ),
        );
      case 1:
        return (
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LargeTitle(
                eyebrow: 'Step 2 of 4',
                title: 'Which language should your coach speak?',
                subtitle: 'You can change this any time in You.',
              ),
              const SizedBox(height: 20),
              _OptionTile(
                key: const ValueKey('lang-en'),
                icon: Icons.translate_rounded,
                title: 'English',
                subtitle: 'Coaches: Ava and Ethan',
                selected: _language == CoachLanguage.en,
                onTap: () => setState(() => _language = CoachLanguage.en),
              ),
              _OptionTile(
                key: const ValueKey('lang-es'),
                icon: Icons.translate_rounded,
                title: 'Español',
                subtitle: 'Coaches: Sofía y Diego',
                selected: _language == CoachLanguage.es,
                onTap: () => setState(() => _language = CoachLanguage.es),
              ),
            ],
          ),
          DwButton(key: const ValueKey('onboarding-continue'), label: 'Continue', expand: true, onPressed: _next),
        );
      case 2:
        return (
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LargeTitle(
                eyebrow: 'Step 3 of 4',
                title: 'DateWise is for adults.',
                subtitle: 'Please confirm your age to continue.',
              ),
              const SizedBox(height: 20),
              _OptionTile(
                key: const ValueKey('age-confirm'),
                icon: Icons.verified_user_outlined,
                title: 'I am 18 or older',
                selected: _adult,
                onTap: () => setState(() => _adult = !_adult),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('age-under'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: AppColors.textMuted),
                  onPressed: () => setState(() => _underage = true),
                  child: const Text('I am under 18'),
                ),
              ),
            ],
          ),
          DwButton(
            key: const ValueKey('onboarding-continue'),
            label: 'Continue',
            expand: true,
            onPressed: _adult ? _next : null,
          ),
        );
      default:
        return (
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LargeTitle(
                eyebrow: 'Step 4 of 4',
                title: 'Choose your dating coach',
                subtitle: 'All four are AI coaches. Pick a style; switch any time.',
              ),
              const SizedBox(height: 16),
              CoachGrid(
                preferred: _language,
                previewingId: previewingId,
                onPreview: previewHandler(),
                onChat: _choose,
              ),
            ],
          ),
          null,
        );
    }
  }

  Widget _underageBody() => const Column(
        key: ValueKey('underage'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LargeTitle(
            title: 'Sorry, DateWise is only for adults.',
            subtitle: 'You need to be 18 or older to use DateWise AI.',
          ),
        ],
      );

  static IconData _goalIcon(CoachingGoal g) => switch (g) {
        CoachingGoal.conversations => Icons.chat_bubble_outline_rounded,
        CoachingGoal.profile => Icons.account_box_outlined,
        CoachingGoal.dates => Icons.calendar_today_outlined,
        CoachingGoal.confidence => Icons.bolt_rounded,
        CoachingGoal.relationship => Icons.favorite_border_rounded,
      };
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? const Color(0xFF2E2019) : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: selected ? AppColors.gold : AppColors.line, width: selected ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, color: AppColors.gold, size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppText.label.copyWith(fontSize: 16)),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: selected ? AppColors.gold : AppColors.line2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
