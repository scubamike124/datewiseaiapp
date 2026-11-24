// The subscription product failing to load (TestFlight build 196: App Store
// Connect had `datewise_premium_monthly` in MISSING_METADATA, so StoreKit
// returned no product): what AppStoreService and the paywall do, how the load
// is retried (paywall open, Try again, app resume), the hidden "Store status"
// readout, and the real plugin's StoreKit 2 purchase events (pending and
// canceled carry no transaction and are never finished; a revoked or expired
// subscription is dropped from currentEntitlements).
//
// No path here unlocks anything without StoreKit's current entitlement, and
// no price is ever shown that StoreKit did not return.

// The StoreKit 2 host API can only be replaced through the plugin's
// @visibleForTesting hook, which lives in src/.
// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart' show SK2PurchaseDetails;
import 'package:in_app_purchase_storekit/src/in_app_purchase_apis.dart' show setInAppPurchaseHostApis;
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'package:datewise_ai/l10n/app_localizations.dart';
import 'package:datewise_ai/screens/paywall_screen.dart' show restoreFailureText;
import 'package:datewise_ai/screens/shell.dart' show AppTab;
import 'package:datewise_ai/services/coach_usage.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/widgets/dw.dart';

import 'helpers.dart';

ProductDetails _product({String id = StoreConfig.productId}) => ProductDetails(
      id: id,
      title: 'DateWise Premium Monthly',
      description: '',
      price: r'$19.99',
      rawPrice: 19.99,
      currencyCode: 'USD',
    );

/// An InAppPurchase whose product query the test controls.
class _Iap implements InAppPurchase {
  bool available = true;

  /// What queryProductDetails returns: no product (MISSING_METADATA), the
  /// product, a plugin error, or a throw.
  List<ProductDetails> products = [];
  IAPError? error;
  bool queryThrows = false;
  Completer<void>? queryGate;
  int queries = 0;
  int availabilityChecks = 0;
  String country = 'USA';
  int restores = 0;
  int buys = 0;
  int listens = 0;

  final stream = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <PurchaseDetails>[];

  /// What the next buy reports on the purchase stream (the real plugin's
  /// StoreKit 2 events, see [_sk2Event]).
  List<PurchaseDetails> Function()? onBuy;

  @override
  Future<bool> isAvailable() async {
    availabilityChecks++;
    return available;
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream {
    listens++;
    return stream.stream;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async {
    queries++;
    expect(identifiers, {StoreConfig.productId});
    if (queryGate != null) await queryGate!.future;
    if (queryThrows) throw StateError('StoreKit product request failed');
    return ProductDetailsResponse(
      productDetails: products,
      notFoundIDs: identifiers.difference({for (final p in products) p.id}).toList(),
      error: error,
    );
  }

  @override
  Future<String> countryCode() async => country;

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buys++;
    final events = onBuy?.call() ?? const <PurchaseDetails>[];
    scheduleMicrotask(() => stream.add(events));
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async => restores++;

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async => completed.add(purchase);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// StoreKit 2 host API: Transaction.currentEntitlements and AppStore.sync.
class _SK2 implements InAppPurchase2API {
  List<String> entitled = [];
  String jws = 'aaa.bbb.ccc';
  int syncs = 0;
  bool syncFails = false;

  /// Thrown by sync instead (the plugin's PlatformException).
  Object? syncError;

  @override
  Future<List<SK2TransactionMessage>> currentEntitlements() async => [
        for (final id in entitled)
          SK2TransactionMessage(id: 7, originalId: 7, productId: id, status: SK2PurchaseStatusMessage.purchased, receiptData: jws),
      ];

  @override
  Future<void> sync() async {
    syncs++;
    if (syncFails) throw StateError('AppStore.sync failed');
    if (syncError != null) throw syncError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A purchase event as the real plugin builds it for StoreKit 2
/// (SK2TransactionMessage.convertToDetails): pending and canceled have no
/// transaction (id 0, so no purchaseID) and pendingCompletePurchase is true
/// only for purchased.
PurchaseDetails _sk2Event(PurchaseStatus status, {String jws = ''}) => SK2PurchaseDetails(
      productID: StoreConfig.productId,
      purchaseID: status == PurchaseStatus.purchased || status == PurchaseStatus.restored ? '7' : null,
      verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: jws, source: 'app_store'),
      transactionDate: null,
      status: status,
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

AppStoreService _store(_Iap iap) => AppStoreService(
      iap: iap,
      restoreSettle: Duration.zero,
      launchRereadDelay: Duration.zero,
      launchReadTimeout: const Duration(milliseconds: 200),
      purchaseRereadDelay: Duration.zero,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final en = lookupAppLocalizations(const Locale('en'));

  group('the product query returns nothing (App Store Connect MISSING_METADATA)', () {
    test('canPurchase false, no price, productUnavailable; the diagnostics say why', () async {
      final iap = _Iap();
      final store = _store(iap);
      await store.init();
      expect(store.ready, isTrue);
      expect(store.canPurchase, isFalse);
      expect(store.storePrice, isNull);
      expect(store.lastError, StoreError.productUnavailable);
      expect(await store.buy(), PurchaseResult.unavailable);
      expect(iap.buys, 0);
      expect(store.isEntitled, isFalse);

      final d = store.diagnostics;
      expect(d.productId, 'datewise_premium_monthly');
      expect(d.queries, 1);
      expect(d.productsReturned, 0);
      expect(d.notFoundIds, [StoreConfig.productId]);
      expect(d.errorCode, isNull);
      expect(d.canMakePayments, isTrue);
      expect(d.storefront, 'USA');
      expect(d.lastError, 'productUnavailable');
      expect(d.toString(), contains('notFoundIDs: datewise_premium_monthly'));
    });

    test('a plugin error is recorded with its code and message', () async {
      final iap = _Iap()
        ..error = IAPError(source: 'app_store', code: 'storekit2_network', message: 'The Internet connection appears to be offline.');
      final store = _store(iap);
      await store.init();
      expect(store.lastError, StoreError.productUnavailable);
      expect(store.diagnostics.errorCode, 'storekit2_network');
      expect(store.diagnostics.errorMessage, contains('offline'));
    });

    test('a query that throws is recorded, not fatal', () async {
      final store = _store(_Iap()..queryThrows = true);
      await store.init();
      expect(store.ready, isTrue);
      expect(store.lastError, StoreError.productUnavailable);
      expect(store.diagnostics.errorCode, 'StateError');
    });

    test('the storefront failing to read is recorded, not fatal', () async {
      final iap = _Iap();
      final store = AppStoreService(iap: _NoCountryIap(iap), restoreSettle: Duration.zero);
      await store.init();
      expect(store.diagnostics.storefront, isNull);
      expect(store.diagnostics.storefrontError, isNotNull);
      expect(store.lastError, StoreError.productUnavailable);
    });

    test('only the product the app sells counts: another product id never enables Subscribe', () async {
      final store = _store(_Iap()..products = [_product(id: 'some_other_product')]);
      await store.init();
      expect(store.canPurchase, isFalse);
      expect(store.storePrice, isNull);
      expect(store.diagnostics.returnedIds, ['some_other_product']);
      expect(store.diagnostics.notFoundIds, [StoreConfig.productId]);
    });
  });

  group('retrying the product query', () {
    test('retryProduct loads it once App Store Connect serves it; nothing is unlocked', () async {
      final iap = _Iap();
      final store = _store(iap);
      await store.init();
      iap.products = [_product()];
      await store.retryProduct();
      expect(iap.queries, 2);
      expect(store.canPurchase, isTrue);
      expect(store.storePrice, r'$19.99');
      expect(store.lastError, isNull);
      expect(store.isEntitled, isFalse, reason: 'loading the product never unlocks chat');
      expect(store.diagnostics.productsReturned, 1);
      expect(store.diagnostics.notFoundIds, isEmpty);
      expect(store.diagnostics.price, r'$19.99');
    });

    test('retryProduct does nothing once the product is loaded', () async {
      final iap = _Iap()..products = [_product()];
      final store = _store(iap);
      await store.init();
      await store.retryProduct();
      expect(iap.queries, 1);
    });

    test('retryProduct waits for launch: before init finished it does not query', () async {
      final iap = _Iap();
      final store = _store(iap);
      await store.retryProduct();
      expect(iap.queries, 0);
    });

    test('Try again, paywall open and resume at the same time share one query', () async {
      final iap = _Iap();
      final store = _store(iap);
      await store.init();
      iap
        ..products = [_product()]
        ..queryGate = Completer<void>();
      final a = store.retryProduct();
      final b = store.refresh();
      final c = store.retryProduct(); // already loading: returns at once
      await _settle();
      expect(store.loadingProduct, isTrue);
      iap.queryGate!.complete();
      await Future.wait([a, b, c]);
      expect(iap.queries, 2, reason: 'one at launch, one shared by the retries');
      expect(store.loadingProduct, isFalse);
      expect(store.canPurchase, isTrue);
    });

    test('the app returning to the foreground (refresh) retries the product', () async {
      final iap = _Iap();
      final store = _store(iap);
      await store.init();
      iap.products = [_product()];
      await store.refresh();
      expect(store.storePrice, r'$19.99');
    });

    test('purchases unavailable at launch, then allowed: the retry checks again and listens once', () async {
      final iap = _Iap()
        ..available = false
        ..products = [_product()];
      final store = _store(iap);
      await store.init();
      expect(store.lastError, StoreError.storeUnavailable);
      expect(store.diagnostics.canMakePayments, isFalse);
      iap.available = true;
      await store.retryProduct();
      expect(store.canPurchase, isTrue);
      expect(store.lastError, isNull);
      expect(store.diagnostics.canMakePayments, isTrue);
      await store.retryProduct();
      await store.refresh();
      expect(iap.listens, 1, reason: 'the purchase stream is listened to once');
    });

    test('a failed retry keeps productUnavailable', () async {
      final iap = _Iap();
      final store = _store(iap);
      await store.init();
      await store.retryProduct();
      expect(iap.queries, 2);
      expect(store.canPurchase, isFalse);
      expect(store.lastError, StoreError.productUnavailable);
    });

    test('Restore that finds nothing keeps productUnavailable (and says "no subscription")', () async {
      final iap = _Iap();
      final store = _store(iap);
      await store.init();
      expect(await store.restore(), isFalse);
      expect(store.lastError, StoreError.productUnavailable);
      expect(restoreFailureText(en, store.lastError, en.noSubscriptionForAppleId), en.noSubscriptionForAppleId);
    });
  });

  group('StoreKit 2 with the real plugin\'s events (iOS)', () {
    late _SK2 sk2;
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sk2 = _SK2();
      setInAppPurchaseHostApis(api2: sk2);
      EntitlementToken.update(null);
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      EntitlementToken.update(null);
      EntitlementToken.refresher = null;
    });

    test('the diagnostics never contain the transaction JWS', () async {
      sk2.entitled = [StoreConfig.productId];
      sk2.jws = 'eyJhbGciOiJFUzI1NiJ9.SECRETPAYLOAD.SIGNATURE';
      final store = _store(_Iap()..products = [_product()]);
      await store.init();
      expect(store.isEntitled, isTrue);
      expect(EntitlementToken.current, sk2.jws);
      final text = store.diagnostics.toString();
      expect(text, contains('Subscribed: true'));
      expect(text, isNot(contains('SECRETPAYLOAD')));
      expect(text, isNot(contains('eyJ')));
    });

    test('purchased: entitled from currentEntitlements, transaction finished', () async {
      final iap = _Iap()..products = [_product()];
      final store = _store(iap);
      await store.init();
      iap.onBuy = () {
        sk2.entitled = [StoreConfig.productId];
        return [_sk2Event(PurchaseStatus.purchased, jws: 'x.y.z')];
      };
      expect(await store.buy(), PurchaseResult.purchased);
      expect(store.isEntitled, isTrue);
      expect(iap.completed.map((p) => p.purchaseID), ['7']);
    });

    test('pending (Ask to Buy): reported pending, not entitled, nothing finished (no transaction yet)', () async {
      final iap = _Iap()..products = [_product()];
      final store = _store(iap);
      await store.init();
      iap.onBuy = () => [_sk2Event(PurchaseStatus.pending)];
      expect(await store.buy(), PurchaseResult.pending);
      expect(store.isEntitled, isFalse);
      expect(store.busy, isFalse);
      expect(iap.completed, isEmpty, reason: 'completePurchase with no purchaseID would crash the plugin');
      // Approved later: Transaction.updates delivers it; currentEntitlements confirms it.
      sk2.entitled = [StoreConfig.productId];
      iap.stream.add([_sk2Event(PurchaseStatus.purchased, jws: 'x.y.z')]);
      await _settle();
      expect(store.isEntitled, isTrue);
    });

    test('canceled: reported canceled, no error, not entitled, nothing finished', () async {
      final iap = _Iap()..products = [_product()];
      final store = _store(iap);
      await store.init();
      iap.onBuy = () => [_sk2Event(PurchaseStatus.canceled)];
      expect(await store.buy(), PurchaseResult.canceled);
      expect(store.lastError, isNull);
      expect(store.isEntitled, isFalse);
      expect(iap.completed, isEmpty);
    });

    test('a "purchased" event StoreKit does not confirm (ended renewal) does not unlock', () async {
      final iap = _Iap()..products = [_product()];
      final store = _store(iap);
      await store.init();
      iap.onBuy = () => [_sk2Event(PurchaseStatus.purchased, jws: 'x.y.z')];
      expect(await store.buy(), PurchaseResult.failed);
      expect(store.isEntitled, isFalse);
      expect(EntitlementToken.current, isNull);
    });

    test('revoked (refund) while the app runs: the Transaction.updates event locks chat and clears the token', () async {
      sk2.entitled = [StoreConfig.productId];
      final iap = _Iap()..products = [_product()];
      final store = _store(iap);
      await store.init();
      expect(store.isEntitled, isTrue);
      expect(EntitlementToken.current, isNotNull);
      sk2.entitled = []; // currentEntitlements excludes revoked transactions
      iap.stream.add([_sk2Event(PurchaseStatus.purchased, jws: 'revoked.jws.sig')]);
      await _settle();
      expect(store.isEntitled, isFalse);
      expect(EntitlementToken.current, isNull, reason: 'a revoked transaction\'s JWS is never sent');
    });

    test('expired while in the background: the resume refresh locks chat and clears the token', () async {
      sk2.entitled = [StoreConfig.productId];
      final store = _store(_Iap()..products = [_product()]);
      await store.init();
      sk2.entitled = [];
      await store.refresh();
      expect(store.isEntitled, isFalse);
      expect(EntitlementToken.current, isNull);
    });

    test('Restore calls AppStore.sync, then reads the entitlement', () async {
      final iap = _Iap()..products = [_product()];
      final store = _store(iap);
      await store.init();
      expect(sk2.syncs, 0, reason: 'launch never calls sync (it may ask the user to sign in)');
      sk2.entitled = [StoreConfig.productId];
      expect(await store.restore(), isTrue);
      expect(sk2.syncs, 1);
      expect(iap.restores, 1);
      expect(store.lastError, isNull);
    });

    test('Restore: sync fails but StoreKit holds the subscription: restored', () async {
      sk2
        ..syncFails = true
        ..entitled = [StoreConfig.productId];
      final store = _store(_Iap()..products = [_product()]);
      await store.init();
      expect(await store.restore(), isTrue);
      expect(store.lastError, isNull);
    });

    test('Restore: sync fails and nothing is held: restoreFailed', () async {
      sk2.syncFails = true;
      final store = _store(_Iap()..products = [_product()]);
      await store.init();
      expect(await store.restore(), isFalse);
      expect(store.lastError, StoreError.restoreFailed);
    });

    test('a subscriber keeps chat although the product never loads', () async {
      sk2.entitled = [StoreConfig.productId];
      final store = _store(_Iap());
      await store.init();
      expect(store.isEntitled, isTrue);
      expect(store.canPurchase, isFalse);
      expect(store.diagnostics.storeKit2, isTrue);
    });
  });

  group('paywall without the product', () {
    Future<(_Iap, AppStoreService)> loaded(WidgetTester tester) async {
      final iap = _Iap();
      final store = _store(iap);
      await tester.runAsync(store.init);
      return (iap, store);
    }

    for (final (lang, prefs, message, retry) in [
      ('English', onboardedPrefs(), 'DateWise Premium is not available in the store yet.', 'Try again'),
      ('Spanish', spanishPrefs(), 'DateWise Premium aún no está disponible en la tienda.', 'Reintentar'),
    ]) {
      testWidgets('$lang: message, Subscribe disabled, no price; Try again loads the real price', (tester) async {
        final (iap, store) = await loaded(tester);
        await pumpApp(tester, prefs: prefs, store: store);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
        expect(iap.queries, 2, reason: 'opening the paywall queried the product again');
        expect(find.text(message), findsOneWidget);
        expect(tester.widget<DwButton>(find.byKey(const ValueKey('paywall-subscribe'))).onPressed, isNull);
        expect(find.textContaining(RegExp(r'\d[.,]\d\d(?!\d)')), findsNothing, reason: 'no hard-coded price');
        final retryButton = tester.widget<DwButton>(find.byKey(const ValueKey('paywall-retry')));
        expect(retryButton.label, retry);
        expect(retryButton.onPressed, isNotNull);

        iap.products = [_product()];
        await tester.ensureVisible(find.byKey(const ValueKey('paywall-retry')));
        await tester.tap(find.byKey(const ValueKey('paywall-retry')));
        await tester.pumpAndSettle();
        expect(iap.queries, 3);
        expect(find.byKey(const ValueKey('paywall-retry')), findsNothing);
        expect(find.text(message), findsNothing);
        final subscribe = tester.widget<DwButton>(find.byKey(const ValueKey('paywall-subscribe')));
        expect(subscribe.onPressed, isNotNull);
        expect(subscribe.label, contains(r'$19.99'));
        expect(store.isEntitled, isFalse);
      });
    }

    testWidgets('with the product loaded there is no Try again', (tester) async {
      final iap = _Iap()..products = [_product()];
      final store = _store(iap);
      await tester.runAsync(store.init);
      await pumpApp(tester, prefs: onboardedPrefs(), store: store);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paywall-retry')), findsNothing);
      expect(iap.queries, 1, reason: 'no extra query when the product is loaded');
    });

    testWidgets('long-press on the plan card opens the Store status readout', (tester) async {
      final (_, store) = await loaded(tester);
      await pumpApp(tester, prefs: onboardedPrefs(), store: store);
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey('paywall-plan')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('store-status')), findsOneWidget);
      expect(find.text('Store status'), findsOneWidget);
      expect(find.textContaining('datewise_premium_monthly'), findsWidgets);
      expect(find.textContaining('USA'), findsOneWidget);
      expect(find.byKey(const ValueKey('store-status-retry')), findsOneWidget);
    });

    testWidgets('a plain tap on the plan card opens nothing', (tester) async {
      final (_, store) = await loaded(tester);
      await pumpApp(tester, prefs: onboardedPrefs(), store: store);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('paywall-plan')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('store-status')), findsNothing);
    });

    testWidgets('web (no StoreKit): no Try again', (tester) async {
      await pumpApp(tester, prefs: onboardedPrefs(), store: UnsupportedStoreService());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paywall-retry')), findsNothing);
    });
  });

  // --- StoreKit review minors (2026-11-24) -----------------------------------------------------
  group('review minors: late product answer, canceled Restore sign-in, Store status in Spanish', () {
    late _SK2 sk2;
    setUp(() {
      sk2 = _SK2();
      setInAppPurchaseHostApis(api2: sk2);
      EntitlementToken.update(null);
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      EntitlementToken.update(null);
      EntitlementToken.refresher = null;
    });

    final canceled = PlatformException(
        code: 'storekit2_failed_to_sync_to_app_store',
        message: 'Storekit has failed to sync to the app store.',
        details: 'userCancelled');

    test('isSyncCanceled: only the user canceling the prompt counts', () {
      expect(AppStoreService.isSyncCanceled(canceled), isTrue);
      expect(
          AppStoreService.isSyncCanceled(PlatformException(
              code: 'storekit2_failed_to_sync_to_app_store', details: 'Error Domain=SKErrorDomain paymentCancelled')),
          isTrue);
      expect(
          AppStoreService.isSyncCanceled(PlatformException(
              code: 'storekit2_failed_to_sync_to_app_store', details: 'networkError(NSURLErrorDomain -1009)')),
          isFalse);
      expect(AppStoreService.isSyncCanceled(StateError('userCancelled')), isFalse, reason: 'not a plugin error');
    });

    testWidgets('a product answer that arrives after the retry timed out still notifies (redraws the paywall)',
        (tester) async {
      final iap = _Iap();
      final store = _store(iap);
      await tester.runAsync(store.init);
      expect(store.canPurchase, isFalse);
      iap
        ..products = [_product()]
        ..queryGate = Completer<void>();
      var notified = 0;
      store.addListener(() => notified++);
      final retry = store.retryProduct();
      // Let the query start (and pass the fake's own checks) before time moves.
      for (var i = 0; i < 10 && iap.queries < 2; i++) {
        await Future<void>.value();
      }
      expect(iap.queries, 2);
      await tester.pump(const Duration(seconds: 11));
      // retryProduct gave up waiting (10 s) and notified; the query still runs.
      expect(store.loadingProduct, isFalse);
      expect(store.canPurchase, isFalse);
      final before = notified;
      iap.queryGate!.complete();
      await tester.pump(const Duration(milliseconds: 10));
      await retry;
      expect(store.canPurchase, isTrue);
      expect(store.storePrice, r'$19.99');
      expect(notified, greaterThan(before), reason: 'the late result notifies listeners itself');
      expect(store.isEntitled, isFalse, reason: 'loading the product never unlocks');
    });

    testWidgets('the paywall redraws when that late answer arrives: price and Subscribe enabled', (tester) async {
      final iap = _Iap();
      final store = _store(iap);
      await tester.runAsync(store.init);
      iap
        ..products = [_product()]
        ..queryGate = Completer<void>();
      await pumpApp(tester, prefs: onboardedPrefs(), store: store);
      // Opening the paywall retried; it times out after 10 s.
      await tester.pump(const Duration(seconds: 11));
      expect(tester.widget<DwButton>(find.byKey(const ValueKey('paywall-subscribe'))).onPressed, isNull);
      iap.queryGate!.complete();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      final subscribe = tester.widget<DwButton>(find.byKey(const ValueKey('paywall-subscribe')));
      expect(subscribe.onPressed, isNotNull);
      expect(subscribe.label, contains(r'$19.99'));
      await tester.pumpAndSettle();
    });

    test('Restore: the user cancels the Apple Account prompt: no error, nothing unlocked', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sk2.syncError = canceled;
      final iap = _Iap()..products = [_product()];
      final store = _store(iap);
      await store.init();
      expect(await store.restore(), isFalse);
      expect(store.lastRestoreCanceled, isTrue);
      expect(store.lastError, isNull);
      expect(store.isEntitled, isFalse);
      expect(iap.restores, 1, reason: 'the local entitlement read still happens');
    });

    test('Restore: canceled prompt but StoreKit holds the subscription: restored', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sk2
        ..syncError = canceled
        ..entitled = [StoreConfig.productId];
      final store = _store(_Iap()..products = [_product()]);
      await store.init();
      expect(await store.restore(), isTrue);
      expect(store.lastRestoreCanceled, isFalse);
      expect(store.lastError, isNull);
    });

    test('Restore: a canceled prompt keeps a product error (Try again stays)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sk2.syncError = canceled;
      final store = _store(_Iap());
      await store.init();
      expect(await store.restore(), isFalse);
      expect(store.lastError, StoreError.productUnavailable);
    });

    test('Restore: any other sync failure is still restoreFailed', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sk2.syncError = PlatformException(
          code: 'storekit2_failed_to_sync_to_app_store', details: 'networkError(NSURLErrorDomain -1009)');
      final store = _store(_Iap()..products = [_product()]);
      await store.init();
      expect(await store.restore(), isFalse);
      expect(store.lastRestoreCanceled, isFalse);
      expect(store.lastError, StoreError.restoreFailed);
    });

    testWidgets('paywall: canceling the Restore sign-in shows no message', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sk2.syncError = canceled;
      final store = _store(_Iap()..products = [_product()]);
      await tester.runAsync(store.init);
      await pumpApp(tester, prefs: onboardedPrefs(), store: store);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('paywall-restore')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('paywall-restore')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(sk2.syncs, 1);
      expect(find.byKey(const ValueKey('paywall-message')), findsNothing);
      expect(find.byKey(const ValueKey('paywall')), findsOneWidget, reason: 'still locked');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('You › Restore: canceling the sign-in shows no snackbar', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sk2
        ..syncError = canceled
        ..entitled = [StoreConfig.productId];
      final store = _store(_Iap()..products = [_product()]);
      await tester.runAsync(store.init);
      await pumpApp(tester, prefs: onboardedPrefs(), store: store, tab: AppTab.you);
      await tester.pumpAndSettle();
      // Subscribed, so You is reachable; now the subscription is gone and the
      // user cancels the sign-in.
      sk2.entitled = [];
      final row = find.byKey(const ValueKey('row-restore'));
      await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
      await tester.runAsync(() async {
        await tester.tap(row);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(sk2.syncs, 1);
      expect(find.byKey(const ValueKey('restore-result')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Store status readout in Spanish', (tester) async {
      final store = _store(_Iap());
      await tester.runAsync(store.init);
      await pumpApp(tester, prefs: spanishPrefs(), store: store);
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey('paywall-plan')));
      await tester.pumpAndSettle();
      expect(find.text('Estado de la tienda'), findsOneWidget);
      expect(find.text('Store status'), findsNothing);
      expect(find.text('Consultar de nuevo'), findsOneWidget);
      expect(find.text('Copiar'), findsOneWidget);
      expect(find.textContaining('Productos recibidos: '), findsOneWidget);
      expect(find.textContaining('Id del producto consultado: '), findsOneWidget);
      expect(find.textContaining('datewise_premium_monthly'), findsWidgets);
      for (final f in StoreStatusField.values) {
        expect(find.textContaining('${f.english}: '), f == StoreStatusField.storeKit2 ? findsOneWidget : findsNothing,
            reason: '${f.name} is translated (StoreKit 2 is a name)');
      }
      // Copy keeps the English readout for support.
      expect(store.diagnostics.toString(), contains('Products returned: '));
    });

    testWidgets('Store status readout without StoreKit, in Spanish', (tester) async {
      await pumpApp(tester, prefs: spanishPrefs(), store: FakeStoreService(entitled: true), tab: AppTab.you);
      await tester.pumpAndSettle();
      final footnote = find.byKey(const ValueKey('settings-footnote'));
      await tester.scrollUntilVisible(footnote, 300, scrollable: find.byType(Scrollable).first);
      await tester.longPress(footnote);
      await tester.pumpAndSettle();
      expect(find.text('Estado de la tienda'), findsOneWidget);
      expect(find.textContaining('sin StoreKit en esta versión'), findsOneWidget);
    });
  });

  testWidgets('You › About: long-press on the version line opens the Store status readout', (tester) async {
    await pumpApp(tester, prefs: onboardedPrefs(), store: FakeStoreService(entitled: true), tab: AppTab.you);
    await tester.pumpAndSettle();
    final footnote = find.byKey(const ValueKey('settings-footnote'));
    await tester.scrollUntilVisible(footnote, 300, scrollable: find.byType(Scrollable).first);
    await tester.longPress(footnote);
    await tester.pumpAndSettle();
    expect(find.text('Store status'), findsOneWidget);
    expect(find.textContaining('no StoreKit in this build'), findsOneWidget);
  });
}

/// Delegates to [_Iap] but cannot read the storefront.
class _NoCountryIap extends _Iap {
  _NoCountryIap(this.inner);
  final _Iap inner;

  @override
  Future<String> countryCode() async => throw StateError('storekit2_failed_to_fetch_country_code');
}
