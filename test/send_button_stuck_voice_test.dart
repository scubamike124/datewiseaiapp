import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/screens/shell.dart';

import 'fake_voice.dart';
import 'helpers.dart';

/// A device voice whose stop() never returns: on an iPhone the speech engine can fail to report
/// that it stopped. The gold send button must still send the message.
class _StuckStopVoice extends ScriptedVoice {
  @override
  Future<void> stop() => Completer<void>().future;
}

void main() {
  testWidgets('the gold send button sends even when the voice never reports that it stopped', (t) async {
    final app = await pumpApp(t, tab: AppTab.chat, voice: _StuckStopVoice(), prefs: onboardedPrefs());
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('composer')), 'Can you book reservations?');
    await t.tap(find.byKey(const ValueKey('send')));
    // Past the stop timeout, then let the reply stream.
    await t.pump(const Duration(seconds: 3));
    await settleReply(t, app.state);

    final users = app.state.activeThread?.messages.where((m) => m.isUser).map((m) => m.text).toList();
    expect(users, ['Can you book reservations?'], reason: 'the message was sent');
    expect(t.takeException(), isNull);
  });

  testWidgets('the keyboard Send key sends the same way', (t) async {
    final app = await pumpApp(t, tab: AppTab.chat, voice: _StuckStopVoice(), prefs: onboardedPrefs());
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('composer')), 'Where should we go for dinner?');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump(const Duration(seconds: 3));
    await settleReply(t, app.state);

    final users = app.state.activeThread?.messages.where((m) => m.isUser).map((m) => m.text).toList();
    expect(users, ['Where should we go for dinner?']);
  });
}
