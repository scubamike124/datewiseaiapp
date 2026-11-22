import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tier.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common/user_avatar.dart';

/// Admin-only screen: list every user, see totals, change a user's plan/status,
/// and suspend/re-enable access. All actions are enforced server-side by
/// row-level security (only admins can touch other users' rows).
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late Future<List<AppUser>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AppUser>> _load() => context.read<AppState>().auth.listUsers();

  void _reload() => setState(() => _future = _load());

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFB91C1C) : AppColors.raised,
      ),
    );
  }

  Future<void> _setTierStatus(
    AppUser u,
    SubscriptionTier tier,
    String status,
  ) async {
    try {
      await context.read<AppState>().auth.adminSetTierStatus(
        userId: u.id,
        tier: tier,
        status: status,
      );
      _toast('Updated ${u.email}.');
      _reload();
    } catch (_) {
      _toast('Update failed.', error: true);
    }
  }

  Future<void> _setSuspended(AppUser u, bool suspended) async {
    try {
      await context.read<AppState>().auth.adminSetSuspended(
        userId: u.id,
        suspended: suspended,
      );
      _toast(suspended ? 'Suspended ${u.email}.' : 'Re-enabled ${u.email}.');
      _reload();
    } catch (_) {
      _toast('Action failed.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Manage Users'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<AppUser>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(onRetry: _reload, message: '${snap.error}');
          }
          final all = snap.data ?? [];
          final filtered =
              _query.isEmpty
                  ? all
                  : all.where((u) {
                    final q = _query.toLowerCase();
                    return (u.email ?? '').toLowerCase().contains(q) ||
                        (u.displayName ?? '').toLowerCase().contains(q);
                  }).toList();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _Stats(users: all),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by email or name',
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: Text('No users found.')),
                    )
                  else
                    ...filtered.map(
                      (u) => _UserCard(
                        user: u,
                        onTierStatus: (t, s) => _setTierStatus(u, t, s),
                        onSuspend: (s) => _setSuspended(u, s),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.users});
  final List<AppUser> users;

  @override
  Widget build(BuildContext context) {
    final total = users.length;
    final paid = users.where((u) => u.isPaid).length;
    final suspended = users.where((u) => u.suspended).length;
    return Row(
      children: [
        _StatBox(
          label: 'Total users',
          value: '$total',
          icon: Icons.people_outline,
        ),
        const SizedBox(width: AppSpacing.sm),
        _StatBox(
          label: 'Paid',
          value: '$paid',
          icon: Icons.verified_outlined,
          color: AppColors.primaryLight,
        ),
        const SizedBox(width: AppSpacing.sm),
        _StatBox(
          label: 'Suspended',
          value: '$suspended',
          icon: Icons.block,
          color: AppColors.danger,
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? AppColors.primaryLight;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onTierStatus,
    required this.onSuspend,
  });
  final AppUser user;
  final void Function(SubscriptionTier tier, String status) onTierStatus;
  final void Function(bool suspended) onSuspend;

  static const _statuses = ['pending_payment', 'active', 'canceled'];

  String _statusLabel(String s) => switch (s) {
    'active' => 'Active (paid)',
    'canceled' => 'Canceled',
    _ => 'Pending payment',
  };

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _fmtDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color:
              user.suspended
                  ? AppColors.danger.withValues(alpha: 0.5)
                  : AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                avatarUrl: user.avatarUrl,
                label: user.email ?? user.displayName,
                radius: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.email ?? '(no email)',
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (user.isAdmin) ...[
                          const SizedBox(width: 6),
                          const _MiniBadge(
                            text: 'ADMIN',
                            color: AppColors.primarySoft,
                          ),
                        ],
                        if (user.suspended) ...[
                          const SizedBox(width: 6),
                          const _MiniBadge(
                            text: 'SUSPENDED',
                            color: AppColors.danger,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      [
                        if (user.displayName?.isNotEmpty == true)
                          user.displayName!,
                        if (user.joinedAt != null)
                          'Joined ${_fmtDate(user.joinedAt!)}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Plan
              _LabeledDropdown<SubscriptionTier>(
                label: 'Plan',
                value: user.tier,
                items:
                    SubscriptionTier.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(TierInfo.of(t).name),
                          ),
                        )
                        .toList(),
                onChanged: (t) {
                  if (t != null) onTierStatus(t, user.status);
                },
              ),
              // Status
              _LabeledDropdown<String>(
                label: 'Status',
                value:
                    _statuses.contains(user.status)
                        ? user.status
                        : 'pending_payment',
                items:
                    _statuses
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(_statusLabel(s)),
                          ),
                        )
                        .toList(),
                onChanged: (s) {
                  if (s != null) onTierStatus(user.tier, s);
                },
              ),
              // Suspend toggle
              OutlinedButton.icon(
                onPressed: () => onSuspend(!user.suspended),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      user.suspended ? AppColors.primarySoft : AppColors.danger,
                ),
                icon: Icon(
                  user.suspended ? Icons.lock_open : Icons.block,
                  size: 18,
                ),
                label: Text(user.suspended ? 'Re-enable' : 'Suspend'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          DropdownButton<T>(
            value: value,
            items: items,
            onChanged: onChanged,
            underline: const SizedBox.shrink(),
            isDense: true,
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, required this.message});
  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
            const SizedBox(height: AppSpacing.md),
            const Text(
              "Couldn't load users.",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Make sure the latest schema has been run in Supabase.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
