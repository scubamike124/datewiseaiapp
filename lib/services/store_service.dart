import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

/// DateWise has exactly one product: an auto-renewable monthly subscription.
/// No free plan, no trial, no annual plan.
class StoreConfig {
  StoreConfig._();

  /// Must match the product created by the owner in App Store Connect.
  static const String productId = 'datewise_premium_monthly';

  static const String productTitle = 'DateWise Premium';

  /// Shown only when the price cannot be read from the App Store.
  static const String fallbackPrice = r'$9.99';

  /// `--dart-define=DW_FAKE_STORE=true` swaps in [FakeStoreService] so the
  /// paid flow can be reviewed on web or in a debug build without StoreKit.
  static const bool useFakeStore = bool.fromEnvironment('DW_FAKE_STORE');

  /// Apple's page for managing subscriptions (opens the App Store app).
  static const String appleManageUrl = 'https://apps.apple.com/account/subscriptions';
  static const String googleManageUrl = 'https://play.google.com/store/account/subscriptions';
}

enum PurchaseResult { purchased, pending, cancelled, failed, unavailable }

/// Subscription state and actions. The UI only talks to this interface.
abstract class StoreService extends ChangeNotifier {
  /// Whether purchases can be made from this build (false on web).
  bool get canPurchase;

  /// Whether the user currently has an active DateWise Premium subscription.
  bool get isEntitled;

  /// Localised price from the store ("$9.99"), or null when not loaded.
  String? get storePrice;

  /// "$9.99/month": the store price, or the fallback when the store has none.
  String get priceLabel => '${storePrice ?? StoreConfig.fallbackPrice}/month';

  /// Last error to show on the paywall, if any.
  String? get lastError;

  bool get busy;

  /// False until the subscription status has been read once (the app shows
  /// a blank launch screen instead of flashing the paywall at subscribers).
  bool get ready => true;

  Future<void> init();
  Future<PurchaseResult> buy();

  /// Restores purchases; returns whether an active subscription was found.
  Future<bool> restore();

  /// Where "Manage subscription" goes, or null when there is nowhere to go.
  String? get manageUrl;
}

/// No purchase path (web without the fake flag): "Subscribe in the iPhone app".
class UnsupportedStoreService extends StoreService {
  @override
  bool get canPurchase => false;
  @override
  bool get isEntitled => false;
  @override
  String? get storePrice => null;
  @override
  String? get lastError => null;
  @override
  bool get busy => false;
  @override
  Future<void> init() async {}
  @override
  Future<PurchaseResult> buy() async => PurchaseResult.unavailable;
  @override
  Future<bool> restore() async => false;
  @override
  String? get manageUrl => null;
}

/// In-memory store for tests and for review builds (`DW_FAKE_STORE=true`).
/// Nothing is charged; the paywall says so.
class FakeStoreService extends StoreService {
  FakeStoreService({bool entitled = false, this.price = r'$9.99'}) : _entitled = entitled;

  bool _entitled;
  bool _everBought = false;
  bool _busy = false;
  final String? price;
  int buyCalls = 0;

  @override
  bool get canPurchase => true;
  @override
  bool get isEntitled => _entitled;
  @override
  String? get storePrice => price;
  @override
  String? get lastError => null;
  @override
  bool get busy => _busy;
  @override
  Future<void> init() async {}

  @override
  Future<PurchaseResult> buy() async {
    buyCalls++;
    _busy = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _entitled = true;
    _everBought = true;
    _busy = false;
    notifyListeners();
    return PurchaseResult.purchased;
  }

  @override
  Future<bool> restore() async {
    _entitled = _everBought || _entitled;
    notifyListeners();
    return _entitled;
  }

  /// Simulates the subscription ending (tests).
  void expire() {
    _entitled = false;
    notifyListeners();
  }

  @override
  String? get manageUrl => null;
}

/// Real purchases through the official `in_app_purchase` plugin (StoreKit 2
/// on iOS). The entitlement is read from StoreKit's current entitlements on
/// launch, so a cancelled or expired subscription stops unlocking chat.
class AppStoreService extends StoreService {
  AppStoreService({InAppPurchase? iap}) : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  bool _available = false;
  bool _entitled = false;
  bool _busy = false;
  bool _ready = false;
  String? _error;
  Completer<PurchaseResult>? _pending;

  @override
  bool get ready => _ready;

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  bool get canPurchase => _available && _product != null;
  @override
  bool get isEntitled => _entitled;
  @override
  String? get storePrice => _product?.price;
  @override
  String? get lastError => _error;
  @override
  bool get busy => _busy;
  @override
  String? get manageUrl => _isIOS ? StoreConfig.appleManageUrl : StoreConfig.googleManageUrl;

  @override
  Future<void> init() async {
    try {
      await _init().timeout(const Duration(seconds: 10));
    } catch (_) {
      _error ??= 'Could not reach the App Store.';
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _init() async {
    try {
      _available = await _iap.isAvailable();
      if (!_available) {
        _error = 'The App Store is not available right now.';
        notifyListeners();
        return;
      }
      _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
        _error = 'Purchase failed. Please try again.';
        _finishPending(PurchaseResult.failed);
      });
      final res = await _iap.queryProductDetails({StoreConfig.productId});
      if (res.productDetails.isNotEmpty) {
        _product = res.productDetails.first;
      } else {
        _error = 'DateWise Premium is not available in the store yet.';
      }
      await _refreshEntitlement();
    } catch (_) {
      _error = 'Could not reach the App Store.';
    }
    notifyListeners();
  }

  Future<void> _refreshEntitlement() async {
    if (_isIOS) {
      final current = await SK2Transaction.currentEntitlements();
      _entitled = current.any((t) => t.productId == StoreConfig.productId);
    } else {
      // Google Play re-delivers active purchases through purchaseStream.
      await _iap.restorePurchases();
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != StoreConfig.productId) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _entitled = true;
          _error = null;
          _finishPending(PurchaseResult.purchased);
        case PurchaseStatus.pending:
          _finishPending(PurchaseResult.pending);
        case PurchaseStatus.canceled:
          _finishPending(PurchaseResult.cancelled);
        case PurchaseStatus.error:
          _error = 'Purchase failed. Please try again.';
          _finishPending(PurchaseResult.failed);
      }
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
    notifyListeners();
  }

  void _finishPending(PurchaseResult r) {
    final c = _pending;
    if (c != null && !c.isCompleted) c.complete(r);
    _pending = null;
    _busy = false;
  }

  @override
  Future<PurchaseResult> buy() async {
    final product = _product;
    if (!_available || product == null) return PurchaseResult.unavailable;
    _busy = true;
    _error = null;
    notifyListeners();
    final completer = Completer<PurchaseResult>();
    _pending = completer;
    try {
      await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
    } catch (_) {
      _error = 'Purchase failed. Please try again.';
      _finishPending(PurchaseResult.failed);
    }
    final result = await completer.future
        .timeout(const Duration(minutes: 5), onTimeout: () => PurchaseResult.failed);
    _busy = false;
    notifyListeners();
    return result;
  }

  @override
  Future<bool> restore() async {
    if (!_available) return false;
    _busy = true;
    notifyListeners();
    try {
      await _iap.restorePurchases();
      await _refreshEntitlement();
    } catch (_) {
      _error = 'Could not restore purchases.';
    }
    _busy = false;
    notifyListeners();
    return _entitled;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// The store for this build: fake when the review flag is set, none on web,
/// otherwise the real App Store / Google Play.
StoreService createStoreService() {
  if (StoreConfig.useFakeStore) return FakeStoreService();
  if (kIsWeb) return UnsupportedStoreService();
  return AppStoreService();
}
