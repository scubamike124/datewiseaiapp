import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_flags.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common/premium.dart';
import '../widgets/common/user_avatar.dart';
import 'admin_users_screen.dart';
import 'settings_screen.dart';

/// Account screen for any signed-in user: edit display name, change password,
/// see the current plan, and (for admins) jump to Manage Users.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.onChangePlan, this.embedded = false});

  /// When set, the "Change plan" action calls this instead of popping the
  /// route — used when the screen is hosted inside a tab (see HomeShell).
  final VoidCallback? onChangePlan;

  /// True when rendered as a tab (not a pushed route): suppresses pop-based
  /// navigation after sign-out so it doesn't tear down the host shell.
  final bool embedded;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _savingName = false;
  bool _savingPassword = false;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _name.text = context.read<AppState>().displayName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFB91C1C) : AppColors.raised,
      ),
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    final state = context.read<AppState>();
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await file.readAsBytes();
      final ext = _extFor(file.name, file.mimeType);
      await state.auth.uploadAvatar(bytes: bytes, fileExt: ext);
      await state.refreshProfile();
      _toast('Profile picture updated.');
    } catch (_) {
      _toast('Could not upload picture.', error: true);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  /// Picks a safe image extension from the file name or mime type.
  String _extFor(String name, String? mime) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png') || mime == 'image/png') return 'png';
    if (lower.endsWith('.webp') || mime == 'image/webp') return 'webp';
    return 'jpg';
  }

  Future<void> _saveName() async {
    setState(() => _savingName = true);
    final state = context.read<AppState>();
    try {
      await state.auth.updateDisplayName(_name.text);
      await state.refreshProfile();
      _toast('Name updated.');
    } catch (_) {
      _toast('Could not update name.', error: true);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _savePassword() async {
    if (_password.text.length < 6) {
      _toast('Password must be at least 6 characters.', error: true);
      return;
    }
    setState(() => _savingPassword = true);
    try {
      await context.read<AppState>().auth.updatePassword(_password.text);
      _password.clear();
      _toast('Password changed.');
    } catch (_) {
      _toast('Could not change password.', error: true);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final tierInfo = state.tierInfo;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Account'),
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Identity header
                GlassCard(
                  glowColor: AppColors.primary,
                  child: Row(
                    children: [
                      _EditableAvatar(
                        avatarUrl: state.avatarUrl,
                        label: state.userEmail,
                        uploading: _uploadingAvatar,
                        onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.displayName?.isNotEmpty == true
                                  ? state.displayName!
                                  : 'DateWise member',
                              style: theme.textTheme.titleLarge,
                            ),
                            Text(
                              state.userEmail ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (state.isAdmin) _RoleChip(label: 'ADMIN'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Current plan — hidden during the free launch (everything is
                // unlocked, so there is no plan to show or change).
                if (!AppFlags.freeLaunch) ...[
                  _Card(
                    child: Row(
                      children: [
                        Icon(
                          Icons.workspace_premium_outlined,
                          color: tierInfo.accentColor,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Current plan',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                              Text(
                                tierInfo.name,
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed:
                              widget.onChangePlan ??
                              () => Navigator.of(context).pop(),
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Edit name
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Display name', style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.person_outline),
                          hintText: 'Your name',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GradientButton(
                          dense: true,
                          busy: _savingName,
                          onPressed: _savingName ? null : _saveName,
                          label: 'Save name',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Change password
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Change password',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.lock_outline),
                          hintText: 'New password (min 6 chars)',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GradientButton(
                          dense: true,
                          busy: _savingPassword,
                          onPressed: _savingPassword ? null : _savePassword,
                          label: 'Update password',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Admin entry
                if (state.isAdmin)
                  _Card(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: AppColors.primarySoft,
                      ),
                      title: const Text('Manage users'),
                      subtitle: const Text(
                        'View all users, change plans, suspend access',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AdminUsersScreen(),
                            ),
                          ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),

                // Sign out
                OutlinedButton.icon(
                  onPressed: () async {
                    await context.read<AppState>().signOut();
                    // When embedded as a tab there's nothing to pop — the tab
                    // rebuilds to the signed-out state automatically.
                    if (!widget.embedded && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar with a camera badge that lets the user pick a new picture.
class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({
    required this.avatarUrl,
    required this.label,
    required this.uploading,
    required this.onTap,
  });
  final String? avatarUrl;
  final String? label;
  final bool uploading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            UserAvatar(avatarUrl: avatarUrl, label: label, radius: 32),
            if (uploading)
              const Positioned.fill(
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.black38,
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: AppColors.romanticGradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: const Icon(
                  Icons.photo_camera_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassCard(radius: AppRadius.md, child: child);
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primarySoft,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}
