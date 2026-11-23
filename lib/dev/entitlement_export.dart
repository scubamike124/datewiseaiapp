import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/coach_usage.dart';

/// Developer action for the live AI test kit (`tool/live/live_chat_test.mjs`,
/// see docs/qa/LIVE_AI_TEST_PLAN.md): copies [EntitlementToken.current], the
/// StoreKit 2 signed transaction the coach backend verifies, so a tester can
/// export it as `DW_TEST_JWS`.
///
/// Only in a debug build started with `--dart-define=DW_DEV_TOOLS=true`, never
/// on the web (no StoreKit there). Release builds, TestFlight and the App Store
/// included, cannot show it: [kDebugMode] is a compile-time constant, and the
/// call site in settings_screen.dart checks it first, so the compiler removes
/// the row and this class from release builds. The text is English only on
/// purpose: it is not part of the app's UI.
class DevEntitlementExport {
  DevEntitlementExport._();

  static const bool _flag = bool.fromEnvironment('DW_DEV_TOOLS');

  /// Tests only: shows the row without the dart-define (still debug builds only).
  @visibleForTesting
  static bool? debugForceEnabled;

  static bool get enabled => kDebugMode && !kIsWeb && (debugForceEnabled ?? _flag);

  /// Non-identifying fields of the token (environment, product, expiry), or
  /// null when it is not a readable JWS. The transaction ids are left out.
  static String? describe(String jws) {
    try {
      final part = jws.split('.')[1];
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part)))) as Map<String, dynamic>;
      final expires = payload['expiresDate'];
      final when = expires is num ? DateTime.fromMillisecondsSinceEpoch(expires.toInt(), isUtc: true).toIso8601String() : '?';
      return '${payload['environment'] ?? '?'} · ${payload['productId'] ?? '?'} · expires $when';
    } catch (_) {
      return null;
    }
  }
}

/// The "Copy entitlement token" row (debug builds only, see [DevEntitlementExport]).
class DevEntitlementRow extends StatelessWidget {
  const DevEntitlementRow({super.key});

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final jws = EntitlementToken.current;
    if (jws == null) {
      messenger.showSnackBar(const SnackBar(content: Text('No entitlement token: subscribe or restore first (iOS only).')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy entitlement token?'),
        content: Text(
          '${DevEntitlementExport.describe(jws) ?? 'Unreadable token'}\n\n'
          "Anyone with this token can use this subscription's coach messages until it expires. "
          'Paste it only into DW_TEST_JWS on your own machine, then clear the clipboard.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Copy')),
        ],
      ),
    );
    if (ok != true) return;
    await Clipboard.setData(ClipboardData(text: jws));
    messenger.showSnackBar(const SnackBar(content: Text('Entitlement token copied.')));
  }

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: const ValueKey('row-dev-copy-entitlement'),
          leading: const Icon(Icons.developer_mode_rounded),
          title: const Text('Developer: copy entitlement token'),
          subtitle: const Text('Debug build only. For the live AI test kit.'),
          onTap: () => _copy(context),
        ),
      );
}
