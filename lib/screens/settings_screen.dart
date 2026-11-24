import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_links.dart';
import '../avatar/hosted/avatar_flags.dart';
import '../avatar/hosted/pilot_debug_screen.dart';
import '../dev/entitlement_export.dart';
import '../models/coach.dart';
import '../services/ai_config.dart';
import '../services/store_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/store_status_sheet.dart';
import '../widgets/dw.dart';
import 'get_help_screen.dart';
import 'legal_screen.dart';
import 'paywall_screen.dart';
import 'shell.dart';
import '../avatar/premium_voice_tip.dart';
import '../l10n/l10n.dart';

/// The "You" tab: language, coach, Coach memory, subscription, data, legal.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<bool> _confirm(BuildContext context, String title, String body, String action) =>
      showConfirmDialog(context, title, body, action);

  void _pickLanguage(BuildContext context, AppState state) {
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        // Scrolls at large text, where the title and both options are taller
        // than the sheet.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Semantics(
                  header: true,
                  child: Text(l.languageRow,
                      key: const ValueKey('language-sheet-title'), style: AppText.name.copyWith(fontSize: 22)),
                ),
              ),
              for (final lang in CoachLanguage.values)
                ListTile(
                  key: ValueKey('language-${lang.name}'),
                  minTileHeight: 52,
                  title: Text(lang.label, style: AppText.label),
                  subtitle: Text(l.coachesFor(lang), style: AppText.small),
                  trailing: state.language == lang ? const Icon(Icons.check_rounded, color: AppColors.gold) : null,
                  selected: state.language == lang,
                  onTap: () {
                    state.setLanguage(lang);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _editMemory(BuildContext context, AppState state) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _MemorySheet(state: state),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.couldNotOpen(url))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final store = context.watch<StoreService>();
    final top = MediaQuery.paddingOf(context).top;
    final memory = state.memoryText;
    final l = context.l10n;

    return StatusBarScrim(
      child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, top + 16, 16, 28),
      child: ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: LargeTitle(title: l.youTitle)),
            _SectionLabel(l.sectionCoaching),
            _Group(children: [
              _Row(
                key: const ValueKey('row-language'),
                icon: Icons.translate_rounded,
                title: l.languageRow,
                value: state.language.label,
                onTap: () => _pickLanguage(context, state),
              ),
              _Row(
                key: const ValueKey('row-coach'),
                icon: Icons.people_outline_rounded,
                title: l.yourCoachRow,
                value: state.selectedCoach.name,
                onTap: () => context.read<ShellController>().go(AppTab.coaches),
              ),
              _Row(
                key: const ValueKey('row-voice-quality'),
                icon: Icons.record_voice_over_outlined,
                title: l.voiceQualityRow,
                onTap: () => showPremiumVoiceTip(context),
              ),
            ]),
            _SectionLabel(l.sectionMemory),
            _Group(children: [
              _SwitchRow(
                key: const ValueKey('row-memory'),
                icon: Icons.psychology_alt_outlined,
                title: l.memoryTitle,
                subtitle: state.memoryEnabled ? l.memoryOn : l.memoryOff,
                value: state.memoryEnabled,
                onChanged: (on) async {
                  // Turning memory off deletes the note: confirm first.
                  if (!on &&
                      state.memoryText.isNotEmpty &&
                      !await _confirm(context, l.memoryOffTitle, l.memoryOffBody, l.memoryOffAction)) {
                    return;
                  }
                  await state.setMemoryEnabled(on);
                },
              ),
              _Row(
                key: const ValueKey('row-memory-edit'),
                icon: Icons.edit_note_rounded,
                title: memory.isEmpty ? l.writeNote : l.yourNote,
                subtitle: memory.isEmpty ? null : memory,
                onTap: () => _editMemory(context, state),
              ),
              if (memory.isNotEmpty)
                _Row(
                  key: const ValueKey('row-memory-clear'),
                  icon: Icons.backspace_outlined,
                  title: l.clearMemory,
                  destructive: true,
                  onTap: () async {
                    if (await _confirm(context, l.clearMemoryTitle, l.clearMemoryBody, l.clear)) {
                      state.clearMemory();
                    }
                  },
                ),
            ]),
            _SectionLabel(l.sectionSubscription),
            _Group(children: [
              _Row(
                key: const ValueKey('row-sub-status'),
                icon: Icons.workspace_premium_outlined,
                title: StoreConfig.productTitle,
                value: store.isEntitled ? l.subActive : l.subNone,
                onTap: store.isEntitled ? null : () => showPaywall(context),
              ),
              if (store.manageUrl != null)
                _Row(
                  key: const ValueKey('row-manage'),
                  icon: Icons.open_in_new_rounded,
                  title: l.manageSubscription,
                  onTap: () => _open(context, store.manageUrl!),
                ),
              if (store.canPurchase || store is AppStoreService)
                _Row(
                  key: const ValueKey('row-restore'),
                  icon: Icons.restore_rounded,
                  title: l.restorePurchasesRow,
                  // As on the paywall: a store or network failure says so,
                  // only a completed restore with nothing found says "none".
                  onTap: () async {
                    final ok = await store.restore();
                    // A canceled Apple Account prompt is not an error.
                    if (context.mounted && (ok || !store.lastRestoreCanceled)) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        key: const ValueKey('restore-result'),
                        content: Text(ok ? l.restoreOk : restoreFailureText(l, store.lastError, l.restoreNone)),
                      ));
                    }
                  },
                ),
            ]),
            _SectionLabel(l.sectionPrivacy),
            _Group(children: [
              _SwitchRow(
                key: const ValueKey('row-ai-sharing'),
                icon: Icons.cloud_outlined,
                title: l.aiSharingTitle,
                subtitle: state.aiConsentGiven ? l.aiSharingOn : l.aiSharingOff,
                value: state.aiConsentGiven,
                onChanged: (on) async {
                  if (!on) {
                    // Withdraws only the permission; every conversation stays (Guideline 5.1.1(ii)).
                    await state.revokeAiConsent();
                    return;
                  }
                  // Turning it on is the same informed agreement as in the chat.
                  if (await showConfirmDialog(context, l.aiConsentTitle, l.aiConsentBody, l.aiConsentAgree,
                      actionColor: AppColors.gold, cancelLabel: l.aiConsentNotNow)) {
                    await state.giveAiConsent();
                  }
                },
              ),
            ]),
            _SectionLabel(l.sectionSafety),
            _Group(children: [
              _Row(
                key: const ValueKey('row-get-help'),
                icon: Icons.health_and_safety_outlined,
                title: l.getHelpNow,
                subtitle: l.getHelpSubtitle,
                onTap: () => Navigator.of(context).push(GetHelpScreen.route(firstCountry: state.deviceCountry)),
              ),
            ]),
            _SectionLabel(l.sectionData),
            _Group(children: [
              _Row(
                key: const ValueKey('row-delete-conversations'),
                icon: Icons.delete_sweep_outlined,
                title: l.deleteAllConversations,
                destructive: true,
                onTap: () async {
                  if (await _confirm(context, l.deleteAllConversationsTitle, l.deleteAllConversationsBody, l.delete)) {
                    // A pending "Conversation deleted · Undo" goes too.
                    if (context.mounted) ScaffoldMessenger.of(context).clearSnackBars();
                    state.deleteAllConversations();
                  }
                },
              ),
              _Row(
                key: const ValueKey('row-delete-data'),
                icon: Icons.delete_forever_outlined,
                title: l.deleteMyData,
                subtitle: l.deleteMyDataNote,
                subtitleMaxLines: null,
                destructive: true,
                onTap: () async {
                  if (await _confirm(context, l.deleteMyDataTitle, l.deleteMyDataBody, l.deleteEverything)) {
                    // A pending "Conversation deleted · Undo" goes too.
                    if (context.mounted) ScaffoldMessenger.of(context).clearSnackBars();
                    state.deleteMyData();
                  }
                },
              ),
            ]),
            _SectionLabel(l.sectionAbout),
            _Group(children: [
              _Row(
                icon: Icons.privacy_tip_outlined,
                key: const ValueKey('row-privacy'),
                title: l.privacyPolicy,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const LegalScreen.doc(LegalDoc.privacy),
                )),
              ),
              _Row(
                icon: Icons.description_outlined,
                key: const ValueKey('row-terms'),
                title: l.termsOfUse,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const LegalScreen.doc(LegalDoc.terms),
                )),
              ),
              _Row(
                icon: Icons.mail_outline_rounded,
                title: l.support,
                // The address as a subtitle, so it is never truncated and
                // never squeezes the label at large text.
                subtitle: AppLinks.supportEmail,
                subtitleOneLine: true,
                onTap: () => _open(context, 'mailto:${AppLinks.supportEmail}'),
              ),
            ]),
            // Debug builds only (kDebugMode is a compile-time constant, so release
            // builds, TestFlight included, never contain this row): see lib/dev/entitlement_export.dart.
            if (kDebugMode && DevEntitlementExport.enabled) ...[
              const _SectionLabel('Developer'),
              const _Group(children: [DevEntitlementRow()]),
            ],
            // Hosted-avatar pilot (docs/avatar/PILOT_RUNBOOK.md): only with the AVATAR_HOSTED
            // flag AND a debug build or a TestFlight build on a non-production coach server.
            if (AvatarFlags.fromBuild().pilotScreenAvailable(testBuild: AIConfig.testBuildHost() != null)) ...[
              _SectionLabel(l.avatarPilotTitle),
              _Group(children: [
                _Row(
                  icon: Icons.face_retouching_natural,
                  key: const ValueKey('row-avatar-pilot'),
                  title: l.avatarPilotOpen,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PilotDebugScreen())),
                ),
              ]),
            ],
            const SizedBox(height: 18),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform().catchError((Object _) => PackageInfo(appName: '', packageName: '', version: '', buildNumber: '')),
              builder: (_, snap) {
                final v = snap.data?.version ?? '';
                // Test builds against a non-production coach backend name it,
                // so a TestFlight tester can confirm the build (not localized:
                // App Store builds never show it).
                final host = AIConfig.testBuildHost();
                // Long-press: the hidden "Store status" readout (what StoreKit
                // returned for the subscription product), for TestFlight.
                return GestureDetector(
                  key: const ValueKey('settings-footnote'),
                  onLongPress: () => showStoreStatus(context),
                  child: Text(
                    '${l.settingsFootnote}${v.isEmpty ? '' : '\n${l.appVersion(v)}'}'
                    '${host == null ? '' : '\nTest build · coach server: $host'}',
                    textAlign: TextAlign.center,
                    style: AppText.small,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
        child: Text(text.toUpperCase(), style: AppText.eyebrow.copyWith(color: AppColors.faint, fontSize: 12)),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 52),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.subtitle,
    this.subtitleMaxLines = 3,
    this.subtitleOneLine = false,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? value;
  final String? subtitle;

  /// Null shows the whole subtitle (notes that must not be cut off).
  final int? subtitleMaxLines;

  /// Keeps the subtitle on one line, shrinking it to fit if needed, so a
  /// value such as an email address never breaks at its dot.
  final bool subtitleOneLine;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.text;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 22, color: destructive ? AppColors.danger : AppColors.gold),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Whole words at large text: "Language" never breaks as "Languag / e" (QA m-2).
                    WholeWordsText(title, style: TextStyle(fontSize: 15.5, color: color, height: 1.3)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: subtitleOneLine
                            ? FittedBox(
                                key: const ValueKey('row-subtitle-fitted'),
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(subtitle!,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.textMuted)),
                              )
                            : Text(subtitle!,
                                maxLines: subtitleMaxLines,
                                overflow: subtitleMaxLines == null ? null : TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.textMuted)),
                      ),
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(value!, textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, color: AppColors.textMuted)),
                ),
              ],
              if (onTap != null && !destructive) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: AppColors.faint, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.gold),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WholeWordsText(title, style: const TextStyle(fontSize: 15.5, color: AppColors.text, height: 1.3)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Coach memory editor. Owns (and disposes) its text controller.
class _MemorySheet extends StatefulWidget {
  const _MemorySheet({required this.state});
  final AppState state;

  @override
  State<_MemorySheet> createState() => _MemorySheetState();
}

class _MemorySheetState extends State<_MemorySheet> {
  late final _controller = TextEditingController(text: widget.state.memoryText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.memoryTitle, style: AppText.name.copyWith(fontSize: 24)),
              const SizedBox(height: 6),
              Text(
                l.memorySheetBody,
                style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.line2),
                ),
                child: TextField(
                  key: const ValueKey('memory-field'),
                  controller: _controller,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: AppState.memoryMaxLength,
                  style: const TextStyle(color: AppColors.text, fontSize: 15, height: 1.4),
                  decoration: InputDecoration(
                    hintText: l.memoryHint,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DwButton(
                key: const ValueKey('memory-save'),
                label: l.save,
                expand: true,
                onPressed: () async {
                  final state = widget.state;
                  final text = _controller.text;
                  // A note is kept only while Coach memory is on: saving one
                  // while it is off asks to turn it on first.
                  if (!state.memoryEnabled && text.trim().isNotEmpty) {
                    if (!await showConfirmDialog(context, l.memoryTurnOnTitle, l.memoryTurnOnBody, l.memoryTurnOnAction,
                        actionColor: AppColors.text)) {
                      return;
                    }
                    await state.setMemoryEnabled(true);
                  }
                  await state.saveMemory(text);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      );
  }
}
