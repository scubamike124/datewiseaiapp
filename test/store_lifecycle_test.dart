import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datewise_ai/services/coach_usage.dart';
import 'package:datewise_ai/services/owner_access.dart';
import 'package:datewise_ai/services/store_service.dart';

/// Only the members the store touches before any purchase; anything else fails loudly.
class _QuietIap extends Fake implements InAppPurchase {
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();

  @override
  Future<bool> isAvailable() async => false;
}

/// Availability stays pending until the test completes it, so the store is disposed while it waits.
class _PendingAvailabilityIap extends Fake implements InAppPurchase {
  _PendingAvailabilityIap(this._avail);
  final Completer<bool> _avail;
  int listens = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream {
    listens++;
    return const Stream.empty();
  }

  @override
  Future<bool> isAvailable() => _avail.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a disposed store releases the entitlement refresher hook it installed', () {
    final store = AppStoreService(iap: _QuietIap(), appStoreSync: () async {});
    expect(EntitlementToken.refresher, isNotNull, reason: 'the live store installs the hook');
    store.dispose();
    expect(EntitlementToken.refresher, isNull, reason: 'a disposed store must not stay reachable through the hook');
  });

  test('owner-access changes after dispose do not reach the disposed store', () async {
    final store = AppStoreService(iap: _QuietIap(), appStoreSync: () async {});
    var notified = 0;
    store.addListener(() => notified++);
    store.dispose();
    // Notifies every owner-access listener. A disposed store must not be one of them, and must not throw.
    await OwnerAccess.instance.clear();
    expect(notified, 0, reason: 'a disposed store must not notify its listeners');
  });

  test('a store disposed while availability is pending never starts a purchase-stream listener', () async {
    final avail = Completer<bool>();
    final iap = _PendingAvailabilityIap(avail);
    final store = AppStoreService(iap: iap, appStoreSync: () async {});
    store.dispose();
    avail.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(iap.listens, 0, reason: 'a disposed store must not subscribe to the purchase stream');
  });

  test('a second store replaces the hook, and disposing the first does not clear the second', () {
    final first = AppStoreService(iap: _QuietIap(), appStoreSync: () async {});
    final second = AppStoreService(iap: _QuietIap(), appStoreSync: () async {});
    first.dispose();
    expect(EntitlementToken.refresher, isNotNull, reason: 'the live second store keeps its hook');
    second.dispose();
    expect(EntitlementToken.refresher, isNull);
  });
}
