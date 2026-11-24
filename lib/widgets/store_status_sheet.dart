import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/store_service.dart';
import '../theme/app_theme.dart';

/// The hidden "Store status" readout: what StoreKit returned for the product
/// query, so the owner can see on a TestFlight phone why the paywall has no
/// price. Opened by a long-press on the paywall's plan card or on the version
/// line under You › About; normal users never see it. It shows no secrets (no
/// transaction, receipt or JWS) and changes nothing: "Query again" only
/// re-runs the product query.
///
/// Not localized: it is a technical readout for the owner and support.
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
    final d = store.diagnostics;
    final rows = d?.rows() ?? [('Store', '${store.runtimeType} (no StoreKit in this build)')];
    final text = d?.toString() ?? rows.map((r) => '${r.$1}: ${r.$2}').join('\n');
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
              child: Text('Store status', style: AppText.name.copyWith(fontSize: 22)),
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
                  child: const Text('Copy'),
                ),
                if (d != null)
                  TextButton(
                    key: const ValueKey('store-status-retry'),
                    onPressed: store.loadingProduct ? null : store.retryProduct,
                    child: Text(store.loadingProduct ? 'Querying…' : 'Query again'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
