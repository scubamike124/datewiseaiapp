import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/store_service.dart';

import 'helpers.dart';

/// The home screen animates for ever, so pumpAndSettle would never return.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A subscription that expires or is refunded while the app is open loses
/// premium at once and visibly: the paywall replaces the tabs (RootGate).
/// Found by the StoreKit Test E2E run 45463373818: buying closed the paywall
/// through the same callback as "Not now", so after a lapse the tabs stayed.
void main() {
  Future<void> expectPaywall(WidgetTester tester, TestApp app) async {
    expect(app.store.isEntitled, isFalse);
    expect(app.state.canChat, isFalse);
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    expect(find.byKey(const ValueKey('paywall-subscribe')), findsOneWidget);
    expect(find.text(r'$19.99'), findsWidgets, reason: 'the single monthly plan, StoreKit price');
  }

  testWidgets('bought on the paywall, then lapsed in the foreground: the paywall comes back', (tester) async {
    final store = FakeStoreService();
    final app = await pumpApp(tester, prefs: onboardedPrefs(), store: store);
    await settle(tester);
    await expectPaywall(tester, app);

    await tester.tap(find.byKey(const ValueKey('paywall-subscribe')));
    await settle(tester);
    expect(app.store.isEntitled, isTrue);
    expect(find.byKey(const ValueKey('paywall')), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);

    store.expire(); // expiry or refund, delivered while the app is open
    await settle(tester);
    await expectPaywall(tester, app);

    // "Not now" still works: the tabs come back, chat stays locked.
    await tester.tap(find.byKey(const ValueKey('paywall-close')));
    await settle(tester);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(app.state.canChat, isFalse);
  });

  testWidgets('closed the paywall earlier, subscribed later, then lapsed: the paywall comes back', (tester) async {
    final store = FakeStoreService();
    final app = await pumpApp(tester, prefs: onboardedPrefs(), store: store);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('paywall-close')));
    await settle(tester);
    expect(find.byType(HomeShell), findsOneWidget);

    final bought = store.buy(); // for example from the chat's Subscribe button
    await settle(tester);
    expect(await bought, PurchaseResult.purchased);
    expect(find.byType(HomeShell), findsOneWidget);

    store.expire();
    await settle(tester);
    await expectPaywall(tester, app);
  });
}
