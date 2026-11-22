import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../content/legal_text.dart';
import '../services/store_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dw.dart';
import 'legal_screen.dart';

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

class _PaywallScreenState extends State<PaywallScreen> {
  String? _message;

  Future<void> _buy(StoreService store) async {
    setState(() => _message = null);
    final result = await store.buy();
    if (!mounted) return;
    switch (result) {
      case PurchaseResult.purchased:
        widget.onClose();
      case PurchaseResult.pending:
        setState(() => _message = 'Your purchase is pending approval. Chat unlocks as soon as it is approved.');
      case PurchaseResult.cancelled:
        break;
      case PurchaseResult.failed:
        setState(() => _message = store.lastError ?? 'Purchase failed. Please try again.');
      case PurchaseResult.unavailable:
        setState(() => _message = store.lastError ?? 'Purchases are not available right now.');
    }
  }

  Future<void> _restore(StoreService store) async {
    setState(() => _message = null);
    final ok = await store.restore();
    if (!mounted) return;
    if (ok) {
      widget.onClose();
    } else {
      setState(() => _message = store.lastError ?? 'No active DateWise Premium subscription was found for this Apple ID.');
    }
  }

  void _openLegal(String title, String content) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(title: title, content: content)));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreService>();
    final coach = context.watch<AppState>().selectedCoach;
    final price = store.storePrice ?? StoreConfig.fallbackPrice;
    final perMonth = store.priceLabel;
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
                    CoachImage(coach: coach, semanticLabel: '${coach.name}, AI coach portrait'),
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
                            tooltip: 'Close',
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
                    const Text('DATEWISE PREMIUM', style: AppText.eyebrow),
                    const SizedBox(height: 8),
                    Semantics(
                      header: true,
                      child: Text('Unlimited coaching with ${coach.name} and the team.', style: AppText.title),
                    ),
                    const SizedBox(height: 16),
                    const _Benefit('Chat with all four AI coaches, in English and Spanish'),
                    const _Benefit('Voice practice: speak and hear replies on your iPhone'),
                    const _Benefit('Your weekly plan and progress, kept on your device'),
                    const SizedBox(height: 18),
                    DwCard(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2E2019), AppColors.surface],
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(StoreConfig.productTitle, style: AppText.label),
                                SizedBox(height: 2),
                                Text('Monthly · auto-renews', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
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
                              const Text('per month', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (unsupported)
                      const DwCard(
                        key: ValueKey('paywall-web'),
                        child: Text(
                          'Subscribe in the iPhone app. Purchases are not available on the web.',
                          style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.text),
                        ),
                      )
                    else
                      DwButton(
                        key: const ValueKey('paywall-subscribe'),
                        label: 'Subscribe for $perMonth',
                        expand: true,
                        busy: store.busy,
                        onPressed: store.canPurchase ? () => _buy(store) : null,
                      ),
                    if (_message != null || (!unsupported && !store.canPurchase && store.lastError != null)) ...[
                      const SizedBox(height: 10),
                      Text(_message ?? store.lastError!,
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: AppColors.rose)),
                    ],
                    if (store is FakeStoreService) ...[
                      const SizedBox(height: 10),
                      const Text('Review build: purchases are simulated and nothing is charged.',
                          textAlign: TextAlign.center, style: AppText.small),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      '$perMonth. Payment is charged to your Apple ID account at confirmation of purchase. '
                      'The subscription auto-renews monthly at $price until canceled, unless canceled at least '
                      '24 hours before the end of the current period. Cancel any time in Settings › Apple ID › Subscriptions.',
                      key: const ValueKey('paywall-disclosure'),
                      textAlign: TextAlign.center,
                      style: AppText.small.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        if (!unsupported)
                          _LinkButton(key: const ValueKey('paywall-restore'), label: 'Restore Purchases', onTap: () => _restore(store)),
                        _LinkButton(label: 'Terms of Use', onTap: () => _openLegal('Terms of Use', kTermsOfService)),
                        _LinkButton(label: 'Privacy Policy', onTap: () => _openLegal('Privacy Policy', kPrivacyPolicy)),
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
