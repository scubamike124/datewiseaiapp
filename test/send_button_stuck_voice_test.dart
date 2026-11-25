import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/models/chat_message.dart';
import 'package:datewise_ai/models/coach.dart';
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
  doubleTapTests();
}

/// A recognizer that hears one utterance per session, in order. Like the device recognizer, stop() returns the words
/// of the session it ends and nothing for a session that never started. With [stuckStop] stop() never returns.
class _Speech extends NoSpeechService {
  _Speech({List<String> utterances = const ['Where should we go for dinner'], this.stuckStop = false})
      : _queue = [...utterances];
  final List<String> _queue;
  final bool stuckStop;
  String _current = '';
  int starts = 0;
  int cancels = 0;

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
    _current = _queue.isEmpty ? '' : _queue.removeAt(0);
    onWords(_current);
    return SpeechStart.started;
  }

  @override
  Future<String> stop() {
    if (stuckStop) return Completer<String>().future;
    final w = _current;
    _current = '';
    return Future.value(w);
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _current = '';
  }
}

Future<void> _openVoice(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('voice-mode')));
  await t.pumpAndSettle();
}

Future<void> _hold(WidgetTester t, Duration d) async {
  final hold = await t.startGesture(t.getCenter(find.byKey(const ValueKey('hold-to-talk'))));
  await t.pump(d);
  await hold.up();
  await t.pump(const Duration(seconds: 3));
}

List<String>? _users(TestApp app) => app.state.activeThread?.messages.where((m) => m.isUser).map((m) => m.text).toList();

void micTests() {
  testWidgets('the talk button starts listening and sends even when the voice never reports that it stopped', (t) async {
    final speech = _Speech();
    final app = await pumpApp(t, tab: AppTab.chat, voice: _StuckStopVoice(), speech: speech, prefs: onboardedPrefs());
    await t.pumpAndSettle();
    await _openVoice(t);
    await _hold(t, const Duration(seconds: 2));
    await settleReply(t, app.state);

    expect(speech.starts, 1, reason: 'recognition started');
    expect(_users(app), ['Where should we go for dinner']);
  });

  testWidgets('what was heard is sent even when the recognizer never reports its final result, and the mic is released', (t) async {
    final speech = _Speech(stuckStop: true);
    final app = await pumpApp(t, tab: AppTab.chat, speech: speech, prefs: onboardedPrefs());
    await t.pumpAndSettle();
    await _openVoice(t);
    await _hold(t, const Duration(seconds: 2));
    await settleReply(t, app.state);

    expect(_users(app), ['Where should we go for dinner']);
    expect(speech.cancels, greaterThanOrEqualTo(1), reason: 'the recognizer is canceled, releasing the microphone');
  });

  testWidgets('a short press while the coach is still speaking and its stop hangs sends the new words, once', (t) async {
    final voice = _StuckStopVoice();
    final speech = _Speech(utterances: ['How do I start a conversation', 'What should I wear']);
    final app = await pumpApp(t, tab: AppTab.chat, voice: voice, speech: speech, prefs: onboardedPrefs());
    await t.pumpAndSettle();
    await _openVoice(t);
    await _hold(t, const Duration(seconds: 2));
    await settleReply(t, app.state);
    // The coach is speaking, and its stop will never report back.
    await voice.speak('Start with something you noticed in their profile.', Coaches.all.first);
    await t.pump();
    await _hold(t, const Duration(milliseconds: 500));
    await settleReply(t, app.state);

    expect(_users(app), ['How do I start a conversation', 'What should I wear'],
        reason: 'the second press is not lost and the first words are not sent again');
  });
}

void doubleTapTests() {
  testWidgets('a quick double tap on the gold button sends once and does not stop the reply', (t) async {
    final app = await pumpApp(t, tab: AppTab.chat, prefs: onboardedPrefs());
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('composer')), 'Where should we go for dinner?');
    await t.tap(find.byKey(const ValueKey('send')));
    await t.pump(const Duration(milliseconds: 120));
    // The button is Stop now; the second tap of the double tap lands on it.
    await t.tap(find.byKey(const ValueKey('stop')));
    await t.pump();
    expect(app.state.isResponding, isTrue, reason: 'the reply keeps going');
    await settleReply(t, app.state);
    final last = app.state.activeThread!.messages.last;
    expect(last.isUser, isFalse);
    expect(last.status, isNot(MessageStatus.stopped));
    expect(_users(app), ['Where should we go for dinner?']);
  });

  testWidgets('a deliberate Stop after the guard still stops the reply', (t) async {
    final app = await pumpApp(t, tab: AppTab.chat, prefs: onboardedPrefs());
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('composer')), 'Give me a long answer about first dates');
    await t.tap(find.byKey(const ValueKey('send')));
    await t.pump(const Duration(milliseconds: 700));
    if (!app.state.isResponding) return; // the offline coach finished first; nothing to stop
    await t.tap(find.byKey(const ValueKey('stop')));
    await t.pump();
    expect(app.state.isResponding, isFalse);
    await settleReply(t, app.state);
  });
}
