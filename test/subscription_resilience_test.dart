// Subscription resilience on the device (lib/services/store_service.dart):
// a paying subscriber is not locked out by a temporary StoreKit failure, and
// always has an action (Restore purchases, Try again). The server side is in
// backend/subscription_resilience.test.mjs; the analysis is in
// docs/qa/SUBSCRIPTION_RESILIENCE.md.

// The StoreKit 2 host API can only be replaced through the plugin's
// @visibleForTesting hook, which lives in src/.
// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/src/in_app_purchase_apis.dart' show setInAppPurchaseHostApis;
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'package:datewise_ai/l10n/app_localizations.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/tier.dart';
import 'package:datewise_ai/services/backend_ai_service.dart';
import 'package:datewise_ai/services/coach_usage.dart';
import 'package:datewise_ai/screens/paywall_screen.dart' show restoreFailureText;
import 'package:datewise_ai/services/store_service.dart';

class _Iap implements InAppPurchase {
  bool available = true;
  bool availableThrows = false;
  bool restoreThrows = false;
  int restores = 0;
  final stream = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <PurchaseDetails>[];

  @override
  Future<bool> isAvailable() async {
    if (availableThrows) throw StateError('StoreKit hiccup');
    return available;
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => stream.stream;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async => ProductDetailsResponse(
        productDetails: [
          ProductDetails(id: StoreConfig.productId, title: 'DateWise Premium Monthly', description: '', price: r'$9.99', rawPrice: 9.99, currencyCode: 'USD'),
        ],
        notFoundIDs: const [],
      );

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restores++;
    if (restoreThrows) throw StateError('AppStore.sync failed');
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async => completed.add(purchase);

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SK2 implements InAppPurchase2API {
  /// (productId, receiptData JWS, expiration ms since epoch)
  List<(String, String, double?)> entitled = [];
  int failTimes = 0;
  int hangTimes = 0;
  bool fail = false;
  int calls = 0;

  /// When non-empty, each read waits on the next completer (the test completes them).
  final gates = <Completer<List<SK2TransactionMessage>>>[];

  @override
  Future<List<SK2TransactionMessage>> currentEntitlements() async {
    calls++;
    if (gates.isNotEmpty) return gates.removeAt(0).future;
    if (hangTimes > 0) {
      hangTimes--;
      return Completer<List<SK2TransactionMessage>>().future; // never completes
    }
    if (fail) throw StateError('StoreKit unreachable');
    if (failTimes > 0) {
      failTimes--;
      throw StateError('StoreKit unreachable');
    }
    var id = 0;
    return [
      for (final (product, jws, exp) in entitled)
        SK2TransactionMessage(
            id: ++id, originalId: 1, productId: product, status: SK2PurchaseStatusMessage.purchased, receiptData: jws, expirationDate: exp == null ? null : exp / 1000),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SK2TransactionMessage _msg(String product, String jws) =>
    SK2TransactionMessage(id: 1, originalId: 1, productId: product, status: SK2PurchaseStatusMessage.purchased, receiptData: jws);

const _jwsA = 'aaa.bbb.ccc';
const _jwsB = 'ddd.eee.fff';
final _soon = DateTime.utc(2026, 12, 1).millisecondsSinceEpoch.toDouble();
final _later = DateTime.utc(2026, 12, 31).millisecondsSinceEpoch.toDouble();

AppStoreService _store(_Iap iap) => AppStoreService(
      iap: iap,
      launchRereadDelay: Duration.zero,
      launchReadTimeout: const Duration(milliseconds: 50),
      purchaseRereadDelay: Duration.zero,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  group('launch: a temporary StoreKit failure does not show a subscriber the paywall', () {
    test('currentEntitlements fails once: read again, entitled, token set', () async {
      sk2.entitled = [(StoreConfig.productId, _jwsA, _soon)];
      sk2.failTimes = 1;
      final store = _store(_Iap());
      await store.init();
      expect(sk2.calls, 2);
      expect(store.ready, isTrue);
      expect(store.isEntitled, isTrue);
      expect(EntitlementToken.current, _jwsA);
    });

    test('currentEntitlements hangs once: times out, read again, entitled', () async {
      sk2.entitled = [(StoreConfig.productId, _jwsA, _soon)];
      sk2.hangTimes = 1;
      final store = _store(_Iap());
      await store.init();
      expect(store.isEntitled, isTrue);
      expect(store.storePrice, r'$9.99');
    });

    test('both reads fail: the paywall can say "Could not reach the App Store" and Restore works later', () async {
      sk2.entitled = [(StoreConfig.productId, _jwsA, _soon)];
      sk2.fail = true;
      final iap = _Iap();
      final store = _store(iap);
      await store.init();
      expect(store.ready, isTrue);
      expect(store.isEntitled, isFalse);
      // Restore purchases (always on the paywall) succeeds once StoreKit answers.
      sk2.fail = false;
      expect(await store.restore(), isTrue);
      expect(store.lastError, isNull);
      expect(EntitlementToken.current, _jwsA);
    });

    test('the next resume (refresh) also recovers it', () async {
      sk2.entitled = [(StoreConfig.productId, _jwsA, _soon)];
      sk2.fail = true;
      final store = _store(_Iap());
      await store.init();
      sk2.fail = false;
      await store.refresh();
      expect(store.isEntitled, isTrue);
    });

    test('purchases unavailable on iOS (Screen Time restriction, a StoreKit hiccup): an active subscriber keeps chat', () async {
      sk2.entitled = [(StoreConfig.productId, _jwsA, _soon)];
      for (final iap in [_Iap()..available = false, _Iap()..availableThrows = true]) {
        final store = _store(iap);
        await store.init();
        expect(store.isEntitled, isTrue);
        expect(store.canPurchase, isFalse);
        expect(EntitlementToken.current, _jwsA);
        // Restore and refresh still read the local entitlement.
        expect(await store.restore(), isTrue);
        sk2.entitled = [];
        await store.refresh();
        expect(store.isEntitled, isFalse, reason: 'a lapsed subscription still locks chat');
        sk2.entitled = [(StoreConfig.productId, _jwsA, _soon)];
      }
    });
  });

  group('restore on a new device', () {
    test('AppStore.sync fails (offline, sign-in canceled) but StoreKit holds the subscription: restored', () async {
      sk2.entitled = [(StoreConfig.productId, _jwsA, _soon)];
      final iap = _Iap()..restoreThrows = true;
      final store = _store(iap);
      await store.init();
      expect(await store.restore(), isTrue);
      expect(store.lastError, isNull);
      expect(iap.restores, 1);
    });

    test('AppStore.sync fails and nothing is held: restoreFailed (the paywall says try again)', () async {
      final store = _store(_Iap()..restoreThrows = true);
      await store.init();
      expect(await store.restore(), isFalse);
      expect(store.lastError, StoreError.restoreFailed);
    });

    test('no purchase on this Apple ID: false, no error (the paywall says no subscription was found)', () async {
      final store = _store(_Iap());
      await store.init();
      expect(await store.restore(), isFalse);
      expect(store.lastError, isNull);
    });
  });

  group('a stale "Could not reach the App Store" after the store answers', () {
    test('the launch read fails, then Restore finds nothing: "No active subscription found"', () async {
      sk2.fail = true;
      final store = _store(_Iap());
      await store.init();
      expect(store.lastError, StoreError.storeUnreachable);
      sk2.fail = false; // StoreKit answers now; this Apple ID has no subscription
      expect(await store.restore(), isFalse);
      expect(store.lastError, isNull);
      for (final (lang, text) in [('en', 'No active subscription found.'), ('es', 'No se encontró una suscripción activa.')]) {
        final l = lookupAppLocalizations(Locale(lang));
        expect(restoreFailureText(l, store.lastError, l.restoreNone), text);
      }
    });

    test('the launch read fails, then a resume refresh reads it: the unreachable error is cleared', () async {
      sk2.fail = true;
      final store = _store(_Iap());
      await store.init();
      expect(store.lastError, StoreError.storeUnreachable);
      sk2.fail = false;
      await store.refresh();
      expect(store.isEntitled, isFalse);
      expect(store.lastError, isNull);
    });

    test('a refresh whose read fails again keeps the unreachable error', () async {
      sk2.fail = true;
      final store = _store(_Iap());
      await store.init();
      await store.refresh();
      expect(store.lastError, StoreError.storeUnreachable);
    });
  });

  group('unknown product ids', () {
    test('an entitlement for an old or unknown product never unlocks chat and sends no token', () async {
      sk2.entitled = [('old_premium_weekly', _jwsB, _later)];
      final store = _store(_Iap());
      await store.init();
      expect(store.isEntitled, isFalse);
      expect(EntitlementToken.current, isNull);
    });

    test('an unknown product on the purchase stream is completed (finished), not re-delivered forever', () async {
      final iap = _Iap();
      final store = _store(iap);
      await store.init();
      final d = PurchaseDetails(
        purchaseID: 'old-1',
        productID: 'old_premium_weekly',
        verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: '', source: 'app_store'),
        transactionDate: '0',
        status: PurchaseStatus.purchased,
      )..pendingCompletePurchase = true;
      iap.stream.add([d]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(iap.completed.map((p) => p.productID), ['old_premium_weekly']);
      expect(store.isEntitled, isFalse);
    });

    test('with this product and another one, the token is this product\'s, the latest-expiring one', () async {
      sk2.entitled = [('old_premium_weekly', 'old.old.old', _later), (StoreConfig.productId, _jwsA, _soon), (StoreConfig.productId, _jwsB, _later)];
      final store = _store(_Iap());
      await store.init();
      expect(store.isEntitled, isTrue);
      expect(EntitlementToken.current, _jwsB);
    });
  });

  group('a token that renewed mid-session (refresh once, retry once)', () {
    test('the server says SUBSCRIPTION_EXPIRED for the old token; StoreKit has the renewal; the reply arrives', () async {
      sk2.entitled = [(StoreConfig.productId, _jwsA, _soon)];
      final store = _store(_Iap()); // wires EntitlementToken.refresher = store.refresh
      await store.init();
      expect(EntitlementToken.current, _jwsA);
      sk2.entitled = [(StoreConfig.productId, _jwsB, _later)]; // renewed while the app was open
      final seen = <String?>[];
      final svc = BackendAIService(
        endpoint: 'https://example.workers.dev',
        retryDelay: Duration.zero,
        clientFactory: () => MockClient.streaming((req, _) async {
          final token = req.headers['X-DateWise-Entitlement'];
          seen.add(token);
          final ok = token == _jwsB;
          final body = ok ? 'data: {"response":"Hi"}\n\ndata: [DONE]\n\n' : '{"error":"SUBSCRIPTION_EXPIRED","code":"SUBSCRIPTION_EXPIRED"}';
          return http.StreamedResponse(Stream.value(utf8.encode(body)), ok ? 200 : 403);
        }),
      );
      final history = [ChatMessage(id: '1', role: MessageRole.user, text: 'Hi', createdAt: DateTime(2026))];
      expect(await svc.streamReply(history: history, tier: SubscriptionTier.values.last).toList(), ['Hi']);
      expect(seen, [_jwsA, _jwsB]);
      expect(store.isEntitled, isTrue);
    });

    test('StoreKit cannot be re-read: the refusal code reaches the chat (actionable notice + Try again), entitlement kept', () async {
      sk2.entitled = [(StoreConfig.productId, _jwsA, _soon)];
      final store = _store(_Iap());
      await store.init();
      sk2.fail = true;
      var sends = 0;
      final svc = BackendAIService(
        endpoint: 'https://example.workers.dev',
        retryDelay: Duration.zero,
        clientFactory: () => MockClient.streaming((req, _) async {
          sends++;
          return http.StreamedResponse(Stream.value(utf8.encode('{"code":"SUBSCRIPTION_EXPIRED"}')), 403);
        }),
      );
      final history = [ChatMessage(id: '1', role: MessageRole.user, text: 'Hi', createdAt: DateTime(2026))];
      await expectLater(
        svc.streamReply(history: history, tier: SubscriptionTier.values.last).toList(),
        throwsA(isA<CoachUnavailableException>().having((e) => e.code, 'code', CoachLimitCode.subscriptionExpired)),
      );
      expect(sends, 2, reason: 'one refresh, one retry: never more');
      expect(store.isEntitled, isTrue, reason: 'a failed re-read keeps the last known state');
      expect(CoachLimitCode.noInstantRetry.contains(CoachLimitCode.subscriptionExpired), isFalse, reason: 'the chat offers Try again');
    });
  });

  group('entitlement reads that finish out of order', () {
    test('a stale read finishing after a newer one does not overwrite it (generation counter)', () async {
      sk2.entitled = [(StoreConfig.productId, _jwsA, _soon)];
      final store = _store(_Iap());
      await store.init();
      expect(store.isEntitled, isTrue);
      final older = Completer<List<SK2TransactionMessage>>();
      final newer = Completer<List<SK2TransactionMessage>>();
      sk2.gates.addAll([older, newer]);
      final a = store.refresh(); // e.g. a resume read that hangs
      final b = store.refresh(); // a later read (another resume, or the chat's refresh-once)
      await Future<void>.delayed(Duration.zero);
      newer.complete([]); // the newer read: the subscription has ended
      await b;
      expect(store.isEntitled, isFalse);
      expect(EntitlementToken.current, isNull);
      older.complete([_msg(StoreConfig.productId, _jwsA)]); // the stale read arrives late
      await a;
      expect(store.isEntitled, isFalse, reason: 'the stale result is discarded');
      expect(EntitlementToken.current, isNull);
    });

    test('a stale "not entitled" does not lock out a subscriber the newer read found', () async {
      final store = _store(_Iap());
      await store.init();
      expect(store.isEntitled, isFalse);
      final older = Completer<List<SK2TransactionMessage>>();
      final newer = Completer<List<SK2TransactionMessage>>();
      sk2.gates.addAll([older, newer]);
      var notifications = 0;
      store.addListener(() => notifications++);
      final a = store.refresh();
      final b = store.restore();
      await Future<void>.delayed(Duration.zero);
      newer.complete([_msg(StoreConfig.productId, _jwsB)]);
      expect(await b, isTrue);
      final afterNewer = notifications;
      expect(afterNewer, greaterThan(0), reason: 'listeners hear about the change');
      older.complete([]);
      await a;
      expect(store.isEntitled, isTrue);
      expect(EntitlementToken.current, _jwsB);
    });
  });

  group('a purchase whose re-read overlaps a resume refresh', () {
    PurchaseDetails purchased() => PurchaseDetails(
          purchaseID: 'tx-1',
          productID: StoreConfig.productId,
          verificationData: PurchaseVerificationData(localVerificationData: _jwsA, serverVerificationData: _jwsA, source: 'app_store'),
          transactionDate: '0',
          status: PurchaseStatus.purchased,
        );

    Future<(Future<PurchaseResult>, Completer<List<SK2TransactionMessage>>, Completer<List<SK2TransactionMessage>>, Future<void>)>
        overlap(AppStoreService store, _Iap iap) async {
      final purchaseRead = Completer<List<SK2TransactionMessage>>();
      final resumeRead = Completer<List<SK2TransactionMessage>>();
      sk2.gates.addAll([purchaseRead, resumeRead]);
      final callsBefore = sk2.calls;
      final result = store.buy();
      await Future<void>.delayed(Duration.zero);
      iap.stream.add([purchased()]); // StoreKit delivers the purchase; its re-read starts
      await pumpEventQueue();
      expect(sk2.calls, callsBefore + 1);
      final resume = store.refresh(); // the app resumes: a newer read supersedes the purchase's
      await pumpEventQueue();
      expect(sk2.calls, callsBefore + 2);
      return (result, purchaseRead, resumeRead, resume);
    }

    test('the superseded purchase read finishes first: the purchase waits for the newest read, not reported failed', () async {
      final iap = _Iap();
      final store = _store(iap);
      await store.init();
      expect(store.isEntitled, isFalse);
      final (result, purchaseRead, resumeRead, resume) = await overlap(store, iap);
      purchaseRead.complete([_msg(StoreConfig.productId, _jwsA)]); // superseded: discarded
      await pumpEventQueue();
      expect(store.busy, isTrue, reason: 'still waiting for the newest read');
      resumeRead.complete([_msg(StoreConfig.productId, _jwsA)]);
      await resume;
      expect(await result, PurchaseResult.purchased);
      expect(store.isEntitled, isTrue);
      expect(store.lastError, isNull);
      expect(EntitlementToken.current, _jwsA);
    });

    test('the newest read finishes first, or the superseded read fails: still purchased', () async {
      final iap = _Iap();
      final store = _store(iap);
      await store.init();
      final (result, purchaseRead, resumeRead, resume) = await overlap(store, iap);
      resumeRead.complete([_msg(StoreConfig.productId, _jwsA)]);
      await resume;
      purchaseRead.completeError(StateError('stale read failed')); // ignored: superseded
      expect(await result, PurchaseResult.purchased);
      expect(store.isEntitled, isTrue);
    });
  });

  test('a product that loads after failed entitlement reads keeps the "Could not reach the App Store" error', () async {
    sk2.fail = true;
    final store = _store(_Iap());
    await store.init();
    expect(store.storePrice, r'$9.99');
    expect(store.lastError, StoreError.storeUnreachable);
  });

  test('a refusal the guard sends while degraded (GUARD_UNAVAILABLE) is retryable from the chat', () {
    expect(CoachLimitCode.noInstantRetry.contains(CoachLimitCode.guardUnavailable), isFalse);
    expect(CoachLimitCode.noInstantRetry.contains(CoachLimitCode.serviceBudgetExhausted), isFalse);
  });

  test('latestExpiring: the newest expiration wins; a missing date counts as oldest', () {
    SK2Transaction t(String jws, String? exp) =>
        SK2Transaction(id: jws, originalId: '1', productId: StoreConfig.productId, purchaseDate: '0', expirationDate: exp, receiptData: jws, appAccountToken: null);
    expect(AppStoreService.latestExpiring([t('a', '100'), t('b', '300'), t('c', '200')]).receiptData, 'b');
    expect(AppStoreService.latestExpiring([t('a', null), t('b', '1')]).receiptData, 'b');
    expect(AppStoreService.latestExpiring([t('a', null)]).receiptData, 'a');
  });
}
