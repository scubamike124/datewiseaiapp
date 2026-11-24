// Full-app QA sweep (v2): You › Restore purchases reports each outcome like
// the paywall does. A store or network failure is never shown as "No active
// subscription found".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/store_service.dart';

import 'helpers.dart';

/// A fake store whose restore fails with [error] (or finds nothing).
class _RestoreStore extends FakeStoreService {
  _RestoreStore(this.error) : super(entitled: false);
  final StoreError? error;
  StoreError? _last;

  @override
  StoreError? get lastError => _last;

  @override
  Future<bool> restore() async {
    _last = error;
    notifyListeners();
    return false;
  }
}

Future<String> _restoreFromYou(WidgetTester t, StoreService store, Map<String, Object> prefs) async {
  await pumpApp(t, prefs: prefs, store: store, tab: AppTab.you);
  // Not subscribed: the paywall shows first; close it to reach You.
  final close = find.byKey(const ValueKey('paywall-close'));
  if (close.evaluate().isNotEmpty) {
    await t.tap(close);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tab-you')).first);
    await t.pumpAndSettle();
  }
  final row = find.byKey(const ValueKey('row-restore'));
  await t.scrollUntilVisible(row, 200);
  await t.tap(row);
  await t.pump();
  final snack = find.byKey(const ValueKey('restore-result'));
  expect(snack, findsOneWidget);
  return t.widget<Text>(find.descendant(of: snack, matching: find.byType(Text)).first).data!;
}

void main() {
  for (final (lang, prefs) in [('en', onboardedPrefs()), ('es', spanishPrefs())]) {
    final es = lang == 'es';
    final cases = <(StoreError?, String)>[
      (null, es ? 'No se encontró una suscripción activa.' : 'No active subscription found.'),
      (StoreError.restoreFailed, es ? 'No se pudieron restaurar las compras.' : 'Could not restore purchases.'),
      (StoreError.storeUnreachable, es ? 'No se pudo conectar con el App Store.' : 'Could not reach the App Store.'),
      (StoreError.storeUnavailable,
          es ? 'El App Store no está disponible en este momento.' : 'The App Store is not available right now.'),
    ];
    for (final (error, expected) in cases) {
      testWidgets('[$lang] You › Restore purchases, ${error?.name ?? 'nothing to restore'}: "$expected"', (t) async {
        expect(await _restoreFromYou(t, _RestoreStore(error), prefs), expected);
      });
    }

    testWidgets('[$lang] You › Restore purchases that finds the subscription says it is active', (t) async {
      expect(await _restoreFromYou(t, FakeStoreService(entitled: true), prefs),
          es ? 'DateWise Premium está activa.' : 'DateWise Premium is active.');
    });
  }

  testWidgets('the paywall shows the same store errors on a failed restore', (t) async {
    await pumpApp(t, prefs: onboardedPrefs(), store: _RestoreStore(StoreError.storeUnreachable));
    await t.ensureVisible(find.byKey(const ValueKey('paywall-restore')));
    await t.tap(find.byKey(const ValueKey('paywall-restore')));
    await t.pumpAndSettle();
    expect(find.text('Could not reach the App Store.'), findsOneWidget);
  });
}
