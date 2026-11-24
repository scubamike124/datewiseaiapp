import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/fair_use.dart';
import '../services/store_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dw.dart';
import 'legal_screen.dart';
import '../l10n/l10n.dart';

/// Opens the paywall as a full-screen sheet; it closes itself after a
/// successful purchase or restore.
Future<void> showPaywall(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (ctx) => PaywallScreen(onClose: () => Navigator.of(ctx).pop()),
  ));
}

/// DateWise Premium: one auto-renewable monthly subscription, with the
/// disclosures Apple requires (title, price per month, auto-renewal, how to
/// cancel, charged to the Apple ID), Restore Purchases, Terms and Privacy.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

/// The paywall's fair-use line, with the limits the backend enforces
/// ([FairUse], checked against backend/wrangler.toml by a test).
String fairUseLine(AppLocalizations l) => l.paywallFairUse(
      FairUse.format(FairUse.dailyReplies, l.localeName),
      FairUse.format(FairUse.monthlyReplies, l.localeName),
      FairUse.format(FairUse.perMinute, l.localeName),
      FairUse.format(FairUse.concurrent, l.localeName),
    );

/// The paywall's localized message for a store error.
String storeErrorText(AppLocalizations l, StoreError e) => switch (e) {
      StoreError.storeUnavailable => l.storeUnavailable,
      StoreError.storeUnreachable => l.storeUnreachable,
      StoreError.productUnavailable => l.productUnavailable,
      StoreError.purchaseFailed => l.purchaseFailed,
      StoreError.restoreFailed => l.restoreFailed,
    };

/// What a restore that found no active subscription says: the store's error
/// when the store failed, is unavailable or could not be reached (never "no
/// subscription", which would be wrong then), else [none].
String restoreFailureText(AppLocalizations l, StoreError? error, String none) =>
    error == StoreError.restoreFailed || error == StoreError.storeUnreachable || error == StoreError.storeUnavailable
        ? storeErrorText(l, error!)
        : none;

class _PaywallScreenState extends State<PaywallScreen> {
  /// A message for the last action, built in the current language.
  String Function(AppLocalizations l)? _message;

  Future<void> _buy(StoreService store) async {
    setState(() => _message = null);
    final result = await store.buy();
    if (!mounted) return;
    final error = store.lastError;
    switch (result) {
      case PurchaseResult.purchased:
        widget.onClose();
      case PurchaseResult.pending:
        setState(() => _message = (l) => l.purchasePending);
      case PurchaseResult.canceled:
        break;
      case PurchaseResult.failed:
        setState(() => _message = (l) => error == null ? l.purchaseFailed : storeErrorText(l, error));
      case PurchaseResult.unavailable:
        setState(() => _message = (l) => error == null ? l.purchasesUnavailable : storeErrorText(l, error));
    }
  }

  Future<void> _restore(StoreService store) async {
    setState(() => _message = null);
    final ok = await store.restore();
    if (!mounted) return;
    final error = store.lastError;
    if (ok) {
      widget.onClose();
    } else {
      setState(() => _message = (l) => restoreFailureText(l, error, l.noSubscriptionForAppleId));
    }
  }

  void _openLegal(LegalDoc doc) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LegalScreen.doc(doc)));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final coach = context.watch<AppState>().selectedCoach;
    final l = context.l10n;
    // Only the price StoreKit returns is ever shown.
    final price = store.storePrice;
    final unsupported = store is UnsupportedStoreService;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      key: const ValueKey('paywall'),
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 230 + top,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoachImage(coach: coach, semanticLabel: l.coachPortrait(coach.name)),
                    const FadeToBackground(stops: [0.4, 1]),
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 120,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x99150C10), Color(0x00150C10)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: top + 6,
                      left: 20,
                      right: 8,
                      child: Row(
                        children: [
                          const BrandMark(size: 20),
                          const Spacer(),
                          CircleIconButton(
                            key: const ValueKey('paywall-close'),
                            icon: Icons.close_rounded,
                            tooltip: l.close,
                            filled: true,
                            onPressed: widget.onClose,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.premiumEyebrow.toUpperCase(), style: AppText.eyebrow),
                    const SizedBox(height: 8),
                    Semantics(
                      header: true,
                      child: Text(l.paywallHeadline(coach.name), style: AppText.title),
                    ),
                    const SizedBox(height: 16),
                    _Benefit(l.benefitCoaches),
                    _Benefit(l.benefitVoice),
                    _Benefit(l.benefitPlan),
                    const SizedBox(height: 18),
                    DwCard(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2E2019), AppColors.surface],
                      ),
                      // Narrow screens and large Dynamic Type (320 pt at 200%): the price goes under the
                      // plan name instead of beside it, so the name keeps the full width and never
                      // breaks inside a word (code review m9).
                      child: LayoutBuilder(builder: (context, c) {
                        final stacked = c.maxWidth - 148 < 140 * MediaQuery.textScalerOf(context).scale(1);
                        final name = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const WholeWordsText(StoreConfig.productTitle, key: ValueKey('paywall-plan-name'), style: AppText.label),
                            const SizedBox(height: 2),
                            WholeWordsText(l.monthlyAutoRenews, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                          ],
                        );
                        final priceColumn =
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: stacked ? double.infinity : 140),
                            child: Column(
                              crossAxisAlignment: stacked ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                              children: [
                                if (price != null) ...[
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: stacked ? Alignment.centerLeft : Alignment.centerRight,
                                    child: Text(
                                      price,
                                      key: const ValueKey('paywall-price'),
                                      maxLines: 1,
                                      style: const TextStyle(fontFamily: AppFonts.serif, fontSize: 26, color: AppColors.gold, height: 1.1),
                                    ),
                                  ),
                                  Text(l.perMonth, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                                ] else
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 130),
                                    child: Text(
                                      l.priceFromAppStore,
                                      key: const ValueKey('paywall-price'),
                                      textAlign: stacked ? TextAlign.start : TextAlign.end,
                                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        return stacked
                            ? Column(
                                key: const ValueKey('paywall-plan-stacked'),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [name, const SizedBox(height: 10), priceColumn],
                              )
                            : Row(
                                children: [
                                  Expanded(child: name),
                                  const SizedBox(width: 8),
                                  // The price takes only the width it needs (up to 140), so the plan name and
                                  // "Monthly · auto-renews" keep the rest (UI review M1). scaleDown: a long
                                  // localized StoreKit price ("MX$399.00") shrinks to fit instead of overflowing.
                                  priceColumn,
                                ],
                              );
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (unsupported)
                      DwCard(
                        key: const ValueKey('paywall-web'),
                        child: Text(
                          l.paywallWebOnly,
                          style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.text),
                        ),
                      )
                    else
                      DwButton(
                        key: const ValueKey('paywall-subscribe'),
                        label: price != null ? l.subscribeFor(price) : l.subscribe,
                        expand: true,
                        busy: store.busy,
                        onPressed: store.canPurchase && price != null ? () => _buy(store) : null,
                      ),
                    if (_message != null || (!unsupported && !store.canPurchase && store.lastError != null)) ...[
                      const SizedBox(height: 10),
                      Text(_message?.call(l) ?? storeErrorText(l, store.lastError!),
                          key: const ValueKey('paywall-message'),
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: AppColors.rose)),
                    ],
                    if (store is FakeStoreService) ...[
                      const SizedBox(height: 10),
                      Text(l.reviewBuildNote, textAlign: TextAlign.center, style: AppText.small),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        if (!unsupported)
                          _LinkButton(key: const ValueKey('paywall-restore'), label: l.restorePurchases, onTap: () => _restore(store)),
                        _LinkButton(key: const ValueKey('paywall-terms'), label: l.termsOfUse, onTap: () => _openLegal(LegalDoc.terms)),
                        _LinkButton(key: const ValueKey('paywall-privacy'), label: l.privacyShort, onTap: () => _openLegal(LegalDoc.privacy)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      price != null ? l.paywallDisclosure(l.pricePerMonth(price), price) : l.paywallDisclosureNoPrice,
                      key: const ValueKey('paywall-disclosure'),
                      textAlign: TextAlign.center,
                      style: AppText.small.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      fairUseLine(l),
                      key: const ValueKey('paywall-fair-use'),
                      textAlign: TextAlign.center,
                      style: AppText.small.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(color: Color(0x29DDB67F), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 14, color: AppColors.gold),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.text))),
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      // Compact, so Restore, Terms and Privacy fit on one row above the fold.
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        foregroundColor: AppColors.textMuted,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12.5, decoration: TextDecoration.underline, decorationColor: AppColors.faint)),
    );
  }
}
