import 'package:flutter/material.dart';

import '../models/coach.dart';
import '../theme/app_theme.dart';
import '../widgets/dw.dart';
import 'onboarding_screen.dart';
import '../l10n/l10n.dart';

/// First screen: Ava's portrait, the promise, and "Get started". There is no
/// sign-in: DateWise keeps your data on this device.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const coach = Coaches.ava;
    final l = context.l10n;
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final heroHeight = (size.height * (size.height < 760 ? 0.42 : 0.5)).clamp(260.0, 500.0);

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
                    CoachImage(coach: coach, semanticLabel: l.welcomePortrait),
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
                    Positioned(
                      left: 20,
                      bottom: 6,
                      child: GlassChip(label: l.chip(coach)),
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
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _Value(icon: Icons.chat_bubble_outline_rounded, label: l.valueConversations)),
                          const SizedBox(width: 8),
                          Expanded(child: _Value(icon: Icons.person_outline_rounded, label: l.valueProfile)),
                          const SizedBox(width: 8),
                          Expanded(child: _Value(icon: Icons.calendar_today_outlined, label: l.valueDates)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      l.welcomeFootnote,
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

class _Value extends StatelessWidget {
  const _Value({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        color: const Color(0x05FFFFFF),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.gold, size: 22),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.3, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
