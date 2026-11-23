import 'package:flutter/material.dart';

import '../models/coach.dart';
import '../theme/app_theme.dart';
import '../widgets/dw.dart';
import 'onboarding_screen.dart';
import '../l10n/l10n.dart';

/// First screen: a coach's portrait (Ava in English, Sofía in Spanish, so the
/// hero follows the locale), the promise, and "Get started". There is no
/// sign-in: DateWise keeps your data on this device.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final coach = l.localeName.startsWith('es') ? Coaches.sofia : Coaches.ava;
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    // iPad: the portrait may grow taller, so the page is not half empty.
    final heroHeight = (size.height * (size.height < 760 ? 0.42 : 0.5))
        .clamp(260.0, isTabletLayout(context) ? 680.0 : 500.0);

    return Scaffold(
      key: const ValueKey('welcome'),
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: heroHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Wider than the column (iPad): the portrait's sides fade
                    // into the page instead of ending in hard edges.
                    if (size.width > kContentMaxWidth)
                      ShaderMask(
                        key: const ValueKey('welcome-hero-side-fade'),
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => const LinearGradient(
                          colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                          stops: [0, 0.14, 0.86, 1],
                        ).createShader(rect),
                        child: CoachImage(coach: coach, semanticLabel: l.welcomePortrait(coach.name)),
                      )
                    else
                      CoachImage(coach: coach, semanticLabel: l.welcomePortrait(coach.name)),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x8C120C0E), Color(0x00120C0E), Color(0x00120C0E), Color(0xDB120C0E), AppColors.background],
                          stops: [0, 0.18, 0.5, 0.86, 1],
                        ),
                      ),
                    ),
                    Positioned(top: top + 10, left: 20, child: const SizedBox(height: 44, child: Center(child: BrandMark()))),
                    // Bounded on both sides, so at large text the chip's
                    // label wraps instead of running off the screen.
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 6,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: GlassChip(key: const ValueKey('welcome-chip'), label: l.chip(coach)),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, bottom + 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: l.welcomeTitleLead),
                          TextSpan(text: l.welcomeTitleAccent, style: AppText.display.copyWith(fontStyle: FontStyle.italic, color: AppColors.gold)),
                        ]),
                        style: AppText.display,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(l.welcomeBody, style: AppText.body),
                    const SizedBox(height: 20),
                    DwButton(
                      key: const ValueKey('get-started'),
                      label: l.getStarted,
                      trailing: Icons.chevron_right_rounded,
                      expand: true,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const OnboardingScreen()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Values(values: [
                      (Icons.chat_bubble_outline_rounded, l.valueConversations),
                      (Icons.person_outline_rounded, l.valueProfile),
                      (Icons.calendar_today_outlined, l.valueDates),
                    ]),
                    const SizedBox(height: 18),
                    Text(
                      l.welcomeFootnote,
                      key: const ValueKey('welcome-footnote'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.faint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three value tiles: side by side, or one per row above
/// [kStackAboveTextScale]. Side by side, a label whose longest word is wider
/// than its tile is scaled down to fit instead of breaking mid-word.
class _Values extends StatelessWidget {
  const _Values({required this.values});
  final List<(IconData, String)> values;

  static const _gap = 8.0;

  // Tile padding (6 each side) and border (1 each side).
  static const _inset = 14.0;

  @override
  Widget build(BuildContext context) {
    if (isLargeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(height: _gap),
            _Value(key: ValueKey('welcome-value-$i'), icon: values[i].$1, label: values[i].$2, row: true),
          ],
        ],
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final labelWidth = (c.maxWidth - _gap * (values.length - 1)) / values.length - _inset;
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(
                child: _Value(key: ValueKey('welcome-value-$i'), icon: values[i].$1, label: values[i].$2, labelWidth: labelWidth),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _Value extends StatelessWidget {
  const _Value({super.key, required this.icon, required this.label, this.labelWidth, this.row = false});
  final IconData icon;
  final String label;
  final double? labelWidth;

  /// One full-width row (icon, then label) instead of a column tile.
  final bool row;

  static const _style = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.3, color: AppColors.textMuted);

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, color: AppColors.gold, size: 22);
    return Container(
      padding: row ? const EdgeInsets.symmetric(vertical: 12, horizontal: 14) : const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        color: const Color(0x05FFFFFF),
      ),
      child: row
          ? Row(
              children: [
                iconWidget,
                const SizedBox(width: 12),
                Expanded(child: WholeWordsText(label, style: _style)),
              ],
            )
          : Column(
              children: [
                iconWidget,
                const SizedBox(height: 8),
                WholeWordsText(label, textAlign: TextAlign.center, style: _style, maxWidth: labelWidth),
              ],
            ),
    );
  }
}
