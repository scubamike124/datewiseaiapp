import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/l10n.dart';
import '../../models/coach.dart';
import '../../services/coach_usage.dart';
import '../../state/app_state.dart';
import '../../widgets/dw.dart';
import 'avatar_audio_source.dart';
import 'avatar_bridge.dart';
import 'avatar_consent.dart';
import 'avatar_flags.dart';
import 'avatar_session_api.dart';
import 'hosted_avatar_controller.dart';
import 'hosted_avatar_view.dart';

/// Pilot-only screen for running the hosted avatar on a real iPhone: connection
/// state, time to first frame, round-trip time, microphone permission, minutes used,
/// and buttons to start, speak a test phrase, interrupt and stop. Reachable only
/// when [AvatarFlags.pilotScreenAvailable] (flag on AND a debug build or a TestFlight
/// build pointed at a non-production coach server), from You > Avatar pilot.
///
/// "Speak test phrase" uses the neural voice endpoint when it exists and otherwise
/// a tone burst ([ToneAudioSource]); the tone exercises connection, latency,
/// interruption and minute counting but not lip-sync quality.
class PilotDebugScreen extends StatefulWidget {
  const PilotDebugScreen({super.key, this.controller, this.flags});

  /// Tests inject a controller built on a fake bridge.
  final HostedAvatarController? controller;
  final AvatarFlags? flags;

  @override
  State<PilotDebugScreen> createState() => _PilotDebugScreenState();
}

class _PilotDebugScreenState extends State<PilotDebugScreen> {
  HostedAvatarController? _c;
  final bool _useTone = true; // the neural voice endpoint does not exist yet (see ToneAudioSource)

  @override
  void initState() {
    super.initState();
    _c = widget.controller;
    if (_c == null) _build();
  }

  Future<void> _build() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final app = context.read<AppState>();
    final flags = widget.flags ?? AvatarFlags.fromBuild();
    final coach = app.selectedCoach;
    setState(() {
      _c = HostedAvatarController(
        api: AvatarSessionApi(),
        bridge: WebViewAvatarBridge(),
        audio: _useTone ? ToneAudioSource() : WorkerTtsAudioSource(),
        consent: AvatarConsent(prefs),
        flags: flags,
        coachId: coach.id,
        language: coach.language == CoachLanguage.es ? 'es' : 'en',
        hasEntitlement: () => EntitlementToken.current != null,
        askConsent: () async {
          final l = context.l10n;
          return showConfirmDialog(context, l.avatarConsentTitle, l.avatarConsentBody(flags.vendorName), l.avatarConsentAgree,
              actionColor: Colors.amber, cancelLabel: l.avatarConsentDecline);
        },
      );
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) _c?.dispose();
    super.dispose();
  }

  String _reason(FallbackReason? r, String none) => r?.name ?? none;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: Text(l.avatarPilotTitle)),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final coach = context.read<AppState>().selectedCoach;
                Widget row(String k, String v) => MergeSemantics(
                      child: ListTile(dense: true, title: Text(k), trailing: Text(v, key: ValueKey('pilot-$k'))),
                    );
                final minutes = c.usedSeconds == null ? '-' : '${(c.usedSeconds! / 60).toStringAsFixed(1)} / ${((c.totalSeconds ?? 0) / 60).round()}';
                return ListView(padding: const EdgeInsets.all(16), children: [
                  if (!(widget.flags ?? AvatarFlags.fromBuild()).hostedEnabled) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(l.avatarPilotOff)),
                  SizedBox(
                    height: 240,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: HostedAvatarView(
                        controller: c,
                        coachName: coach.name,
                        fallback: ColoredBox(color: Colors.black12, child: Center(child: Text(coach.name))),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  row(l.avatarPilotVendor, c.vendor ?? (widget.flags ?? AvatarFlags.fromBuild()).vendorName),
                  row(l.avatarPilotState, c.state.name),
                  row(l.avatarPilotActivity, c.activity.name),
                  row(l.avatarPilotLatency, c.firstFrameMs == null ? '-' : '${c.firstFrameMs} ms'),
                  row('RTT', c.rttMs == null ? '-' : '${c.rttMs} ms'),
                  row(l.avatarPilotMic, c.micState == 'unknown' ? l.avatarPilotMicNotUsed : c.micState),
                  row(l.avatarPilotAllowance, minutes),
                  row(l.avatarPilotFallback, _reason(c.fallbackReason, l.avatarPilotNone)),
                  if (c.lastError != null) row(l.avatarPilotError, c.lastError!),
                  const SizedBox(height: 12),
                  if (_useTone) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l.avatarPilotTone, style: Theme.of(context).textTheme.bodySmall)),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton(key: const ValueKey('pilot-start'), onPressed: c.start, child: Text(l.avatarPilotStart)),
                    FilledButton.tonal(key: const ValueKey('pilot-speak'), onPressed: () => c.speakReply(coach.voiceIntro), child: Text(l.avatarPilotSpeak)),
                    FilledButton.tonal(key: const ValueKey('pilot-interrupt'), onPressed: c.interrupt, child: Text(l.avatarPilotInterrupt)),
                    OutlinedButton(key: const ValueKey('pilot-stop'), onPressed: c.stop, child: Text(l.avatarPilotStop)),
                  ]),
                ]);
              },
            ),
    );
  }
}
