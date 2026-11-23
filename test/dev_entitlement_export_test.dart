import 'dart:convert';
import 'dart:io';

import 'package:datewise_ai/dev/entitlement_export.dart';
import 'package:datewise_ai/screens/settings_screen.dart';
import 'package:datewise_ai/services/coach_usage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// The debug-only "copy entitlement token" action for the live AI test kit
/// (docs/qa/LIVE_AI_TEST_PLAN.md, section 2).
void main() {
  final payload = base64Url.encode(utf8.encode(jsonEncode({
    'environment': 'Sandbox',
    'productId': 'p',
    'expiresDate': 1767225600000,
    'originalTransactionId': '2000000999999999',
  }))).replaceAll('=', '');
  final jws = 'eyJhbGciOiJFUzI1NiJ9.$payload.c2lnbmF0dXJl';

  String? clipboard;
  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
  });
  tearDown(() {
    DevEntitlementExport.debugForceEnabled = null;
    EntitlementToken.update(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpRow(WidgetTester tester) => tester.pumpWidget(const MaterialApp(home: Scaffold(body: DevEntitlementRow())));

  test('off unless DW_DEV_TOOLS is defined (tests run without it)', () {
    expect(DevEntitlementExport.enabled, isFalse);
    DevEntitlementExport.debugForceEnabled = true;
    expect(DevEntitlementExport.enabled, isTrue); // debug build (flutter test), not web
  });

  test('the settings call site checks the compile-time kDebugMode first', () {
    final src = File('lib/screens/settings_screen.dart').readAsStringSync();
    expect(src, contains('if (kDebugMode && DevEntitlementExport.enabled)'));
    final dev = File('lib/dev/entitlement_export.dart').readAsStringSync();
    expect(dev, contains('kDebugMode && !kIsWeb'));
    // Nothing in the action logs or prints the token.
    expect(RegExp(r'\b(print|debugPrint|log)\(').hasMatch(dev), isFalse);
  });

  testWidgets('the You tab has no developer row by default', (tester) async {
    await pumpScreen(tester, const Scaffold(body: SettingsScreen()), size: const Size(390, 2600));
    expect(find.byKey(const ValueKey('row-dev-copy-entitlement')), findsNothing);
    expect(find.text('Developer: copy entitlement token'), findsNothing);
  });

  testWidgets('the You tab shows it in a debug build with the flag', (tester) async {
    DevEntitlementExport.debugForceEnabled = true;
    await pumpScreen(tester, const Scaffold(body: SettingsScreen()), size: const Size(390, 2600));
    expect(find.byKey(const ValueKey('row-dev-copy-entitlement')), findsOneWidget);
  });

  testWidgets('no token: says so and copies nothing', (tester) async {
    await pumpRow(tester);
    await tester.tap(find.byType(DevEntitlementRow));
    await tester.pump();
    expect(find.textContaining('No entitlement token'), findsOneWidget);
    expect(clipboard, isNull);
  });

  testWidgets('asks first, shows only non-identifying fields, then copies the token', (tester) async {
    EntitlementToken.update(jws);
    await pumpRow(tester);
    await tester.tap(find.byType(DevEntitlementRow));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sandbox · p · expires 2026-01-01T00:00:00.000Z'), findsOneWidget);
    expect(find.textContaining('2000000999999999'), findsNothing);
    expect(find.textContaining(jws), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(clipboard, isNull);

    await tester.tap(find.byType(DevEntitlementRow));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard, jws);
    expect(find.text('Entitlement token copied.'), findsOneWidget);
  });
}
