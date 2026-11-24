// QA: subscription logic of AppStoreService (lib/services/store_service.dart)
// and the chat gate in AppState, driven by a scripted InAppPurchase and, for
// the iOS path, a fake StoreKit 2 host API (Transaction.currentEntitlements).
//
// The defects listed in docs/qa/SUBSCRIPTION_PRIVACY_REPORT.md (D1, D2, D3,
// D10) are fixed; their tests now run unskipped.

// The StoreKit 2 host API can only be replaced through the plugin's
// @visibleForTesting hook, which lives in src/.
// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/src/in_app_purchase_apis.dart' show setInAppPurchaseHostApis;
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/models/user_profile.dart';
import 'package:datewise_ai/services/ai_service.dart';
import 'package:datewise_ai/services/coach_usage.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/state/app_state.dart';

import 'helpers.dart';

ProductDetails _product({String price = r'$19.99'}) => ProductDetails(
      id: StoreConfig.productId,
      title: 'DateWise Premium Monthly',
      description: 'Chat and voice coaching with all four AI coaches.',
      price: price,
      rawPrice: 19.99,
      currencyCode: 'USD',
    );

PurchaseDetails _details(PurchaseStatus status, {String productId = StoreConfig.productId, bool pendingComplete = true}) {
  final d = PurchaseDetails(
    purchaseID: 'tx-${status.name}',
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'jws',
      serverVerificationData: 'jws',
      source: 'app_store',
    ),
    transactionDate: '0',
    status: status,
  );
  if (status == PurchaseStatus.error) d.error = IAPError(source: 'app_store', code: 'x', message: 'failed');
  d.pendingCompletePurchase = pendingComplete;
  return d;
}

/// An InAppPurchase whose purchase stream the test scripts.
class _ScriptedIap implements InAppPurchase {
  _ScriptedIap({this.available = true, this.owned = false, this.restoreDelay});

  bool available;

  /// Whether the store holds an active subscription for this account
  /// (re-delivered as `restored` by restorePurchases, like Google Play).
  bool owned;

  /// When set, restored purchases arrive this long after restorePurchases
  /// returns (Google Play delivers them asynchronously).
  Duration? restoreDelay;

  /// What the next buy reports on the purchase stream.
  List<PurchaseStatus> onBuy = [PurchaseStatus.purchased];
  bool buyThrows = false;

  final stream = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <PurchaseDetails>[];
  /// Purchase ids whose completePurchase throws (the plugin's null-check
  /// error for a StoreKit Test transaction with id 0).
  final Set<String?> completeThrowsFor = {};
  int buys = 0;
  int restores = 0;

  void emit(List<PurchaseDetails> list) => stream.add(list);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => stream.stream;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async =>
      ProductDetailsResponse(productDetails: [_product()], notFoundIDs: const []);

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buys++;
    expect(purchaseParam.productDetails.id, StoreConfig.productId);
    if (buyThrows) throw StateError('StoreKit error');
    for (final s in onBuy) {
      scheduleMicrotask(() => emit([_details(s)]));
    }
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restores++;
    if (!owned) return;
    final d = _details(PurchaseStatus.restored);
    if (restoreDelay == null) {
      scheduleMicrotask(() => emit([d]));
    } else {
      Timer(restoreDelay!, () => emit([d]));
    }
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (completeThrowsFor.contains(purchase.purchaseID)) throw TypeError();
    completed.add(purchase);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// StoreKit 2 host API: only what AppStoreService uses (currentEntitlements).
class _FakeSK2 implements InAppPurchase2API {
  /// AppStore.sync (Restore purchases): counted; throws when [syncFails].
  int syncs = 0;
  bool syncFails = false;

  @override
  Future<void> sync() async {
    syncs++;
    if (syncFails) throw StateError('AppStore.sync failed');
  }

  List<String> entitled = [];
  bool fail = false;

  /// Fail only the next [failTimes] reads.
  int failTimes = 0;
  int calls = 0;

  @override
  Future<List<SK2TransactionMessage>> currentEntitlements() async {
    calls++;
    if (fail) throw StateError('App Store unreachable');
    if (failTimes > 0) {
      failTimes--;
      throw StateError('App Store unreachable');
    }
    return [
      for (final id in entitled)
        SK2TransactionMessage(id: 1, originalId: 1, productId: id, status: SK2PurchaseStatusMessage.purchased),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts the requests that would reach the coach backend.
class _CountingAI implements AIService {
  int calls = 0;
  @override
  String get providerLabel => 'counting';
  @override
  Stream<String> streamReply({
    required List<ChatMessage> history,
    required SubscriptionTier tier,
    UserProfile? profile,
    Coach? coach,
  }) {
    calls++;
    return Stream.fromIterable(['ok']);
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StoreKit purchase results (Google Play / generic path)', () {
    test('success: entitled, purchased, completePurchase called once', () async {
      final iap = _ScriptedIap();
      final store = AppStoreService(iap: iap);
      await store.init();
      expect(store.canPurchase, isTrue);
      expect(store.storePrice, r'$19.99');
      final r = await store.buy();
      await _settle();
      expect(r, PurchaseResult.purchased);
      expect(store.isEntitled, isTrue);
      expect(store.busy, isFalse);
      expect(store.lastError, isNull);
      expect(iap.completed.map((p) => p.status), [PurchaseStatus.purchased]);
    });

    test('pending (Ask to Buy): not entitled yet; unlocks when the approval arrives', () async {
      final iap = _ScriptedIap()..onBuy = [PurchaseStatus.pending];
      final store = AppStoreService(iap: iap);
      await store.init();
      final r = await store.buy();
      await _settle();
      expect(r, PurchaseResult.pending);
      expect(store.isEntitled, isFalse);
      expect(store.busy, isFalse);
      iap.emit([_details(PurchaseStatus.purchased)]);
      await _settle();
      expect(store.isEntitled, isTrue);
      expect(iap.completed.last.status, PurchaseStatus.purchased);
    });

    test('a completePurchase failure is contained: purchased, entitled, the rest of the batch handled', () async {
      final iap = _ScriptedIap()..completeThrowsFor.add('tx-purchased');
      final store = AppStoreService(iap: iap);
      await store.init();
      var notified = 0;
      store.addListener(() => notified++);
      final r = await store.buy();
      await _settle();
      expect(r, PurchaseResult.purchased);
      expect(store.isEntitled, isTrue);
      expect(store.busy, isFalse);
      // A stray transaction delivered after the failing one in the same batch is still finished.
      notified = 0;
      iap.emit([_details(PurchaseStatus.purchased), _details(PurchaseStatus.restored, productId: 'old_iap')]);
      await _settle();
      expect(iap.completed.map((p) => p.productID), ['old_iap']);
      expect(notified, greaterThan(0));
    });

    test('error: failed, purchaseFailed shown, not entitled, transaction still completed', () async {
      final iap = _ScriptedIap()..onBuy = [PurchaseStatus.error];
      final store = AppStoreService(iap: iap);
      await store.init();
      final r = await store.buy();
      await _settle();
      expect(r, PurchaseResult.failed);
      expect(store.lastError, StoreError.purchaseFailed);
      expect(store.isEntitled, isFalse);
      expect(iap.completed.map((p) => p.status), [PurchaseStatus.error]);
    });

    test('cancel: canceled, no error message, not entitled', () async {
      final iap = _ScriptedIap()..onBuy = [PurchaseStatus.canceled];
      final store = AppStoreService(iap: iap);
      await store.init();
      final r = await store.buy();
      await _settle();
      expect(r, PurchaseResult.canceled);
      expect(store.lastError, isNull);
      expect(store.isEntitled, isFalse);
      expect(store.busy, isFalse);
    });

    test('the plugin throwing on buy: failed, not busy', () async {
      final iap = _ScriptedIap()..buyThrows = true;
      final store = AppStoreService(iap: iap);
      await store.init();
      expect(await store.buy(), PurchaseResult.failed);
      expect(store.lastError, StoreError.purchaseFailed);
      expect(store.busy, isFalse);
    });

    test('store unavailable: nothing can be bought', () async {
      final store = AppStoreService(iap: _ScriptedIap(available: false));
      await store.init();
      expect(store.ready, isTrue);
      expect(store.canPurchase, isFalse);
      expect(store.lastError, StoreError.storeUnavailable);
      expect(await store.buy(), PurchaseResult.unavailable);
    });

    test('a transaction for another product id never unlocks chat', () async {
      final iap = _ScriptedIap();
      final store = AppStoreService(iap: iap);
      await store.init();
      iap.emit([_details(PurchaseStatus.purchased, productId: 'datewise_premium_yearly')]);
      await _settle();
      expect(store.isEntitled, isFalse);
      // D10: the stray transaction is still finished, so it is not redelivered.
      expect(iap.completed.map((p) => p.productID), ['datewise_premium_yearly']);
    });

    test('restore with a prior purchase: entitled', () async {
      final iap = _ScriptedIap(owned: true);
      final store = AppStoreService(iap: iap);
      await store.init();
      await _settle();
      // On Play, init itself re-delivers the active purchase.
      expect(store.isEntitled, isTrue);
      expect(await store.restore(), isTrue);
    });

    test('restore without a prior purchase: false, no error, still locked', () async {
      final iap = _ScriptedIap();
      final store = AppStoreService(iap: iap);
      await store.init();
      expect(await store.restore(), isFalse);
      expect(store.isEntitled, isFalse);
      expect(store.lastError, isNull);
      expect(store.busy, isFalse);
    });

    test('restore() waits for asynchronously re-delivered purchases (Google Play)', () async {
      final iap = _ScriptedIap(owned: true, restoreDelay: const Duration(milliseconds: 50));
      final store = AppStoreService(iap: iap);
      await store.init();
      expect(await store.restore(), isTrue, reason: 'the paywall would say "no subscription found"');
    });

    test('a lapsed subscription locks chat again after refresh (Google Play)', () async {
      final iap = _ScriptedIap(owned: true);
      final store = AppStoreService(iap: iap);
      await store.init();
      await _settle();
      expect(store.isEntitled, isTrue);
      iap.owned = false; // expired / canceled
      await store.refresh();
      await _settle();
      expect(store.isEntitled, isFalse);
    });
  });

  group('StoreKit 2 entitlement (iOS path)', () {
    late _FakeSK2 sk2;
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sk2 = _FakeSK2();
      setInAppPurchaseHostApis(api2: sk2);
    });
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('launch reads Transaction.currentEntitlements: subscriber is entitled', () async {
      sk2.entitled = [StoreConfig.productId];
      final store = AppStoreService(iap: _ScriptedIap());
      await store.init();
      expect(sk2.calls, 1);
      expect(store.isEntitled, isTrue);
      expect(store.manageUrl, StoreConfig.appleManageUrl);
    });

    test('launch without a current entitlement: locked', () async {
      final store = AppStoreService(iap: _ScriptedIap());
      await store.init();
      expect(store.isEntitled, isFalse);
    });

    test('an entitlement for another product does not count', () async {
      sk2.entitled = ['some_other_product'];
      final store = AppStoreService(iap: _ScriptedIap());
      await store.init();
      expect(store.isEntitled, isFalse);
    });

    test('expired while the app was in the background: refresh() (on resume) locks chat and sending', () async {
      SharedPreferences.setMockInitialValues(onboardedPrefs());
      sk2.entitled = [StoreConfig.productId];
      final store = AppStoreService(iap: _ScriptedIap());
      await store.init();
      final ai = _CountingAI();
      final state = AppState(storage: await StorageService.create(), ai: ai, store: store);
      expect(state.canChat, isTrue);
      expect(await state.sendMessage('hello'), isTrue);
      await _settle();
      expect(ai.calls, 1);

      sk2.entitled = []; // StoreKit drops expired / refunded subscriptions
      await store.refresh();
      expect(store.isEntitled, isFalse);
      expect(state.canChat, isFalse);
      expect(await state.sendMessage('again'), isFalse);
      expect(await state.retryLastReply(), isFalse);
      expect(ai.calls, 1, reason: 'nothing reaches the backend once the subscription lapsed');
    });

    test('App Store unreachable on refresh: the last known state is kept', () async {
      sk2.entitled = [StoreConfig.productId];
      final store = AppStoreService(iap: _ScriptedIap());
      await store.init();
      sk2.fail = true;
      await store.refresh();
      expect(store.isEntitled, isTrue);
    });

    test('restore with a prior purchase (new phone): entitled', () async {
      final iap = _ScriptedIap();
      final store = AppStoreService(iap: iap);
      await store.init();
      expect(store.isEntitled, isFalse);
      sk2.entitled = [StoreConfig.productId]; // after AppStore.sync
      expect(await store.restore(), isTrue);
      expect(iap.restores, 1);
    });

    test('restore without a prior purchase: false and locked', () async {
      final store = AppStoreService(iap: _ScriptedIap());
      await store.init();
      expect(await store.restore(), isFalse);
      expect(store.isEntitled, isFalse);
      expect(store.lastError, isNull);
    });

    test('restore failing: restoreFailed, locked', () async {
      final store = AppStoreService(iap: _ScriptedIap());
      await store.init();
      sk2.fail = true;
      expect(await store.restore(), isFalse);
      expect(store.lastError, StoreError.restoreFailed);
    });

    test('a Transaction.updates event is re-checked against currentEntitlements', () async {
      // Transaction.updates also delivers unfinished renewals for a period that
      // has since ended, and refunds/revocations; the plugin reports all of
      // them as "purchased". The app should ask currentEntitlements instead
      // of trusting the event.
      final iap = _ScriptedIap();
      final store = AppStoreService(iap: iap);
      await store.init();
      expect(store.isEntitled, isFalse);
      iap.emit([_details(PurchaseStatus.purchased)]);
      await _settle();
      expect(store.isEntitled, isFalse);
    });
  });

  group('StoreKit 2 re-read fails on a Transaction.updates event', () {
    late _FakeSK2 sk2;
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sk2 = _FakeSK2();
      setInAppPurchaseHostApis(api2: sk2);
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      EntitlementToken.update(null);
    });

    PurchaseDetails withJws(String jws) => PurchaseDetails(
          purchaseID: 'tx-update',
          productID: StoreConfig.productId,
          verificationData: PurchaseVerificationData(localVerificationData: jws, serverVerificationData: jws, source: 'app_store'),
          transactionDate: '0',
          status: PurchaseStatus.purchased,
        )..pendingCompletePurchase = true;

    test('not entitled before: stays locked; only the token is updated', () async {
      final iap = _ScriptedIap();
      final store = AppStoreService(iap: iap);
      await store.init();
      expect(store.isEntitled, isFalse);
      sk2.fail = true;
      iap.emit([withJws('aaa.bbb.ccc')]);
      await _settle();
      expect(store.isEntitled, isFalse, reason: 'the event alone does not unlock chat');
      expect(EntitlementToken.current, 'aaa.bbb.ccc');
    });

    test('entitled before: stays entitled; the token is updated', () async {
      sk2.entitled = [StoreConfig.productId];
      final iap = _ScriptedIap();
      final store = AppStoreService(iap: iap);
      await store.init();
      expect(store.isEntitled, isTrue);
      sk2.fail = true;
      iap.emit([withJws('new.jws.token')]);
      await _settle();
      expect(store.isEntitled, isTrue);
      expect(EntitlementToken.current, 'new.jws.token');
    });

    test('a purchase the user made: one delayed re-read, then entitled', () async {
      final iap = _ScriptedIap();
      final store = AppStoreService(iap: iap, purchaseRereadDelay: const Duration(milliseconds: 10));
      await store.init();
      sk2.entitled = [StoreConfig.productId];
      sk2.failTimes = 1;
      final before = sk2.calls;
      expect(await store.buy(), PurchaseResult.purchased);
      expect(sk2.calls - before, 2, reason: 'first re-read failed, the delayed one succeeded');
      expect(store.isEntitled, isTrue);
    });

    test('a purchase the user made: both re-reads fail, reported pending (not failed)', () async {
      final iap = _ScriptedIap();
      final store = AppStoreService(iap: iap, purchaseRereadDelay: const Duration(milliseconds: 10));
      await store.init();
      sk2.fail = true;
      expect(await store.buy(), PurchaseResult.pending,
          reason: 'the user paid; say it unlocks when confirmed instead of prompting a second purchase');
      expect(store.isEntitled, isFalse);
    });
  });

  group('entitlement is not cached on the device (cannot be spoofed via SharedPreferences)', () {
    test('buying writes no entitlement to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(onboardedPrefs());
      final storage = await StorageService.create();
      final iap = _ScriptedIap();
      final store = AppStoreService(iap: iap);
      await store.init();
      AppState(storage: storage, ai: _CountingAI(), store: store);
      final before = (await SharedPreferences.getInstance()).getKeys();
      await store.buy();
      await _settle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), before);
      for (final k in prefs.getKeys()) {
        expect(k, isNot(matches(RegExp('premium|entitle|subscri|tier', caseSensitive: false))));
      }
    });

    test('forged prefs (legacy tier, premium flags) do not unlock chat', () async {
      SharedPreferences.setMockInitialValues({
        ...onboardedPrefs(),
        'dw_tier': 'magnet',
        'dw_premium': true,
        'dw_entitled': true,
        'dw_subscription': 'active',
      });
      final ai = _CountingAI();
      final store = AppStoreService(iap: _ScriptedIap());
      await store.init();
      final state = AppState(storage: await StorageService.create(), ai: ai, store: store);
      expect(store.isEntitled, isFalse);
      expect(state.canChat, isFalse);
      expect(await state.sendMessage('hi'), isFalse);
      expect(ai.calls, 0);
    });
  });

  group('one paid plan: \$19.99 / month, no intro offer', () {
    test('DateWise.storekit has exactly one auto-renewable product', () {
      final j = jsonDecode(File('ios/Runner/DateWise.storekit').readAsStringSync()) as Map<String, dynamic>;
      expect(j['products'], isEmpty, reason: 'no consumables / non-consumables');
      expect(j['nonRenewingSubscriptions'], isEmpty);
      final groups = j['subscriptionGroups'] as List;
      expect(groups, hasLength(1));
      final subs = (groups.single as Map)['subscriptions'] as List;
      expect(subs, hasLength(1));
      final s = subs.single as Map;
      expect(s['productID'], StoreConfig.productId);
      expect(s['type'], 'RecurringSubscription');
      expect(s['recurringSubscriptionPeriod'], 'P1M');
      expect(s['displayPrice'], '19.99');
      expect(s['introductoryOffer'], isNull);
      expect(s['adHocOffers'], isEmpty);
      expect(s['codeOffers'], isEmpty);
      expect(s['winbackOffers'], isEmpty);
      expect(s['familyShareable'], isFalse);
    });

    test('the paywall shows only the StoreKit price string (no hard-coded \$19.99 in lib)', () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
        // FakeStoreService's default price is the only allowed literal.
        final src = f.readAsStringSync().replaceAll(r"String? price = r'$19.99'", '');
        final lines = src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
        expect(RegExp(r'(?<![\d.])\d+[.,]99(?!\d)').hasMatch(lines), isFalse, reason: f.path);
      }
      // Translations take the price as a parameter; they never carry an amount or a currency.
      for (final f in Directory('lib/l10n').listSync().whereType<File>()) {
        final src = f.readAsStringSync();
        expect(RegExp(r'\d[.,]\d\d(?!\d)|US\$|USD|€').hasMatch(src), isFalse, reason: f.path);
      }
    });

    test('App Store metadata states one monthly plan at USD 19.99 with no intro offer', () {
      final md = File('docs/appstore/metadata.md').readAsStringSync();
      expect(md, contains('`datewise_premium_monthly`'));
      expect(md, contains('| Duration | 1 month |'));
      expect(md, contains('| Price | USD 19.99'));
      expect(md, contains('| Introductory offer / free trial | None |'));
      expect(md, contains(r'$19.99/month in the U.S.'));
      expect(md, contains(r'US$19.99 al mes en EE. UU.'));
      expect(RegExp(r'(?<![0-9])9[.,]99').hasMatch(md), isFalse, reason: 'no stale \$9.99');
    });
  });
}
