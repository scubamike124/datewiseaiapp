import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/speech_service.dart';

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

  micTests();
}

/// A recognizer that hears [words]; with [stuckStop] its stop() never returns (the engine failed to report it).
class _Speech extends NoSpeechService {
  _Speech({this.stuckStop = false});
  static const words = 'Where should we go for dinner';
  final bool stuckStop;
  int starts = 0;

  @override
  bool get available => true;
  @override
  Future<bool> ensureReady() async => true;
  @override
  Future<SpeechStart> start({
    required String localeId,
    List<String> fallbackLocales = const [],
    required void Function(String words) onWords,
    void Function()? onUnsupported,
    void Function(String words)? onEnded,
  }) async {
    starts++;
    onWords(words);
    return SpeechStart.started;
  }

  @override
  Future<String> stop() => stuckStop ? Completer<String>().future : Future.value(words);
}

Future<void> _holdToTalk(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('voice-mode')));
  await t.pumpAndSettle();
  final hold = await t.startGesture(t.getCenter(find.byKey(const ValueKey('hold-to-talk'))));
  await t.pump(const Duration(seconds: 2));
  await hold.up();
  await t.pump(const Duration(seconds: 3));
}

void micTests() {
  testWidgets('the talk button starts listening and sends even when the voice never reports that it stopped', (t) async {
    final speech = _Speech();
    final app = await pumpApp(t, tab: AppTab.chat, voice: _StuckStopVoice(), speech: speech, prefs: onboardedPrefs());
    await t.pumpAndSettle();
    await _holdToTalk(t);
    await settleReply(t, app.state);

    expect(speech.starts, 1, reason: 'recognition started');
    final users = app.state.activeThread?.messages.where((m) => m.isUser).map((m) => m.text).toList();
    expect(users, ['Where should we go for dinner']);
  });

  testWidgets('what was heard is sent even when the recognizer never reports its final result', (t) async {
    final app = await pumpApp(t, tab: AppTab.chat, speech: _Speech(stuckStop: true), prefs: onboardedPrefs());
    await t.pumpAndSettle();
    await _holdToTalk(t);
    await settleReply(t, app.state);

    final users = app.state.activeThread?.messages.where((m) => m.isUser).map((m) => m.text).toList();
    expect(users, ['Where should we go for dinner']);
  });
}
