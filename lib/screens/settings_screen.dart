import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_links.dart';
import '../models/coach.dart';
import '../services/store_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dw.dart';
import 'legal_screen.dart';
import 'paywall_screen.dart';
import 'shell.dart';
import '../l10n/l10n.dart';

/// A confirmation dialog whose body scrolls, so long text at large sizes is
/// never clipped. True when the user chose [action].
Future<bool> _confirmDialog(BuildContext context, String title, String body, String action,
    {Color actionColor = AppColors.danger}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel, style: const TextStyle(color: AppColors.text))),
        TextButton(
          key: const ValueKey('confirm-action'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action, style: TextStyle(color: actionColor, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// The "You" tab: language, coach, Coach memory, subscription, data, legal.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<bool> _confirm(BuildContext context, String title, String body, String action) =>
      _confirmDialog(context, title, body, action);

  void _pickLanguage(BuildContext context, AppState state) {
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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

    return SingleChildScrollView(
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
                  onTap: () async {
                    final ok = await store.restore();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? l.restoreOk : l.restoreNone),
                      ));
                    }
                  },
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
                    state.deleteAllConversations();
                  }
                },
              ),
              _Row(
                key: const ValueKey('row-delete-data'),
                icon: Icons.delete_forever_outlined,
                title: l.deleteMyData,
                subtitle: l.deleteMyDataNote,
                destructive: true,
                onTap: () async {
                  if (await _confirm(context, l.deleteMyDataTitle, l.deleteMyDataBody, l.deleteEverything)) {
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
                value: AppLinks.supportEmail,
                onTap: () => _open(context, 'mailto:${AppLinks.supportEmail}'),
              ),
            ]),
            const SizedBox(height: 18),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform().catchError((Object _) => PackageInfo(appName: '', packageName: '', version: '', buildNumber: '')),
              builder: (_, snap) {
                final v = snap.data?.version ?? '';
                return Text(
                  '${l.settingsFootnote}${v.isEmpty ? '' : '\n${l.appVersion(v)}'}',
                  textAlign: TextAlign.center,
                  style: AppText.small,
                );
              },
            ),
          ],
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
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? value;
  final String? subtitle;
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
                    Text(title, style: TextStyle(fontSize: 15.5, color: color, height: 1.3)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, maxLines: 3, overflow: TextOverflow.ellipsis,
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
                    Text(title, style: const TextStyle(fontSize: 15.5, color: AppColors.text, height: 1.3)),
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
                    if (!await _confirmDialog(context, l.memoryTurnOnTitle, l.memoryTurnOnBody, l.memoryTurnOnAction,
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
