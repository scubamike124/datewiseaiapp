import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/dw.dart';

/// Settings › "More natural coach voices": how to download Apple's free
/// Premium / Enhanced voices, which the voice service then prefers
/// (DeviceVoiceService.pickVoice ranks Premium > Enhanced > default).
Future<void> showPremiumVoiceTip(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final l = ctx.l10n;
      return SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('voice-quality-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(l.voiceQualityTitle, style: AppText.name.copyWith(fontSize: 22)),
              ),
              const SizedBox(height: 10),
              Text(l.voiceQualityBody, style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.text)),
              const SizedBox(height: 18),
              DwButton(label: l.voiceQualityDone, expand: true, onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      );
    },
  );
}
