import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_links.dart';
import '../content/legal_text.dart';
import '../models/coach.dart';
import '../services/store_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dw.dart';
import 'legal_screen.dart';
import 'paywall_screen.dart';
import 'shell.dart';

/// The "You" tab: language, coach, Coach memory, subscription, data, legal.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: AppColors.text))),
          TextButton(
            key: const ValueKey('confirm-action'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _pickLanguage(BuildContext context, AppState state) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in CoachLanguage.values)
              ListTile(
                minTileHeight: 52,
                title: Text(l.label, style: AppText.label),
                subtitle: Text(
                  l == CoachLanguage.en ? 'Coaches: Ava and Ethan' : 'Coaches: Sofía y Diego',
                  style: AppText.small,
                ),
                trailing: state.language == l ? const Icon(Icons.check_rounded, color: AppColors.gold) : null,
                onTap: () {
                  state.setLanguage(l);
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
    final controller = TextEditingController(text: state.memoryText);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Coach memory', style: AppText.name.copyWith(fontSize: 24)),
              const SizedBox(height: 6),
              const Text(
                'A short note your coaches see with each message while Coach memory is on. '
                'Write only what you are happy to share.',
                style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textMuted),
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
                  controller: controller,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: AppState.memoryMaxLength,
                  style: const TextStyle(color: AppColors.text, fontSize: 15, height: 1.4),
                  decoration: const InputDecoration(
                    hintText: 'e.g. I am 31, shy at first, on Hinge, looking for something serious.',
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DwButton(
                key: const ValueKey('memory-save'),
                label: 'Save',
                expand: true,
                onPressed: () {
                  state.saveMemory(controller.text);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final store = context.watch<StoreService>();
    final top = MediaQuery.paddingOf(context).top;
    final memory = state.memoryText;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, top + 16, 16, 28),
      child: ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: LargeTitle(title: 'You')),
            const _SectionLabel('Coaching'),
            _Group(children: [
              _Row(
                key: const ValueKey('row-language'),
                icon: Icons.translate_rounded,
                title: 'Coaching language',
                value: state.language.label,
                onTap: () => _pickLanguage(context, state),
              ),
              _Row(
                key: const ValueKey('row-coach'),
                icon: Icons.people_outline_rounded,
                title: 'Your coach',
                value: state.selectedCoach.name,
                onTap: () => context.read<ShellController>().go(AppTab.coaches),
              ),
            ]),
            const _SectionLabel('Coach memory'),
            _Group(children: [
              _SwitchRow(
                key: const ValueKey('row-memory'),
                icon: Icons.psychology_alt_outlined,
                title: 'Coach memory',
                subtitle: state.memoryEnabled
                    ? 'On: your note below is sent with each message.'
                    : 'Off: coaches only see the current conversation.',
                value: state.memoryEnabled,
                onChanged: state.setMemoryEnabled,
              ),
              _Row(
                key: const ValueKey('row-memory-edit'),
                icon: Icons.edit_note_rounded,
                title: memory.isEmpty ? 'Write your note' : 'Your note',
                subtitle: memory.isEmpty ? null : memory,
                onTap: () => _editMemory(context, state),
              ),
              if (memory.isNotEmpty)
                _Row(
                  key: const ValueKey('row-memory-clear'),
                  icon: Icons.backspace_outlined,
                  title: 'Clear memory',
                  destructive: true,
                  onTap: () async {
                    if (await _confirm(context, 'Clear Coach memory?', 'Your note will be deleted from this device.', 'Clear')) {
                      state.clearMemory();
                    }
                  },
                ),
            ]),
            const _SectionLabel('Subscription'),
            _Group(children: [
              _Row(
                key: const ValueKey('row-sub-status'),
                icon: Icons.workspace_premium_outlined,
                title: StoreConfig.productTitle,
                value: store.isEntitled ? 'Active' : 'Not subscribed',
                onTap: store.isEntitled ? null : () => showPaywall(context),
              ),
              if (store.manageUrl != null)
                _Row(
                  key: const ValueKey('row-manage'),
                  icon: Icons.open_in_new_rounded,
                  title: 'Manage subscription',
                  onTap: () => _open(context, store.manageUrl!),
                ),
              if (store.canPurchase || store is AppStoreService)
                _Row(
                  key: const ValueKey('row-restore'),
                  icon: Icons.restore_rounded,
                  title: 'Restore purchases',
                  onTap: () async {
                    final ok = await store.restore();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? 'DateWise Premium is active.' : 'No active subscription found.'),
                      ));
                    }
                  },
                ),
            ]),
            const _SectionLabel('Your data'),
            _Group(children: [
              _Row(
                key: const ValueKey('row-delete-conversations'),
                icon: Icons.delete_sweep_outlined,
                title: 'Delete all conversations',
                destructive: true,
                onTap: () async {
                  if (await _confirm(context, 'Delete all conversations?',
                      'Every conversation with every coach will be deleted from this device.', 'Delete')) {
                    state.deleteAllConversations();
                  }
                },
              ),
              _Row(
                key: const ValueKey('row-delete-data'),
                icon: Icons.delete_forever_outlined,
                title: 'Delete my data',
                destructive: true,
                onTap: () async {
                  if (await _confirm(
                      context,
                      'Delete all your data?',
                      'Conversations, plan, progress, Coach memory and settings will be erased from this device, '
                          'and the app will start again. Your Apple subscription is not affected.',
                      'Delete everything')) {
                    state.deleteMyData();
                  }
                },
              ),
            ]),
            const _SectionLabel('About'),
            _Group(children: [
              _Row(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const LegalScreen(title: 'Privacy Policy', content: kPrivacyPolicy),
                )),
              ),
              _Row(
                icon: Icons.description_outlined,
                title: 'Terms of Use',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const LegalScreen(title: 'Terms of Use', content: kTermsOfService),
                )),
              ),
              _Row(
                icon: Icons.mail_outline_rounded,
                title: 'Support',
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
                  'Your coaches are AI. Conversations are stored on this device.${v.isEmpty ? '' : '\nDateWise AI $v'}',
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
