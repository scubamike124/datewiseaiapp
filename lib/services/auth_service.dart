import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tier.dart';
import 'supabase_config.dart';

/// Thin wrapper around Supabase Auth + the subscription table.
///
/// Every method is a safe no-op when [SupabaseConfig.isConfigured] is false, so
/// the rest of the app can call into it unconditionally and the app still runs
/// in its original no-account mode when no backend is set up.
class AuthService {
  /// Initialise Supabase once at startup. No-op when unconfigured.
  static Future<void> initialize() async {
    if (!SupabaseConfig.isConfigured) return;
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  bool get isConfigured => SupabaseConfig.isConfigured;

  SupabaseClient? get _client {
    if (!isConfigured) return null;
    // `initialize()` always runs before the app builds, but guard anyway so we
    // degrade to no-account mode (instead of crashing) if Supabase isn't ready
    // yet — e.g. in widget tests that construct AppState without initializing.
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  User? get currentUser => _client?.auth.currentUser;
  bool get isSignedIn => currentUser != null;
  String? get email => currentUser?.email;

  /// Emits whenever the user signs in or out. Null when unconfigured.
  Stream<AuthState>? get onAuthStateChange =>
      _client?.auth.onAuthStateChange;

  /// Creates an account. Returns true if a session is active immediately;
  /// false means the project requires email confirmation first.
  Future<bool> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final res = await _client!.auth.signUp(
      email: email.trim(),
      password: password,
      data: {if (displayName != null) 'display_name': displayName.trim()},
    );
    return res.session != null;
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client!.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
  }

  /// Records the user's chosen plan. Pre-payment this is 'pending_payment';
  /// a trusted server flips it to 'active' once real billing is wired up.
  ///
  /// Non-fatal: if the table isn't set up yet or the network fails, the app
  /// keeps working (the choice is still saved locally).
  Future<void> saveSelectedTier(SubscriptionTier tier) async {
    final user = currentUser;
    if (user == null) return;
    try {
      await _client!.from('subscriptions').upsert({
        'user_id': user.id,
        'tier': tier.name,
        'status': 'pending_payment',
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('saveSelectedTier failed (non-fatal): $e');
    }
  }

  /// Loads the user's saved plan from the database, if any. Non-fatal.
  Future<SubscriptionTier?> loadSelectedTier() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      final row = await _client!
          .from('subscriptions')
          .select('tier')
          .eq('user_id', user.id)
          .maybeSingle();
      if (row == null) return null;
      return SubscriptionTier.fromId(row['tier'] as String?);
    } catch (e) {
      debugPrint('loadSelectedTier failed (non-fatal): $e');
      return null;
    }
  }

  // --- Current user's profile (role / suspended / name) -------------------

  /// Loads the signed-in user's own profile row. Non-fatal (returns null).
  Future<AppUser?> loadMyProfile() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      final row = await _client!
          .from('profiles')
          .select('id, email, display_name, avatar_url, role, suspended')
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return null;
      return AppUser.fromRow(row);
    } catch (e) {
      debugPrint('loadMyProfile failed (non-fatal): $e');
      return null;
    }
  }

  /// Updates the signed-in user's display name.
  Future<void> updateDisplayName(String name) async {
    final user = currentUser;
    if (user == null) return;
    await _client!
        .from('profiles')
        .update({'display_name': name.trim()}).eq('id', user.id);
  }

  /// Uploads a new profile picture to the 'avatars' bucket, saves its URL on
  /// the user's profile, and returns the public URL (cache-busted).
  Future<String?> uploadAvatar({
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final user = currentUser;
    if (user == null) return null;
    final ext = fileExt.replaceAll('.', '').toLowerCase();
    final path = '${user.id}/avatar.$ext';
    final storage = _client!.storage.from('avatars');
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
    );
    final publicUrl = storage.getPublicUrl(path);
    // Cache-bust so the new image shows immediately (same path is overwritten).
    final busted = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    await _client!
        .from('profiles')
        .update({'avatar_url': busted}).eq('id', user.id);
    return busted;
  }

  /// Changes the signed-in user's password.
  Future<void> updatePassword(String newPassword) async {
    await _client!.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Requests account deletion: removes the records this client is allowed to
  /// delete (the user's own subscription row), best-effort flags the profile as
  /// `deletion_requested`, then signs out. Final removal of the auth user is
  /// completed server-side (Supabase dashboard or an Edge Function), since the
  /// public anon key can't delete auth users.
  Future<void> requestAccountDeletion() async {
    final user = currentUser;
    if (user == null) return;
    // Best-effort flag (no-op if the column doesn't exist yet).
    try {
      await _client!
          .from('profiles')
          .update({'deletion_requested': true}).eq('id', user.id);
    } catch (e) {
      debugPrint('mark deletion_requested failed (non-fatal): $e');
    }
    // Remove the user's subscription record (RLS allows deleting your own).
    try {
      await _client!.from('subscriptions').delete().eq('user_id', user.id);
    } catch (e) {
      debugPrint('delete subscription failed (non-fatal): $e');
    }
    await signOut();
  }

  // --- Admin-only operations (enforced by row-level security) -------------

  /// Lists every user with their plan + status. Returns only the caller's own
  /// row for non-admins (RLS), the full list for admins.
  Future<List<AppUser>> listUsers() async {
    final rows = await _client!
        .from('admin_user_overview')
        .select()
        .order('joined_at', ascending: false);
    return (rows as List)
        .map((r) => AppUser.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Admin: set a user's plan tier and subscription status.
  Future<void> adminSetTierStatus({
    required String userId,
    required SubscriptionTier tier,
    required String status,
  }) async {
    await _client!.from('subscriptions').upsert({
      'user_id': userId,
      'tier': tier.name,
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Admin: suspend or re-enable a user.
  Future<void> adminSetSuspended({
    required String userId,
    required bool suspended,
  }) async {
    await _client!
        .from('profiles')
        .update({'suspended': suspended}).eq('id', userId);
  }
}

/// A user as seen by the account/admin screens. Tolerant of partial rows
/// (the `admin_user_overview` view and the `profiles` table share fields).
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.avatarUrl,
    required this.role,
    required this.suspended,
    required this.tier,
    required this.status,
    this.joinedAt,
  });

  final String id;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final String role; // 'user' | 'admin'
  final bool suspended;
  final SubscriptionTier tier;
  final String status; // 'pending_payment' | 'active' | 'canceled'
  final DateTime? joinedAt;

  bool get isAdmin => role == 'admin';
  bool get isPaid => status == 'active';

  factory AppUser.fromRow(Map<String, dynamic> r) {
    return AppUser(
      id: r['id'] as String,
      email: r['email'] as String?,
      displayName: r['display_name'] as String?,
      avatarUrl: r['avatar_url'] as String?,
      role: (r['role'] as String?) ?? 'user',
      suspended: (r['suspended'] as bool?) ?? false,
      tier: SubscriptionTier.fromId(r['tier'] as String?),
      status: (r['status'] as String?) ?? 'pending_payment',
      joinedAt: r['joined_at'] != null
          ? DateTime.tryParse(r['joined_at'].toString())
          : null,
    );
  }
}
