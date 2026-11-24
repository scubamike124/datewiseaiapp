// Real-StoreKit end-to-end subscription test of the app's own code.
//
// Runs on an iOS simulator under `xcodebuild test` (see
// .github/workflows/storekit-e2e.yml), never under `flutter test` on the host.
// The app's real store (createStoreService() → AppStoreService, the
// in_app_purchase plugin, StoreKit 2) talks to Apple's StoreKit Test
// environment loaded from ios/Runner/DateWise.storekit. The native XCTest
// (ios/RunnerTests/RunnerTests.swift, StoreKitE2ETests) owns the
// SKTestSession and answers the commands sent on [_bridge]: reset, Ask to
// Buy, time rate, expire, renew, refund, cancel auto-renew. Nothing here
// uses FakeStoreService, and this is not App Store sandbox.
//
// Each scenario starts from an empty StoreKit Test history. "Relaunch" builds
// a new AppStoreService and app widget tree (what a cold start does: the
// entitlement is read again from StoreKit); "reinstall" also wipes the app's
// local data first.

import 'dart:async';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/l10n/l10n.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/coach_usage.dart';
import 'package:datewise_ai/services/mock_ai_service.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/services/storage_service.dart';
import 'package:datewise_ai/services/store_service.dart';
import 'package:datewise_ai/services/voice_service.dart';
import 'package:datewise_ai/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bridge = MethodChannel('datewise/storekit_test');
const _product = StoreConfig.productId;

/// Outcome per scenario, sent to the XCTest when all have run.
final _results = <String, String>{};

final _en = lookupAppLocalizations(const Locale('en'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _waitForBridge();
  });

  tearDownAll(() async {
    await _bridge.invokeMethod<void>('done', {'results': _results});
  });

  _scenario('catalog: only the monthly subscription exists, with the StoreKit price', (t) async {
    final app = await _launch(t);
    expect(app.store, isA<AppStoreService>(), reason: 'the real StoreKit store, not FakeStoreService');
    expect(InAppPurchaseStoreKitPlatform.isStoreKit2Enabled, isTrue);
    await _until(t, () => app.store.canPurchase, 'product loaded');
    expect(app.store.storePrice, r'$19.99');
    expect(app.store.isEntitled, isFalse);
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
    expect(find.text(r'$19.99'), findsWidgets, reason: 'the paywall shows the localized StoreKit price');

    // Ask StoreKit for every id a second plan might plausibly use: only the
    // monthly subscription exists (no annual, lifetime, weekly or free plan).
    final res = await InAppPurchase.instance.queryProductDetails({
      _product,
      'datewise_premium_annual',
      'datewise_premium_yearly',
      'datewise_premium_weekly',
      'datewise_premium_lifetime',
      'datewise_lifetime',
      'datewise_free',
      'datewise_premium_free',
      'datewise_premium_trial',
    });
    expect(res.error, isNull);
    expect([for (final p in res.productDetails) p.id], [_product]);
    final p = res.productDetails.single as AppStoreProduct2Details;
    expect(p.sk2Product.type, SK2ProductType.autoRenewable);
    expect(p.sk2Product.subscription!.subscriptionPeriod.unit, SK2SubscriptionPeriodUnit.month);
    expect(p.sk2Product.subscription!.subscriptionPeriod.value, 1);
    expect(p.sk2Product.subscription!.promotionalOffers, isEmpty);
    expect(p.rawPrice, closeTo(19.99, 0.001));
    expect(p.currencyCode, 'USD');
    expect(await _transactions(), isEmpty);
  });

  _scenario('purchase unlocks premium, and it survives a relaunch', (t) async {
    var app = await _launch(t);
    await _subscribe(t, app);
    await _until(t, () => app.store.isEntitled, 'premium after purchase');
    await _until(t, () => find.byType(HomeShell).evaluate().isNotEmpty, 'home after purchase');
    expect(find.byKey(const ValueKey('paywall')), findsNothing);
    _expectJws();
    final txs = await _transactions();
    expect(txs, hasLength(1));
    expect(txs.single['productId'], _product);

    app = await _launch(t);
    expect(app.store.isEntitled, isTrue, reason: 'entitlement read from StoreKit at launch');
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(const ValueKey('paywall')), findsNothing);
    _expectJws();
  });

  _scenario('renewal keeps premium', (t) async {
    var app = await _launch(t);
    await _subscribe(t, app);
    await _until(t, () => app.store.isEntitled, 'premium after purchase');
    await _bridge.invokeMethod<void>('forceRenew', {'productId': _product});
    await _until(t, () async => (await _transactions()).length >= 2, 'renewal transaction');
    await _resume(t);
    await _settle(t);
    expect(app.store.isEntitled, isTrue);
    _expectJws();

    app = await _launch(t);
    expect(app.store.isEntitled, isTrue);
    expect(find.byKey(const ValueKey('paywall')), findsNothing);
  });

  _scenario('expiry removes premium and shows the paywall', (t) async {
    var app = await _launch(t);
    await _subscribe(t, app);
    await _until(t, () => app.store.isEntitled, 'premium after purchase');

    await _bridge.invokeMethod<void>('expire', {'productId': _product});
    await _resume(t); // the app re-reads the entitlement whenever it returns to the foreground
    await _until(t, () => !app.store.isEntitled, 'premium removed after expiry');
    await _until(t, () => find.byKey(const ValueKey('paywall')).evaluate().isNotEmpty, 'paywall after expiry');
    expect(EntitlementToken.current, isNull, reason: 'no JWS is sent for an expired subscription');

    app = await _launch(t);
    expect(app.store.isEntitled, isFalse);
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
  });

  _scenario('cancel auto-renew: premium until the period ends, then removed (accelerated time)', (t) async {
    await _bridge.invokeMethod<void>('setTimeRate', {'rate': 'monthlyRenewalEveryThirtySeconds'});
    final app = await _launch(t);
    await _subscribe(t, app);
    await _until(t, () => app.store.isEntitled, 'premium after purchase');

    // A month passes every 30 seconds: wait for one automatic renewal.
    await _until(t, () async => (await _transactions()).length >= 2, 'automatic renewal',
        timeout: const Duration(seconds: 90));
    await _resume(t);
    await _settle(t);
    expect(app.store.isEntitled, isTrue, reason: 'still premium after the automatic renewal');

    // Cancel (turn off auto-renew) on the latest transaction: premium stays
    // until that period ends, then goes.
    final latest = _latest(await _transactions());
    await _bridge.invokeMethod<void>('disableAutoRenew', {'id': latest['id']});
    await _resume(t);
    await _settle(t);
    final expiresMs = latest['expirationMs'] as int?;
    if (expiresMs != null && DateTime.now().millisecondsSinceEpoch < expiresMs - 3000) {
      expect(app.store.isEntitled, isTrue, reason: 'canceled, but the paid period has not ended');
    }
    await _until(t, () async {
      await _resume(t);
      return !app.store.isEntitled;
    }, 'premium removed when the canceled period ends', timeout: const Duration(seconds: 90));
    final count = (await _transactions()).length;
    await Future<void>.delayed(const Duration(seconds: 35));
    expect((await _transactions()).length, count, reason: 'no renewal after cancellation');
    await _resume(t);
    await _settle(t);
    expect(app.store.isEntitled, isFalse);
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
  });

  _scenario('restore after reinstall: premium back while active, not after expiry', (t) async {
    var app = await _launch(t);
    await _subscribe(t, app);
    await _until(t, () => app.store.isEntitled, 'premium after purchase');

    // Reinstall: local data wiped. StoreKit still holds the subscription.
    app = await _launch(t, wipeData: true);
    expect(app.store.isEntitled, isTrue, reason: 'StoreKit current entitlements after reinstall');
    expect(await app.store.restore(), isTrue, reason: 'Restore purchases finds the active subscription');
    expect(app.store.isEntitled, isTrue);
    expect(app.store.lastError, isNull);

    await _bridge.invokeMethod<void>('expire', {'productId': _product});
    app = await _launch(t, wipeData: true);
    expect(app.store.isEntitled, isFalse);
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
    await _tap(t, const ValueKey('paywall-restore'));
    await _until(t, () => !app.store.busy, 'restore finished');
    await _settle(t);
    expect(app.store.isEntitled, isFalse, reason: 'an expired subscription is not restored');
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
    final message = t.widget<Text>(find.byKey(const ValueKey('paywall-message'))).data;
    expect(message, _en.noSubscriptionForAppleId);
  });

  _scenario('refund revokes premium', (t) async {
    var app = await _launch(t);
    await _subscribe(t, app);
    await _until(t, () => app.store.isEntitled, 'premium after purchase');

    final tx = _latest(await _transactions());
    await _bridge.invokeMethod<void>('refund', {'id': tx['id']});
    // StoreKit delivers the revoked transaction through Transaction.updates;
    // the app re-reads its current entitlements. A foreground refresh too.
    var removedWithoutResume = true;
    try {
      await _until(t, () => !app.store.isEntitled, 'refund via Transaction.updates',
          timeout: const Duration(seconds: 15));
    } on TestFailure {
      removedWithoutResume = false;
      await _resume(t);
      await _until(t, () => !app.store.isEntitled, 'premium removed after refund');
    }
    await _log('refund removed premium ${removedWithoutResume ? 'from Transaction.updates' : 'on the next foreground refresh'}');
    await _until(t, () => find.byKey(const ValueKey('paywall')).evaluate().isNotEmpty, 'paywall after refund');
    expect(EntitlementToken.current, isNull, reason: 'a refunded transaction\'s JWS is never sent');
    expect((await _transactions()).any((x) => x['cancelMs'] != null), isTrue);

    app = await _launch(t);
    expect(app.store.isEntitled, isFalse);
    expect(await app.store.restore(), isFalse, reason: 'a refunded subscription is not restored');
  });

  _scenario('Ask to Buy: pending is not premium until approved', (t) async {
    await _bridge.invokeMethod<void>('setAskToBuy', {'enabled': true});
    final app = await _launch(t);
    await _subscribe(t, app);
    await _until(t, () => !app.store.busy, 'purchase returned');
    await _settle(t);
    expect(app.store.isEntitled, isFalse, reason: 'waiting for the parent');
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('paywall-message'))).data, _en.purchasePending);
    expect(EntitlementToken.current, isNull);
    final pending = (await _transactions()).where((x) => x['pendingAskToBuy'] == true).toList();
    expect(pending, hasLength(1));

    await _resume(t);
    await _settle(t);
    expect(app.store.isEntitled, isFalse, reason: 'still pending after a foreground refresh');

    await _bridge.invokeMethod<void>('approveAskToBuy', {'id': pending.single['id']});
    await _until(t, () => app.store.isEntitled, 'premium after approval (Transaction.updates)');
    await _until(t, () => find.byType(HomeShell).evaluate().isNotEmpty, 'home after approval');
    _expectJws();
  });
}

// ---------------------------------------------------------------------------

void _scenario(String name, Future<void> Function(WidgetTester t) body) {
  testWidgets(name, (t) async {
    _results[name] = 'did not finish';
    await _bridge.invokeMethod<void>('reset');
    try {
      await _guarded(() => body(t));
      _throwIfAppError();
      _results[name] = 'success';
    } catch (e, st) {
      _results[name] = '$e\n${st.toString().split('\n').take(8).join('\n')}';
      rethrow;
    } finally {
      await _teardownApp(t);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}

/// The first error that escaped the app's own async code (a stream listener
/// throwing, for example) during the current scenario.
Object? _appError;
StackTrace? _appErrorStack;

/// Runs a scenario body in its own error zone, so an uncaught error from the
/// app (whose listeners are registered by the body, in [_launch]) is recorded
/// instead of reaching flutter_test's test zone. flutter_test ends the test
/// the moment such an error arrives while the body is still pumping, and every
/// later scenario then fails with `!inTest` / `!_expectingFrame` without
/// running. Here [_until] and [_settle] throw the recorded error, so the body
/// stops, the scenario fails once with the real error, the app is torn down
/// inside the test, and the next scenario starts clean.
Future<void> _guarded(Future<void> Function() body) {
  _appError = null;
  _appErrorStack = null;
  final done = Completer<void>();
  runZonedGuarded(
    () {
      body().then(
        done.complete,
        onError: (Object e, StackTrace st) {
          if (!done.isCompleted) done.completeError(e, st);
        },
      );
    },
    (e, st) {
      if (_appError != null) return;
      _appError = e;
      _appErrorStack = st;
      unawaited(_log('uncaught app error: $e'));
    },
  );
  return done.future;
}

void _throwIfAppError() {
  final e = _appError;
  if (e == null) return;
  throw TestFailure(
    'Uncaught error in the app: $e\n'
    '${_appErrorStack.toString().split('\n').take(8).join('\n')}',
  );
}

Future<void> _waitForBridge() async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (true) {
    try {
      await _bridge.invokeMethod<String>('ping');
      return;
    } on MissingPluginException {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}

Future<void> _log(String message) => _bridge.invokeMethod<void>('log', {'message': message});

class _App {
  _App(this.store, this.state);
  final StoreService store;
  final AppState state;
}

_App? _current;

Future<void> _teardownApp(WidgetTester t) async {
  final old = _current;
  _current = null;
  if (old == null) return;
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump();
  old.store.dispose();
}

/// A cold start of the app as lib/main.dart builds it, with the real store
/// (createStoreService) and an offline coach, for a user who finished
/// onboarding. [wipeData] first deletes the app's local data (reinstall).
Future<_App> _launch(WidgetTester t, {bool wipeData = false}) async {
  await _teardownApp(t);
  final prefs = await SharedPreferences.getInstance();
  if (wipeData) await prefs.clear();
  await prefs.setBool('dw_onboarded', true);
  await prefs.setBool('dw_ai_consent', true);
  await prefs.setInt('dw_ai_consent_version', StorageService.aiConsentVersion);
  await prefs.setString('dw_coach', 'ava');
  await prefs.setString('dw_profile', '{"goals":["profile","conversations","dates"],"language":"en"}');
  EntitlementToken.update(null);

  final storage = await StorageService.create();
  final store = createStoreService();
  final state = AppState(storage: storage, ai: MockAIService(), store: store);
  unawaited(store.init());
  final app = _current = _App(store, state);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<StoreService>.value(value: store),
      ChangeNotifierProvider<AppState>.value(value: state),
      Provider<VoiceService>.value(value: NoVoiceService()),
      Provider<SpeechService>.value(value: NoSpeechService()),
    ],
    child: const DateWiseApp(),
  ));
  await _until(t, () => store.ready, 'store ready at launch');
  await _settle(t);
  return app;
}

/// Taps Subscribe on the paywall, as the user does.
Future<void> _subscribe(WidgetTester t, _App app) async {
  await _until(t, () => app.store.canPurchase && app.store.storePrice != null, 'Subscribe enabled');
  await _settle(t);
  await _tap(t, const ValueKey('paywall-subscribe'));
}

Future<void> _tap(WidgetTester t, Key key) async {
  final f = find.byKey(key);
  await _until(t, () => f.evaluate().isNotEmpty, 'widget $key');
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(f, warnIfMissed: false);
  await t.pump();
}

/// Sends the app to the background and back: the app re-reads the
/// entitlement on resume (AppLifecycleListener → StoreService.refresh).
Future<void> _resume(WidgetTester t) async {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    t.binding.handleAppLifecycleStateChanged(s);
    await t.pump();
  }
  await _settle(t);
}

/// Real time passes (platform channel replies, StoreKit), with frames.
Future<void> _settle(WidgetTester t, [Duration d = const Duration(milliseconds: 1500)]) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    _throwIfAppError();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await t.pump();
  }
}

Future<void> _until(WidgetTester t, FutureOr<bool> Function() cond, String what,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    _throwIfAppError();
    if (await cond()) {
      await t.pump();
      return;
    }
    if (DateTime.now().isAfter(end)) {
      final d = _current?.store.diagnostics;
      throw TestFailure('Timed out after ${timeout.inSeconds}s waiting for: $what'
          '${d == null ? '' : '\nstore: entitled=${d.entitled} ready=${d.ready} error=${d.lastError} price=${d.price}'}'
          '\ntransactions: ${await _transactions()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await t.pump();
  }
}

Future<List<Map<String, Object?>>> _transactions() async {
  final list = await _bridge.invokeListMethod<Object?>('transactions') ?? const [];
  return [for (final m in list) Map<String, Object?>.from(m! as Map)];
}

Map<String, Object?> _latest(List<Map<String, Object?>> txs) {
  expect(txs, isNotEmpty);
  return txs.reduce((a, b) => (b['purchaseMs'] as int) >= (a['purchaseMs'] as int) ? b : a);
}

void _expectJws() {
  final jws = EntitlementToken.current;
  expect(jws, isNotNull, reason: 'the signed transaction (JWS) for the coach backend');
  expect(RegExp(r'^[\w-]+\.[\w-]+\.[\w-]+$').hasMatch(jws!), isTrue);
}
