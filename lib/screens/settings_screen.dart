import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_flags.dart';
import '../app_links.dart';
import '../content/legal_text.dart';
import '../services/purchase_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common/premium.dart';
import 'legal_screen.dart';

/// App settings: subscription management, legal documents, support, app info,
/// and the account-deletion / log-out actions.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  static const PurchaseService _purchases = MockPurchaseService();

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = 'v${info.version} (${info.buildNumber})');
    } catch (_) {
      // Leave blank if unavailable.
    }
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

  Future<void> _open(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) _toast('Could not open the link.', error: true);
  }

  Future<void> _emailSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppLinks.supportEmail,
      query: 'subject=${Uri.encodeComponent('DateWise AI support')}',
    );
    if (!await launchUrl(uri)) {
      _toast(
        'No email app found. Write to ${AppLinks.supportEmail}.',
        error: true,
      );
    }
  }

  void _openLegal(String title, String content) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalScreen(title: title, content: content),
      ),
    );
  }

  Future<void> _restore() async {
    await _purchases.restore();
    _toast('No purchases to restore yet.');
  }

  Future<void> _confirmDelete() async {
    final state = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete account?'),
            content: const Text(
              'This removes your data from this device and requests deletion of your '
              'account records. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await state.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pop(); // close settings
      _toast('Account deletion requested and local data cleared.');
    } catch (_) {
      _toast(
        'Could not complete deletion. Please contact support.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final signedIn = state.authEnabled && state.isSignedIn;

    // "Rate the app" must open the correct store per platform. Hidden until a
    // listing exists for the current platform (so iOS never opens Google Play).
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final storeUrl = isIOS ? AppLinks.appStoreUrl : AppLinks.playStoreUrl;
    final hasStoreListing =
        isIOS
            ? AppLinks.iosAppStoreId.isNotEmpty
            : AppLinks.androidPackage.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            children: [
              // Billing actions are hidden during the free launch (no subscriptions
              // exist). They return — and become store-aware — in the paid update.
              if (!AppFlags.freeLaunch) ...[
                _section('Subscription'),
                _group([
                  _tile(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Manage subscription',
                    subtitle: 'Change or cancel via Google Play',
                    onTap: () => _open(AppLinks.manageSubscriptionsUrl),
                  ),
                  _tile(
                    icon: Icons.restore_rounded,
                    title: 'Restore purchases',
                    onTap: _restore,
                  ),
                ]),
              ],

              _section('Legal'),
              _group([
                _tile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () => _openLegal('Privacy Policy', kPrivacyPolicy),
                ),
                _tile(
                  icon: Icons.description_outlined,
                  title: 'Terms of Service',
                  onTap: () => _openLegal('Terms of Service', kTermsOfService),
                ),
                _tile(
                  icon: Icons.gpp_maybe_outlined,
                  title: 'Disclaimer',
                  onTap: () => _openLegal('Disclaimer', kDisclaimer),
                ),
              ]),

              _section('Support'),
              _group([
                _tile(
                  icon: Icons.mail_outline_rounded,
                  title: 'Contact support',
                  subtitle: AppLinks.supportEmail,
                  onTap: _emailSupport,
                ),
                if (hasStoreListing)
                  _tile(
                    icon: Icons.star_outline_rounded,
                    title: 'Rate the app',
                    onTap: () => _open(storeUrl),
                  ),
              ]),

              _section('About'),
              _group([
                _tile(
                  icon: Icons.info_outline_rounded,
                  title: 'App version',
                  trailing: Text(
                    _version,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
                _tile(
                  icon: Icons.article_outlined,
                  title: 'Open-source licenses',
                  onTap:
                      () => showLicensePage(
                        context: context,
                        applicationName: 'DateWise AI',
                        applicationVersion: _version,
                      ),
                ),
              ]),

              _section('Account'),
              _group([
                _tile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete account',
                  danger: true,
                  onTap: _confirmDelete,
                ),
                if (signedIn)
                  _tile(
                    icon: Icons.logout_rounded,
                    title: 'Log out',
                    onTap: () async {
                      final nav = Navigator.of(context);
                      await context.read<AppState>().signOut();
                      if (mounted) nav.pop();
                    },
                  ),
              ]),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xs,
      AppSpacing.lg,
      AppSpacing.xs,
      AppSpacing.sm,
    ),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textMuted,
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final color = danger ? AppColors.danger : AppColors.text;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (danger ? AppColors.danger : AppColors.primary).withValues(
            alpha: 0.14,
          ),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(
          icon,
          size: 20,
          color: danger ? AppColors.danger : AppColors.primarySoft,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
      subtitle:
          subtitle == null
              ? null
              : Text(
                subtitle,
                style: const TextStyle(color: AppColors.textMuted),
              ),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textMuted,
              )),
      onTap: onTap,
    );
  }

  /// A rounded glass group of tiles separated by hairlines.
  Widget _group(List<Widget> tiles) => GlassCard(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    radius: AppRadius.md,
    child: Column(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0)
            const Divider(height: 1, indent: 68, color: AppColors.cardBorder),
          tiles[i],
        ],
      ],
    ),
  );
}
