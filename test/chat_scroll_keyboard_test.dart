import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/screens/shell.dart';

import 'helpers.dart';

ScrollPosition _list(WidgetTester t) =>
    t.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('messages-ava')), matching: find.byType(Scrollable)).first).position;

Future<void> _send(WidgetTester t, TestApp app, String text) async {
  await t.enterText(find.byKey(const ValueKey('composer')), text);
  await t.tap(find.byKey(const ValueKey('send')));
  await t.pump();
  await settleReply(t, app.state);
}

void main() {
  testWidgets('sending brings the newest message back into view after the user scrolled up', (t) async {
    final app = await pumpApp(t, tab: AppTab.chat, prefs: onboardedPrefs());
    await t.pumpAndSettle();
    for (final m in ['How do I start a conversation?', 'What should I wear on a first date?', 'How do I ask for a second date?']) {
      await _send(t, app, m);
    }
    // Scroll up to older messages (the list is reversed: dragging down moves away from the newest).
    await t.drag(find.byKey(const ValueKey('messages-ava')), const Offset(0, 400));
    await t.pumpAndSettle();
    expect(_list(t).pixels, greaterThan(0), reason: 'the conversation is scrolled up');

    await _send(t, app, 'Where should we go for dinner?');
    await t.pumpAndSettle();
    expect(_list(t).pixels, 0, reason: 'the newest message is in view');
  });

  testWidgets('dragging the conversation lowers the keyboard', (t) async {
    final app = await pumpApp(t, tab: AppTab.chat, prefs: onboardedPrefs());
    await t.pumpAndSettle();
    await _send(t, app, 'How do I start a conversation?');
    await t.tap(find.byKey(const ValueKey('composer')));
    await t.pump();
    expect(t.testTextInput.isVisible, isTrue);
    await t.drag(find.byKey(const ValueKey('messages-ava')), const Offset(0, 200));
    await t.pumpAndSettle();
    expect(t.testTextInput.isVisible, isFalse);
  });
}
