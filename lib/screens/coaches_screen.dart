import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/coach.dart';
import '../services/voice_service.dart';
import '../state/app_state.dart';
import '../widgets/coach_card.dart';
import '../widgets/dw.dart';
import 'shell.dart';
import '../l10n/l10n.dart';

/// Plays a coach's short spoken intro with on-device TTS. Shared by the
/// Coaches tab and the onboarding coach step.
mixin VoicePreview<T extends StatefulWidget> on State<T> {
  String? previewingId;
  VoidCallback? _listener;

  VoiceService? _voiceRef;
  VoiceService get _voice => _voiceRef ??= context.read<VoiceService>();

  void Function(Coach)? previewHandler() {
    if (!_voice.available) return null;
    if (_listener == null) {
      _listener = () {
        if (!_voice.speaking.value && mounted && previewingId != null) {
          setState(() => previewingId = null);
        }
      };
      _voice.speaking.addListener(_listener!);
    }
    return (coach) async {
      if (previewingId == coach.id) {
        await _voice.stop();
        if (mounted) setState(() => previewingId = null);
        return;
      }
      setState(() => previewingId = coach.id);
      await _voice.speak(coach.voiceIntro, coach);
    };
  }

  void stopPreview() {
    if (previewingId != null) {
      _voice.stop();
      previewingId = null;
    }
  }

  @override
  void dispose() {
    if (_listener != null) _voiceRef?.speaking.removeListener(_listener!);
    super.dispose();
  }
}

class CoachesScreen extends StatefulWidget {
  const CoachesScreen({super.key});

  @override
  State<CoachesScreen> createState() => _CoachesScreenState();
}

class _CoachesScreenState extends State<CoachesScreen> with VoicePreview {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l = context.l10n;
    final top = MediaQuery.paddingOf(context).top;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.1,
          colors: [Color(0xFF3A1626), Color(0x00150C10)],
          stops: [0, 0.7],
        ),
      ),
      child: StatusBarScrim(
        child: SingleChildScrollView(
        // The last line clears the tab bar and the home indicator.
        padding: EdgeInsets.fromLTRB(14, top + 16, 14, 24 + MediaQuery.paddingOf(context).bottom),
        child: ContentWidth(
          maxWidth: kWideContentMaxWidth,
          child: Column(
            children: [
              LargeTitle(
                eyebrow: l.coachesEyebrow,
                title: l.chooseCoachTitle,
                subtitle: l.chooseCoachSubtitle,
                center: true,
              ),
              const SizedBox(height: 16),
              CoachGrid(
                selectedId: state.selectedCoach.id,
                previewingId: previewingId,
                preferred: state.chosenLanguage ?? AppLocales.languageOf(Localizations.localeOf(context)),
                onPreview: previewHandler(),
                onChat: (coach) async {
                  stopPreview();
                  await state.selectCoach(coach.id);
                  if (context.mounted) context.read<ShellController>().openChat();
                },
              ),
              // No footnote under the grid: each card's badge already says
              // English or Español, and a last line here was cut off by the
              // tab bar on smaller iPhones.
            ],
          ),
        ),
      ),
      ),
    );
  }
}
