import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/owner_access.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';

/// The hidden "Store status" readout: what StoreKit returned for the product
/// query, so the owner can see on a TestFlight phone why the paywall has no
/// price. Opened by a long-press on the paywall's plan card or on the version
/// line under You › About; normal users never see it. It shows no secrets (no
/// transaction, receipt or JWS) and changes nothing: "Query again" only
/// re-runs the product query.
///
/// Shown in the UI language (English or Spanish). Copy copies the English
/// readout, so support always gets the same labels.
Future<void> showStoreStatus(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const StoreStatusSheet(),
  );
}

class StoreStatusSheet extends StatelessWidget {
  const StoreStatusSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final l = context.l10n;
    final d = store.diagnostics;
    final words = StoreStatusWords(
      notYet: l.storeStatusNotYet,
      unknown: l.storeStatusUnknown,
      notApplicable: l.storeStatusNotApplicable,
      unavailable: l.storeStatusUnavailable,
      yes: l.storeStatusYes,
      no: l.storeStatusNo,
    );
    final rows = d != null
        ? [for (final (f, v) in d.entries(words)) (storeStatusLabel(l, f), v)]
        : [(l.storeStatusStore, l.storeStatusNoStoreKit('${store.runtimeType}'))];
    final text = d?.toString() ?? 'Store: ${store.runtimeType} (no StoreKit in this build)';
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('store-status'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(l.storeStatusTitle, style: AppText.name.copyWith(fontSize: 22)),
            ),
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$label: ', style: const TextStyle(color: AppColors.textMuted)),
                    TextSpan(text: value, style: const TextStyle(color: AppColors.text)),
                  ]),
                  style: const TextStyle(fontSize: 13.5, height: 1.35),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('store-status-copy'),
                  onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                  child: Text(l.storeStatusCopy),
                ),
                // Hidden owner-only access (not localized, never shown to customers): see docs/OWNER_ACCESS.md.
                if (OwnerAccess.enabled)
                TextButton(
                  key: const ValueKey('owner-code-open'),
                  onPressed: () => _ownerCode(context),
                  child: Text(OwnerAccess.instance.active ? 'Owner access: on' : 'Owner code'),
                ),
                if (d != null)
                  TextButton(
                    key: const ValueKey('store-status-retry'),
                    onPressed: store.loadingProduct ? null : store.retryProduct,
                    child: Text(store.loadingProduct ? l.storeStatusQuerying : l.storeStatusQueryAgain),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The readout label for [f] in the UI language.
String storeStatusLabel(AppLocalizations l, StoreStatusField f) => switch (f) {
      StoreStatusField.productId => l.storeStatusProductId,
      StoreStatusField.queries => l.storeStatusQueries,
      StoreStatusField.lastQuery => l.storeStatusLastQuery,
      StoreStatusField.productsReturned => l.storeStatusProductsReturned,
      StoreStatusField.returnedIds => l.storeStatusReturnedIds,
      StoreStatusField.notFoundIds => l.storeStatusNotFoundIds,
      StoreStatusField.errorCode => l.storeStatusErrorCode,
      StoreStatusField.errorMessage => l.storeStatusErrorMessage,
      StoreStatusField.canMakePayments => l.storeStatusCanMakePayments,
      StoreStatusField.storefront => l.storeStatusStorefront,
      StoreStatusField.storeKit2 => l.storeStatusStoreKit2,
      StoreStatusField.price => l.storeStatusPrice,
      StoreStatusField.subscribed => l.storeStatusSubscribed,
      StoreStatusField.statusRead => l.storeStatusStatusRead,
      StoreStatusField.paywallError => l.storeStatusPaywallError,
    };

Future<void> _ownerCode(BuildContext context) async {
  final ctl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Owner code'),
      content: TextField(key: const ValueKey('owner-code-field'), controller: ctl, obscureText: true, autocorrect: false, enableSuggestions: false),
      actions: [
        if (OwnerAccess.instance.active)
          TextButton(onPressed: () => Navigator.pop(ctx, '\u0000clear'), child: const Text('Turn off')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(key: const ValueKey('owner-code-submit'), onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('OK')),
      ],
    ),
  );
  ctl.dispose();
  if (code == null || code.isEmpty) return;
  var ok = true;
  if (code == '\u0000clear') {
    await OwnerAccess.instance.clear();
  } else {
    ok = await OwnerAccess.instance.redeem(code);
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Done' : 'Not accepted')));
  }
}
