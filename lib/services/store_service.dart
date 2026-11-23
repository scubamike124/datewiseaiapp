import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'coach_usage.dart';

/// DateWise has exactly one product: an auto-renewable monthly subscription.
/// No free plan, no trial, no annual plan.
class StoreConfig {
  StoreConfig._();

  /// Must match the product created by the owner in App Store Connect.
  static const String productId = 'datewise_premium_monthly';

  static const String productTitle = 'DateWise Premium';

  /// `--dart-define=DW_FAKE_STORE=true` swaps in [FakeStoreService] so the
  /// paid flow can be reviewed on web or in a debug build without StoreKit.
  static const bool useFakeStore = bool.fromEnvironment('DW_FAKE_STORE');

  /// Apple's page for managing subscriptions (opens the App Store app).
  static const String appleManageUrl = 'https://apps.apple.com/account/subscriptions';
  static const String googleManageUrl = 'https://play.google.com/store/account/subscriptions';
}

enum PurchaseResult { purchased, pending, canceled, failed, unavailable }

/// Why the store could not do something. The paywall shows a localized
/// message for each.
enum StoreError { storeUnavailable, storeUnreachable, productUnavailable, purchaseFailed, restoreFailed }

/// Subscription state and actions. The UI only talks to this interface.
abstract class StoreService extends ChangeNotifier {
  /// Whether purchases can be made from this build (false on web).
  bool get canPurchase;

  /// Whether the user currently has an active DateWise Premium subscription.
  bool get isEntitled;

  /// Localized price from the App Store ("$9.99"), or null when not loaded.
  /// No price is ever hard-coded: without it the paywall says "price shown
  /// by the App Store" and Subscribe stays disabled.
  String? get storePrice;

  /// Last error to show on the paywall, if any.
  StoreError? get lastError;

  bool get busy;

  /// False until the subscription status has been read once (the app shows
  /// a blank launch screen instead of flashing the paywall at subscribers).
  bool get ready => true;

  Future<void> init();
  Future<PurchaseResult> buy();

  /// Restores purchases; returns whether an active subscription was found.
  Future<bool> restore();

  /// Re-reads the entitlement (called whenever the app comes back to the
  /// foreground, so a subscription canceled or expired meanwhile locks chat).
  Future<void> refresh();

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
  StoreError? get lastError => null;
  @override
  bool get busy => false;
  @override
  Future<void> init() async {}
  @override
  Future<PurchaseResult> buy() async => PurchaseResult.unavailable;
  @override
  Future<bool> restore() async => false;
  @override
  Future<void> refresh() async {}
  @override
  String? get manageUrl => null;
}

/// In-memory store for tests and for review builds (`DW_FAKE_STORE=true`).
/// Nothing is charged; the paywall says so.
class FakeStoreService extends StoreService {
  FakeStoreService({bool entitled = false, String? price = r'$9.99', bool purchasedBefore = false})
      : _entitled = entitled,
        _everBought = purchasedBefore || entitled,
        _price = price;

  bool _entitled;
  bool _everBought = false;
  bool _busy = false;
  final String? _price;
  int buyCalls = 0;
  int refreshCalls = 0;

  @override
  bool get canPurchase => true;
  @override
  bool get isEntitled => _entitled;
  @override
  String? get storePrice => _price;
  @override
  StoreError? get lastError => null;
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

  @override
  Future<void> refresh() async {
    refreshCalls++;
    notifyListeners();
  }

  /// Simulates the subscription ending (canceled or expired in Apple's
  /// settings): restoring no longer finds it.
  void expire() {
    _entitled = false;
    _everBought = false;
    notifyListeners();
  }

  @override
  String? get manageUrl => null;
}

/// Real purchases through the official `in_app_purchase` plugin (StoreKit 2
/// on iOS). The entitlement is read from StoreKit's current entitlements on
/// launch, so a canceled or expired subscription stops unlocking chat.
class AppStoreService extends StoreService {
  AppStoreService({
    InAppPurchase? iap,
    this.restoreSettle = const Duration(seconds: 2),
    this.purchaseRereadDelay = const Duration(seconds: 1),
    this.launchRereadDelay = const Duration(seconds: 1),
    this.launchReadTimeout = const Duration(seconds: 4),
  })
      : _iap = iap ?? InAppPurchase.instance {
    EntitlementToken.refresher = refresh;
  }

  final InAppPurchase _iap;

  /// Google Play re-delivers active purchases asynchronously after
  /// `restorePurchases()`. This is how long a refresh waits for them before
  /// it concludes there is no active subscription.
  final Duration restoreSettle;

  /// Pause before the second StoreKit re-read after a purchase the user
  /// started, when the first re-read failed.
  final Duration purchaseRereadDelay;

  /// Pause before the second StoreKit entitlement read at launch, when the
  /// first one failed or timed out (so a subscriber is not shown the paywall
  /// because of one slow read).
  final Duration launchRereadDelay;

  /// Longest wait for one StoreKit entitlement read at launch (two reads and
  /// the pause stay inside the 10-second launch limit).
  final Duration launchReadTimeout;

  /// Set while an Android refresh waits for Play to re-deliver purchases.
  Completer<void>? _restoreWait;
  bool _restoreSeen = false;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  bool _available = false;
  bool _entitled = false;
  bool _busy = false;
  bool _ready = false;
  StoreError? _error;
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
  StoreError? get lastError => _error;
  @override
  bool get busy => _busy;
  @override
  String? get manageUrl => _isIOS ? StoreConfig.appleManageUrl : StoreConfig.googleManageUrl;

  @override
  Future<void> init() async {
    try {
      await _init().timeout(const Duration(seconds: 10));
    } catch (_) {
      _error ??= StoreError.storeUnreachable;
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _init() async {
    try {
      try {
        _available = await _iap.isAvailable();
      } catch (_) {
        _available = false;
      }
      if (!_available) {
        _error = StoreError.storeUnavailable;
        // iOS: purchases may be unavailable (Screen Time "In-App Purchases:
        // Don't Allow", a StoreKit hiccup) while the subscription is still
        // active. Transaction.currentEntitlements is local, so read it anyway:
        // a subscriber keeps chat and sees no paywall.
        if (_isIOS) await _readEntitlementAtLaunch();
        notifyListeners();
        return;
      }
      _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
        _error = StoreError.purchaseFailed;
        _finishPending(PurchaseResult.failed);
      });
      // The entitlement first (local on iOS), then the product (network): a
      // slow product query can neither delay nor time out the subscriber's
      // unlock, and a subscriber keeps chat although the price is unavailable.
      if (_isIOS) {
        await _readEntitlementAtLaunch();
        await _loadProduct();
      } else {
        await _loadProduct();
        try {
          await _refreshEntitlement();
        } catch (_) {
          _error ??= StoreError.storeUnreachable;
        }
      }
    } catch (_) {
      _error = StoreError.storeUnreachable;
    }
    notifyListeners();
  }

  /// Reads the iOS entitlement at launch, twice if the first read fails or
  /// times out. If both fail the user sees the paywall with "Could not reach
  /// the App Store" and Restore purchases; the next resume reads it again.
  Future<void> _readEntitlementAtLaunch() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future<void>.delayed(launchRereadDelay);
      try {
        await _refreshEntitlement().timeout(launchReadTimeout);
        return;
      } catch (_) {}
    }
    _error ??= StoreError.storeUnreachable;
  }

  /// Loads the subscription product (price, title). Failure leaves
  /// [canPurchase] false and is retried by [refresh].
  Future<void> _loadProduct() async {
    try {
      final res = await _iap.queryProductDetails({StoreConfig.productId});
      if (res.productDetails.isNotEmpty) {
        _product = res.productDetails.first;
        // Only the product error is cleared: a failed entitlement read
        // (storeUnreachable) still needs to be shown.
        if (_error == StoreError.productUnavailable) _error = null;
      } else {
        _error = StoreError.productUnavailable;
      }
    } catch (_) {
      _error = StoreError.productUnavailable;
    }
  }

  /// Incremented by every entitlement read; only the newest read's result is
  /// applied, so a slow, stale read that finishes late cannot overwrite a
  /// newer state (for example a launch read finishing after a resume read).
  int _entitlementGen = 0;

  void _applyEntitlement(bool entitled) {
    if (_entitled == entitled) return;
    _entitled = entitled;
    notifyListeners();
  }

  /// The newest read, which superseded callers wait for (see [_refreshEntitlement]).
  Future<void>? _latestEntitlementRead;

  /// Reads the entitlement. If a newer read starts while this one runs, this
  /// one's result is discarded and the caller waits for the newest read
  /// instead of returning early, so it always sees the newest state: a
  /// purchase whose re-read overlaps a resume refresh is not reported as
  /// failed. An error from a superseded read is ignored; the newest read's
  /// error is what the caller gets.
  Future<void> _refreshEntitlement() async {
    var gen = ++_entitlementGen;
    var read = _latestEntitlementRead = _readEntitlement(gen);
    while (true) {
      try {
        await read;
      } catch (_) {
        if (gen == _entitlementGen) rethrow;
      }
      if (gen == _entitlementGen) return;
      gen = _entitlementGen;
      read = _latestEntitlementRead!;
    }
  }

  Future<void> _readEntitlement(int gen) async {
    if (_isIOS) {
      final current = await SK2Transaction.currentEntitlements();
      if (gen != _entitlementGen) return; // a newer read started: its result wins (callers wait for it)
      // Any other product id (for example an IAP created before v2) never
      // unlocks chat; stray transactions are finished in [_onPurchases].
      final mine = current.where((t) => t.productId == StoreConfig.productId).toList();
      // The signed transaction (JWS) the coach backend verifies; null when not
      // entitled. With more than one (rare), the latest-expiring one is sent.
      EntitlementToken.update(mine.isEmpty ? null : latestExpiring(mine).receiptData);
      _applyEntitlement(mine.isNotEmpty);
    } else {
      // Google Play re-delivers active purchases through purchaseStream.
      // Wait for that batch (or [restoreSettle]) and take the result as the
      // entitlement, so a lapsed subscription locks chat again. The last
      // known state is kept while waiting, so chat does not flicker.
      final wait = Completer<void>();
      _restoreWait = wait;
      _restoreSeen = false;
      try {
        await _iap.restorePurchases();
        await wait.future.timeout(restoreSettle, onTimeout: () {});
        if (gen == _entitlementGen) _applyEntitlement(_restoreSeen);
      } finally {
        if (identical(_restoreWait, wait)) _restoreWait = null;
      }
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != StoreConfig.productId) {
        // Finish stray transactions (e.g. a removed sandbox product) so the
        // store stops re-delivering them on every launch.
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        continue;
      }
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          var rereadFailed = false;
          if (_isIOS) {
            // Transaction.updates also delivers renewals for a period that
            // has ended and refunded or revoked transactions, all reported
            // as "purchased". Ask StoreKit for the current entitlement.
            // The re-read also sets the entitlement token from the current
            // entitlement (or clears it), so a refunded transaction's JWS is
            // never sent.
            try {
              await _refreshEntitlement();
            } catch (_) {
              // For a purchase the user just made, try the re-read once more
              // after a short pause before giving up on it.
              var ok = false;
              if (_pending != null) {
                await Future<void>.delayed(purchaseRereadDelay);
                try {
                  await _refreshEntitlement();
                  ok = true;
                } catch (_) {}
              }
              if (!ok) {
                // StoreKit could not be re-read: the event alone proves nothing
                // (it may be an ended renewal or a refund), so the last known
                // entitlement stands. Only the token is updated from the
                // delivered JWS; the backend verifies it with Apple's
                // certificates and refuses an expired or revoked one.
                rereadFailed = true;
                EntitlementToken.updateIfJws(p.verificationData.serverVerificationData);
              }
            }
          } else {
            _entitled = true;
            final wait = _restoreWait;
            if (wait != null) {
              _restoreSeen = true;
              if (!wait.isCompleted) wait.complete();
            }
          }
          _error = null;
          // If StoreKit could not confirm a purchase the user just paid for,
          // report it as pending ("chat unlocks when approved") rather than
          // failed, so they are not prompted to buy again. The next resume or
          // Restore re-reads the entitlement.
          _finishPending(_entitled
              ? PurchaseResult.purchased
              : (rereadFailed ? PurchaseResult.pending : PurchaseResult.failed));
        case PurchaseStatus.pending:
          _finishPending(PurchaseResult.pending);
        case PurchaseStatus.canceled:
          _finishPending(PurchaseResult.canceled);
        case PurchaseStatus.error:
          _error = StoreError.purchaseFailed;
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
      _error = StoreError.purchaseFailed;
      _finishPending(PurchaseResult.failed);
    }
    final result = await completer.future
        .timeout(const Duration(minutes: 5), onTimeout: () => PurchaseResult.failed);
    _busy = false;
    notifyListeners();
    return result;
  }

  /// The transaction with the latest expiration date (StoreKit 2 reports it
  /// in milliseconds since the epoch; a missing date counts as oldest).
  @visibleForTesting
  static SK2Transaction latestExpiring(List<SK2Transaction> list) {
    num expiry(SK2Transaction t) => num.tryParse(t.expirationDate ?? '') ?? -1;
    return list.reduce((a, b) => expiry(b) > expiry(a) ? b : a);
  }

  @override
  Future<bool> restore() async {
    // iOS can read its local entitlements even when purchases are unavailable.
    if (!_available && !_isIOS) return false;
    _busy = true;
    notifyListeners();
    try {
      // iOS: AppStore.sync, then read currentEntitlements. A failed sync
      // (offline, Apple ID sign-in canceled) does not hide a subscription
      // StoreKit already holds, so the local read still happens. Android: the
      // refresh itself asks Play to re-deliver and waits for the result.
      var syncFailed = false;
      if (_isIOS) {
        try {
          await _iap.restorePurchases();
        } catch (_) {
          syncFailed = true;
        }
      }
      await _refreshEntitlement();
      if (_entitled) {
        _error = null;
      } else if (syncFailed) {
        _error = StoreError.restoreFailed;
      }
    } catch (_) {
      _error = StoreError.restoreFailed;
    }
    _busy = false;
    notifyListeners();
    return _entitled;
  }

  @override
  Future<void> refresh() async {
    if (!_available) {
      // The store may have been unreachable at launch: try again.
      if (!_ready) return;
      try {
        _available = await _iap.isAvailable().timeout(const Duration(seconds: 10));
      } catch (_) {
        _available = false;
      }
      if (_available) {
        _error = null;
        _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
          _error = StoreError.purchaseFailed;
          _finishPending(PurchaseResult.failed);
        });
      } else if (!_isIOS) {
        return;
      }
    }
    if (_available && _product == null) {
      try {
        await _loadProduct().timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    try {
      await _refreshEntitlement().timeout(const Duration(seconds: 10));
    } catch (_) {
      // Keep the last known state when the App Store cannot be reached.
    }
    notifyListeners();
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
  // Never in a release app build: even if the flag were passed by mistake, a
  // release iOS/Android build always uses the real store.
  if (StoreConfig.useFakeStore && (kIsWeb || kDebugMode)) return FakeStoreService();
  if (kIsWeb) return UnsupportedStoreService();
  return AppStoreService();
}
