// Full-app QA sweep (v2), voice: recognition that ends by itself (timeout,
// no match) leaves "Listening…" with a gentle note; a denied permission says
// so (never "not available on this device") and offers Open Settings; and
// the denial paths: initialize false or hasPermission false hides voice,
// a recheck on resume restores it, the snackbars, initialize throwing,
// onUnsupported mid-session, releasing the hold while starting, and
// disposing the chat while recognition starts.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:datewise_ai/screens/paywall_screen.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/speech_service.dart';
import 'package:datewise_ai/services/store_service.dart';

import 'helpers.dart';

/// A fake SpeechToText (only what DeviceSpeechService uses). [init] and
/// [permission] are a bool, or an Object to throw.
class _Stt implements SpeechToText {
  _Stt({this.init = true, this.permission = true});
  Object init;
  Object permission;
  void Function(SpeechRecognitionError)? onError;
  void Function(String)? onStatus;
  int stops = 0;
  int cancels = 0;

  Future<T> _answer<T>(Object v) => v is T ? Future<T>.value(v as T) : Future<T>.error(v);

  @override
  dynamic noSuchMethod(Invocation i) {
    switch (i.memberName) {
      case #initialize:
        onError = i.namedArguments[#onError] as void Function(SpeechRecognitionError)?;
        onStatus = i.namedArguments[#onStatus] as void Function(String)?;
        return _answer<bool>(init);
      case #hasPermission:
        return _answer<bool>(permission);
      case #isListening:
        return false;
      case #locales:
        return Future<List<LocaleName>>.value([LocaleName('en_US', 'English')]);
      case #listen:
        return Future<void>.value();
      case #stop:
        stops++;
        return Future<void>.value();
      case #cancel:
        cancels++;
        return Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

/// A fake SpeechService for the chat screen.
class _Speech implements SpeechService {
  _Speech({this.available = true, this.denied = false, this.canOpenSettings = true});

  @override
  bool available;
  bool denied;
  @override
  bool get permissionDenied => denied;
  @override
  final bool canOpenSettings;
  int settingsOpened = 0;
  @override
  Future<void> openSettings() async => settingsOpened++;

  /// ensureReady fails with a permission denial.
  bool denyOnReady = false;

  /// What recheckPermission finds (null: no change).
  bool? recheckAllows;

  Completer<SpeechStart>? pendingStart;
  bool holdStart = false;
  SpeechStart nextResult = SpeechStart.started;
  void Function()? onUnsupported;
  void Function(String)? onEnded;
  int starts = 0, stops = 0, cancels = 0;

  @override
  Future<bool> ensureReady() async {
    if (denyOnReady) {
      available = false;
      denied = true;
      return false;
    }
    return available;
  }

  @override
  Future<void> recheckPermission() async {
    if (recheckAllows == true) {
      available = true;
      denied = false;
    }
  }

  @override
  Future<SpeechStart> start({
    required String localeId,
    List<String> fallbackLocales = const [],
    required void Function(String words) onWords,
    void Function()? onUnsupported,
    void Function(String words)? onEnded,
  }) async {
    starts++;
    this.onUnsupported = onUnsupported;
    this.onEnded = onEnded;
    if (holdStart) {
      pendingStart = Completer<SpeechStart>();
      return pendingStart!.future;
    }
    return nextResult;
  }

  @override
  Future<String> stop() async {
    stops++;
    return '';
  }

  @override
  Future<void> cancel() async => cancels++;
}

const _deniedNote =
    'Microphone or speech recognition access is turned off for DateWise. Allow it in Settings to talk with Ava, or type instead.';
const _permissionNeeded =
    'Voice needs microphone and speech recognition access. You can allow it in Settings.';

Future<void> _openMenu(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('chat-menu')));
  await t.pumpAndSettle();
}

Future<_Speech> _openVoice(WidgetTester t, _Speech s) async {
  await pumpApp(t, prefs: onboardedPrefs(), tab: AppTab.chat, speech: s);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('voice-mode')));
  await t.pumpAndSettle();
  return s;
}

Finder get _talk => find.byKey(const ValueKey('hold-to-talk'));

void main() {
  group('DeviceSpeechService', () {
    Future<SpeechStart> start(DeviceSpeechService s, {void Function(String)? onEnded, void Function()? onUnsupported}) =>
        s.start(localeId: 'en-US', onWords: (_) {}, onEnded: onEnded, onUnsupported: onUnsupported);

    test('initialize false and hasPermission false: voice is hidden as a permission denial', () async {
      final s = DeviceSpeechService.withRecognizer(_Stt(init: false, permission: false));
      expect(await s.ensureReady(), isFalse);
      expect(s.available, isFalse);
      expect(s.permissionDenied, isTrue);
    });

    test('initialize false with permission granted: not a denial (recognizer unavailable)', () async {
      final s = DeviceSpeechService.withRecognizer(_Stt(init: false, permission: true));
      expect(await s.ensureReady(), isFalse);
      expect(s.available, isTrue);
      expect(s.permissionDenied, isFalse);
    });

    test('initialize throwing: denied only when hasPermission is false or throws too', () async {
      final granted = DeviceSpeechService.withRecognizer(_Stt(init: StateError('boom'), permission: true));
      expect(await granted.ensureReady(), isFalse);
      expect(granted.permissionDenied, isFalse);
      final denied = DeviceSpeechService.withRecognizer(_Stt(init: StateError('boom'), permission: false));
      expect(await denied.ensureReady(), isFalse);
      expect(denied.permissionDenied, isTrue);
      final unknown = DeviceSpeechService.withRecognizer(_Stt(init: StateError('boom'), permission: StateError('no')));
      expect(await unknown.ensureReady(), isFalse);
      expect(unknown.available, isFalse);
      expect(await start(unknown), SpeechStart.denied);
    });

    test('recheckPermission (on resume) restores voice once access is allowed', () async {
      final stt = _Stt(init: false, permission: false);
      final s = DeviceSpeechService.withRecognizer(stt);
      await s.ensureReady();
      expect(s.available, isFalse);
      await s.recheckPermission();
      expect(s.available, isFalse, reason: 'still denied');
      stt.permission = true;
      await s.recheckPermission();
      expect(s.available, isTrue);
      expect(s.permissionDenied, isFalse);
    });

    test('no match or a speech timeout ends the session once, with what was heard', () async {
      final stt = _Stt();
      final s = DeviceSpeechService.withRecognizer(stt);
      final ended = <String>[];
      expect(await start(s, onEnded: ended.add), SpeechStart.started);
      stt.onStatus!(SpeechToText.listeningStatus);
      stt.onError!(SpeechRecognitionError('error_no_match', true));
      stt.onStatus!(SpeechToText.notListeningStatus);
      stt.onStatus!(SpeechToText.doneStatus);
      expect(ended, [''], reason: 'called once');

      await start(s, onEnded: ended.add);
      stt.onStatus!(SpeechToText.listeningStatus);
      stt.onError!(SpeechRecognitionError('error_speech_timeout', true));
      expect(ended, ['', '']);
    });

    test('a silence timeout after words ends with the words; a stale end status is ignored', () async {
      final stt = _Stt();
      final s = DeviceSpeechService.withRecognizer(stt);
      final ended = <String>[];
      await start(s, onEnded: ended.add);
      // An end status from an earlier session, before this one listens.
      stt.onStatus!(SpeechToText.doneStatus);
      expect(ended, isEmpty);
      stt.onStatus!(SpeechToText.listeningStatus);
      stt.onStatus!(SpeechToText.doneStatus);
      expect(ended, ['']);
    });

    test('stop() and cancel() never report an end', () async {
      final stt = _Stt();
      final s = DeviceSpeechService.withRecognizer(stt);
      final ended = <String>[];
      await start(s, onEnded: ended.add);
      stt.onStatus!(SpeechToText.listeningStatus);
      await s.stop();
      stt.onStatus!(SpeechToText.doneStatus);
      await start(s, onEnded: ended.add);
      stt.onStatus!(SpeechToText.listeningStatus);
      await s.cancel();
      stt.onError!(SpeechRecognitionError('error_no_match', true));
      expect(ended, isEmpty);
    });

    test('a language error mid-session calls onUnsupported, not onEnded', () async {
      final stt = _Stt();
      final s = DeviceSpeechService.withRecognizer(stt);
      final ended = <String>[];
      var unsupported = 0;
      await start(s, onEnded: ended.add, onUnsupported: () => unsupported++);
      stt.onStatus!(SpeechToText.listeningStatus);
      stt.onError!(SpeechRecognitionError('error_language_unavailable', true));
      stt.onStatus!(SpeechToText.doneStatus);
      expect(unsupported, 1);
      expect(ended, isEmpty);
    });

    test('Android error_permission mid-session is a permission denial, not a normal end', () async {
      final stt = _Stt();
      final s = DeviceSpeechService.withRecognizer(stt);
      final ended = <String>[];
      var unsupported = 0;
      await start(s, onEnded: ended.add, onUnsupported: () => unsupported++);
      stt.onStatus!(SpeechToText.listeningStatus);
      expect(s.permissionDenied, isFalse);
      stt.onError!(SpeechRecognitionError('error_permission', true));
      stt.onStatus!(SpeechToText.doneStatus);
      expect(s.permissionDenied, isTrue);
      expect(s.available, isFalse, reason: 'voice hides until access is allowed again');
      expect(ended, [''], reason: 'the session ends once');
      expect(unsupported, 0);
    });

    test('Open Settings is offered on iOS only', () {
      final s = DeviceSpeechService.withRecognizer(_Stt());
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(s.canOpenSettings, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(s.canOpenSettings, isFalse);
      debugDefaultTargetPlatformOverride = null;
      expect(NoSpeechService().canOpenSettings, isFalse);
      expect(NoSpeechService().permissionDenied, isFalse);
    });
  });

  group('chat', () {
    testWidgets('denied permission: no voice button; the menu says so and opens Settings', (t) async {
      final speech = _Speech(available: false, denied: true);
      await pumpApp(t, prefs: onboardedPrefs(), tab: AppTab.chat, speech: speech);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-mode')), findsNothing);
      await _openMenu(t);
      expect(find.text(_deniedNote), findsOneWidget);
      expect(find.textContaining('not available on this device'), findsNothing);
      await t.tap(find.byKey(const ValueKey('menu-open-settings')));
      await t.pumpAndSettle();
      expect(speech.settingsOpened, 1);
    });

    testWidgets('Spanish: the denial note and "Abrir Configuración"', (t) async {
      await pumpApp(t, prefs: spanishPrefs(), tab: AppTab.chat, speech: _Speech(available: false, denied: true));
      await t.pumpAndSettle();
      await _openMenu(t);
      expect(find.textContaining('El acceso al micrófono o al reconocimiento de voz está desactivado'), findsOneWidget);
      expect(find.text('Abrir Configuración'), findsOneWidget);
    });

    testWidgets('no recognizer on the device (not a denial): the "not available" note, no Settings', (t) async {
      await pumpApp(t, prefs: onboardedPrefs(), tab: AppTab.chat, speech: _Speech(available: false));
      await t.pumpAndSettle();
      await _openMenu(t);
      expect(find.text("Voice isn't available on this device. You can type to Ava."), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-open-settings')), findsNothing);
    });

    testWidgets('where Settings cannot be opened, the denial note shows without the button', (t) async {
      await pumpApp(t,
          prefs: onboardedPrefs(), tab: AppTab.chat, speech: _Speech(available: false, denied: true, canOpenSettings: false));
      await t.pumpAndSettle();
      await _openMenu(t);
      expect(find.text(_deniedNote), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-open-settings')), findsNothing);
    });

    testWidgets('back from Settings with access allowed: the voice button returns', (t) async {
      final speech = _Speech(available: false, denied: true);
      await pumpApp(t, prefs: onboardedPrefs(), tab: AppTab.chat, speech: speech);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-mode')), findsNothing);
      speech.recheckAllows = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-mode')), findsOneWidget);
    });

    testWidgets('denied when entering voice: snackbar with Open Settings, and voice hides', (t) async {
      final speech = _Speech()..denyOnReady = true;
      await pumpApp(t, prefs: onboardedPrefs(), tab: AppTab.chat, speech: speech);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('voice-mode')));
      await t.pump();
      expect(find.text(_permissionNeeded), findsOneWidget);
      await t.pump(const Duration(milliseconds: 500)); // the snackbar slides in
      await t.tap(find.byKey(const ValueKey('voice-open-settings')));
      await t.pump();
      expect(speech.settingsOpened, 1);
      expect(find.byKey(const ValueKey('voice-mode')), findsNothing);
      await t.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('denied at start while holding: snackbar, no stop, not listening', (t) async {
      final speech = await _openVoice(t, _Speech()..nextResult = SpeechStart.denied);
      final g = await t.startGesture(t.getCenter(_talk));
      await t.pump();
      await t.pump();
      expect(find.text(_permissionNeeded), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-open-settings')), findsOneWidget);
      expect(find.text('Listening…'), findsNothing);
      await g.up();
      await t.pump();
      expect(speech.stops, 0);
      await t.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('releasing the hold while starting, then a denied start: no stop, the denial is shown', (t) async {
      final speech = await _openVoice(t, _Speech()..holdStart = true);
      final g = await t.startGesture(t.getCenter(_talk));
      await t.pump();
      await g.up();
      await t.pump();
      speech.pendingStart!.complete(SpeechStart.denied);
      await t.pump();
      await t.pump();
      expect(speech.stops, 0);
      expect(find.text(_permissionNeeded), findsOneWidget);
      expect(find.text('Listening…'), findsNothing);
      await t.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('onUnsupported mid-session: listening ends with the language note', (t) async {
      final speech = await _openVoice(t, _Speech());
      final g = await t.startGesture(t.getCenter(_talk));
      await t.pump();
      expect(find.text('Listening…'), findsOneWidget);
      speech.onUnsupported!();
      await t.pump();
      expect(find.text('Listening…'), findsNothing);
      expect(find.textContaining("Voice isn't available for this language"), findsOneWidget);
      expect(speech.cancels, greaterThanOrEqualTo(1));
      await g.up();
      await t.pump();
      expect(speech.stops, 0);
      await t.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('timeout or no match while holding: "Listening…" ends with a gentle note; release sends nothing', (t) async {
      final speech = await _openVoice(t, _Speech());
      final g = await t.startGesture(t.getCenter(_talk));
      await t.pump();
      expect(find.text('Listening…'), findsOneWidget);
      speech.onEnded!('');
      await t.pump();
      expect(find.text('Listening…'), findsNothing);
      expect(find.text("I didn't catch that. Hold the button and try again."), findsOneWidget);
      await g.up();
      await t.pump();
      expect(speech.stops, 0);
      expect(find.byKey(const ValueKey('stop')), findsNothing);
      await t.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('recognition that ends by itself after words sends them', (t) async {
      final speech = _Speech();
      await pumpApp(t, prefs: onboardedPrefs(), tab: AppTab.chat, speech: speech);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('voice-mode')));
      await t.pumpAndSettle();
      final g = await t.startGesture(t.getCenter(_talk));
      await t.pump();
      speech.onEnded!('Help me reply to her');
      await t.pump();
      await g.up();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Help me reply to her'), findsWidgets);
      await t.pumpAndSettle(const Duration(seconds: 10));
    });

    testWidgets('a transcript that arrives while a reply streams goes into the composer, not lost', (t) async {
      final speech = _Speech();
      final app = await pumpApp(t, prefs: onboardedPrefs(), tab: AppTab.chat, speech: speech);
      await t.pumpAndSettle();
      // A draft the user had typed is kept; the transcript goes after it.
      await t.enterText(find.byKey(const ValueKey('composer')), 'Draft:');
      await t.tap(find.byKey(const ValueKey('voice-mode')));
      await t.pumpAndSettle();
      final g = await t.startGesture(t.getCenter(_talk));
      await t.pump();
      expect(find.text('Listening…'), findsOneWidget);
      // A reply starts streaming meanwhile (for example a quick prompt).
      unawaited(app.state.sendMessage('Give me a strong opener'));
      await t.pump();
      expect(app.state.isResponding, isTrue);
      speech.onEnded!('Ask her out for coffee');
      await t.pump();
      await g.up();
      await t.pump();
      expect(find.byKey(const ValueKey('voice-kept-in-composer')), findsOneWidget);
      expect(find.text('Your coach is still replying. What you said is in the message box.'), findsOneWidget);
      final users = app.state.activeThread!.messages.where((m) => m.isUser).map((m) => m.text).toList();
      expect(users, ['Give me a strong opener'], reason: 'the transcript was not sent');
      await t.pumpAndSettle(const Duration(seconds: 10));
      // Back to typing: the transcript is in the field, ready to send.
      await t.tap(find.byTooltip('Type instead'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byKey(const ValueKey('composer'))).controller!.text, 'Draft: Ask her out for coffee');
    });

    testWidgets('disposing the chat while recognition starts cancels it once the start completes', (t) async {
      final speech = await _openVoice(t, _Speech()..holdStart = true);
      final g = await t.startGesture(t.getCenter(_talk));
      await t.pump();
      expect(speech.starts, 1);
      await t.pumpWidget(const SizedBox());
      // Disposing cancels; the session that starts afterwards is canceled too.
      final cancelsBefore = speech.cancels;
      speech.pendingStart!.complete(SpeechStart.started);
      await t.pump();
      await t.pump();
      expect(speech.cancels, greaterThan(cancelsBefore), reason: 'the started session is released');
      expect(speech.stops, 0);
      await g.up();
      expect(t.takeException(), isNull);
    });

    testWidgets('a permission error mid-session shows the permission note, not "didn\'t catch that"', (t) async {
      final speech = await _openVoice(t, _Speech());
      final g = await t.startGesture(t.getCenter(_talk));
      await t.pump();
      expect(find.text('Listening…'), findsOneWidget);
      speech
        ..available = false
        ..denied = true;
      speech.onEnded!('');
      await t.pump();
      expect(find.text('Listening…'), findsNothing);
      expect(find.text(_permissionNeeded), findsOneWidget);
      expect(find.text("I didn't catch that. Hold the button and try again."), findsNothing);
      await g.up();
      await t.pumpAndSettle(const Duration(seconds: 6));
    });

    testWidgets('the permission snackbar with Open Settings closes by itself', (t) async {
      final speech = _Speech()..denyOnReady = true;
      await pumpApp(t, prefs: onboardedPrefs(), tab: AppTab.chat, speech: speech);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('voice-mode')));
      await t.pumpAndSettle();
      final bar = t.widget<SnackBar>(find.byKey(const ValueKey('voice-permission-snackbar')));
      expect(bar.persist, isFalse);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-permission-snackbar')), findsNothing);
    });

    testWidgets('releasing the talk button having said nothing shows "didn\'t catch that"', (t) async {
      final speech = await _openVoice(t, _Speech());
      final g = await t.startGesture(t.getCenter(_talk));
      await t.pump();
      expect(find.text('Listening…'), findsOneWidget);
      await g.up();
      await t.pump();
      await t.pump();
      expect(speech.stops, 1);
      expect(find.text('Listening…'), findsNothing);
      expect(find.byKey(const ValueKey('voice-no-speech')), findsOneWidget);
      expect(find.text("I didn't catch that. Hold the button and try again."), findsOneWidget);
      await t.pumpAndSettle(const Duration(seconds: 6));
    });

    testWidgets('a transcript after the subscription lapsed waits in the composer behind the paywall', (t) async {
      final speech = _Speech();
      final store = FakeStoreService(entitled: true);
      final app = await pumpApp(t, prefs: onboardedPrefs(), tab: AppTab.chat, speech: speech, store: store);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('voice-mode')));
      await t.pumpAndSettle();
      final g = await t.startGesture(t.getCenter(_talk));
      await t.pump();
      expect(find.text('Listening…'), findsOneWidget);
      // The paywall was closed earlier this session, so the app stays in
      // the tabs (chat locked) when the subscription lapses.
      app.state.dismissPaywall();
      store.expire();
      await t.pump();
      speech.onEnded!('Ask her out for coffee');
      await t.pumpAndSettle();
      await g.up();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(app.state.activeThread?.messages.where((m) => m.isUser), anyOf(isNull, isEmpty), reason: 'nothing sent');
      // Subscribed again: what was said is in the message box.
      final bought = store.buy();
      await t.pump(const Duration(milliseconds: 20));
      await bought;
      await t.pumpAndSettle();
      if (find.byType(PaywallScreen).evaluate().isNotEmpty) {
        Navigator.of(t.element(find.byType(PaywallScreen))).pop();
        await t.pumpAndSettle();
      }
      if (find.byTooltip('Type instead').evaluate().isNotEmpty) {
        await t.tap(find.byTooltip('Type instead'));
        await t.pumpAndSettle();
      }
      expect(t.widget<TextField>(find.byKey(const ValueKey('composer'))).controller!.text, 'Ask her out for coffee');
    });
  });
}
