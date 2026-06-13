import '../models/tier.dart';

/// Seam for in-app purchases so the Plans UI doesn't depend on a billing
/// implementation. Today [MockPurchaseService] "succeeds" immediately and the
/// caller records the chosen plan (status stays `pending_payment`). Real Google
/// Play Billing (`in_app_purchase`) will replace the mock later without changing
/// any callers.
abstract class PurchaseService {
  /// Attempts to purchase [tier]. Returns true if the user should be moved onto
  /// that plan. Throws on a real billing error (callers should handle).
  Future<bool> buy(SubscriptionTier tier);

  /// Restores previously-purchased subscriptions.
  Future<void> restore();
}

class MockPurchaseService implements PurchaseService {
  const MockPurchaseService();

  @override
  Future<bool> buy(SubscriptionTier tier) async => true;

  @override
  Future<void> restore() async {}
}
