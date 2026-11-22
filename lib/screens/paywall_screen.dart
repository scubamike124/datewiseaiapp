import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

/// The paywall's localized message for a store error.
String storeErrorText(AppLocalizations l, StoreError e) => switch (e) {
      StoreError.storeUnavailable => l.storeUnavailable,
      StoreError.storeUnreachable => l.storeUnreachable,
      StoreError.productUnavailable => l.productUnavailable,
      StoreError.purchaseFailed => l.purchaseFailed,
      StoreError.restoreFailed => l.restoreFailed,
    };

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
      setState(() => _message = (l) => error == StoreError.restoreFailed || error == StoreError.storeUnreachable || error == StoreError.storeUnavailable
          ? storeErrorText(l, error!)
          : l.noSubscriptionForAppleId);
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
    final price = store.price;
    final perMonth = l.pricePerMonth(price);
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
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(StoreConfig.productTitle, style: AppText.label),
                                const SizedBox(height: 2),
                                Text(l.monthlyAutoRenews, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                price,
                                key: const ValueKey('paywall-price'),
                                style: const TextStyle(fontFamily: AppFonts.serif, fontSize: 26, color: AppColors.gold, height: 1.1),
                              ),
                              Text(l.perMonth, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                            ],
                          ),
                        ],
                      ),
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
                        label: l.subscribeFor(price),
                        expand: true,
                        busy: store.busy,
                        onPressed: store.canPurchase ? () => _buy(store) : null,
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
                    const SizedBox(height: 16),
                    Text(
                      l.paywallDisclosure(perMonth, price),
                      key: const ValueKey('paywall-disclosure'),
                      textAlign: TextAlign.center,
                      style: AppText.small.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        if (!unsupported)
                          _LinkButton(key: const ValueKey('paywall-restore'), label: l.restorePurchases, onTap: () => _restore(store)),
                        _LinkButton(key: const ValueKey('paywall-terms'), label: l.termsOfUse, onTap: () => _openLegal(LegalDoc.terms)),
                        _LinkButton(key: const ValueKey('paywall-privacy'), label: l.privacyPolicy, onTap: () => _openLegal(LegalDoc.privacy)),
                      ],
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
      style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: AppColors.textMuted),
      child: Text(label, style: const TextStyle(fontSize: 13.5, decoration: TextDecoration.underline, decorationColor: AppColors.faint)),
    );
  }
}
