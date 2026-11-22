import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/coach.dart';
import '../models/user_profile.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/coach_card.dart';
import '../widgets/dw.dart';
import 'coaches_screen.dart';
import '../l10n/l10n.dart';

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
  CoachLanguage? _language;
  bool _adult = false;

  /// The language step starts on the current UI language (the device
  /// language, or an earlier choice).
  CoachLanguage get _lang => _language ?? AppLocales.languageOf(Localizations.localeOf(context));

  /// Choosing a language switches the app's UI language right away.
  void _setLanguage(CoachLanguage l) {
    setState(() => _language = l);
    context.read<AppState>().setLanguage(l);
  }

  /// Under 18: recorded on the device; the app shows only the "adults only"
  /// page from now on (see RootGate), with no way back into onboarding.
  Future<void> _underage() async {
    stopPreview();
    final nav = Navigator.of(context);
    await context.read<AppState>().markUnderage();
    nav.popUntil((r) => r.isFirst);
  }

  void _back() {
    if (_step == 0) {
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
    final ok = await state.completeOnboarding(
      goals: List.of(_goals),
      language: _lang,
      coachId: coach.id,
      adultConfirmed: _adult,
    );
    if (!ok) return;
    // The root now shows the paywall / app; close the onboarding route.
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final l = context.l10n;
    final (Widget body, Widget? action) = _stepBody(l);

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
                    tooltip: l.back,
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
                              duration: motion(context, const Duration(milliseconds: 250)),
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

  (Widget, Widget?) _stepBody(AppLocalizations l) {
    switch (_step) {
      case 0:
        return (
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LargeTitle(
                eyebrow: l.stepOf(1, _steps),
                title: l.goalsTitle,
                subtitle: l.goalsSubtitle,
              ),
              const SizedBox(height: 20),
              for (final g in CoachingGoal.values)
                _OptionTile(
                  key: ValueKey('goal-${g.name}'),
                  icon: _goalIcon(g),
                  title: l.goal(g),
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
            label: l.continueAction,
            expand: true,
            onPressed: _goals.isEmpty ? null : _next,
          ),
        );
      case 1:
        return (
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LargeTitle(
                eyebrow: l.stepOf(2, _steps),
                title: l.languageTitle,
                subtitle: l.languageSubtitle,
              ),
              const SizedBox(height: 20),
              _OptionTile(
                key: const ValueKey('lang-en'),
                icon: Icons.translate_rounded,
                title: 'English',
                subtitle: l.coachesFor(CoachLanguage.en),
                selected: _lang == CoachLanguage.en,
                onTap: () => _setLanguage(CoachLanguage.en),
              ),
              _OptionTile(
                key: const ValueKey('lang-es'),
                icon: Icons.translate_rounded,
                title: 'Español',
                subtitle: l.coachesFor(CoachLanguage.es),
                selected: _lang == CoachLanguage.es,
                onTap: () => _setLanguage(CoachLanguage.es),
              ),
            ],
          ),
          DwButton(key: const ValueKey('onboarding-continue'), label: l.continueAction, expand: true, onPressed: _next),
        );
      case 2:
        return (
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LargeTitle(
                eyebrow: l.stepOf(3, _steps),
                title: l.ageTitle,
                subtitle: l.ageSubtitle,
              ),
              const SizedBox(height: 20),
              _OptionTile(
                key: const ValueKey('age-confirm'),
                icon: Icons.verified_user_outlined,
                title: l.ageConfirm,
                selected: _adult,
                onTap: () => setState(() => _adult = !_adult),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('age-under'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: AppColors.textMuted),
                  onPressed: _underage,
                  child: Text(l.ageUnder),
                ),
              ),
            ],
          ),
          DwButton(
            key: const ValueKey('onboarding-continue'),
            label: l.continueAction,
            expand: true,
            onPressed: _adult ? _next : null,
          ),
        );
      default:
        return (
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LargeTitle(
                eyebrow: l.stepOf(4, _steps),
                title: l.chooseCoachTitle,
                subtitle: l.chooseCoachSubtitle,
              ),
              const SizedBox(height: 16),
              CoachGrid(
                preferred: _lang,
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

/// Shown, and kept, once the user says they are under 18: there is no way
/// forward (no back button, no onboarding, no chat).
class UnderageScreen extends StatelessWidget {
  const UnderageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      key: const ValueKey('underage'),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(alignment: Alignment.centerLeft, child: BrandMark()),
                const SizedBox(height: 32),
                LargeTitle(title: l.underageTitle, subtitle: l.underageBody),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
