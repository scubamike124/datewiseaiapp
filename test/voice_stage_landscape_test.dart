// Landscape phones in voice mode, with the default test font (the numbers
// below were measured with it): the overflow is no worse than before the
// framing change.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/app.dart';
import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/screens/shell.dart';
import 'package:datewise_ai/services/speech_service.dart';

import 'helpers.dart';

class _Speech implements SpeechService {
  @override
  bool get available => true;
  @override
  bool get permissionDenied => false;
  @override
  bool get canOpenSettings => false;
  @override
  Future<void> openSettings() async {}
  @override
  Future<bool> ensureReady() async => true;
  @override
  Future<void> recheckPermission() async {}
  @override
  Future<SpeechStart> start({
    required String localeId,
    List<String> fallbackLocales = const [],
    required void Function(String words) onWords,
    void Function()? onUnsupported,
    void Function(String words)? onEnded,
  }) async =>
      SpeechStart.started;
  @override
  Future<String> stop() async => '';
  @override
  Future<void> cancel() async {}
}

Future<void> _openVoice(WidgetTester t, Coach coach, Size size, double top, double bottom, double scale, {double keyboard = 0}) async {
  setSurface(t, size, scale);
  t.view.padding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
  t.view.viewPadding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
  addTearDown(t.view.resetPadding);
  addTearDown(t.view.resetViewPadding);
  final app = await makeState(prefs: onboardedPrefs(coach: coach.id));
  await t.pumpWidget(wrap(app, const DateWiseApp(initialTab: AppTab.chat), speech: _Speech()));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('voice-mode')));
  await t.pumpAndSettle();
  if (keyboard > 0) {
    t.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
  }
}

Rect _r(WidgetTester t, String key) => t.getRect(find.byKey(ValueKey(key)));



void main() {
  // Landscape phones: no worse than the app before the framing change, which
  // (test font) overflowed 205 / 190 px at 1.0 and 9.5 / 0 px at 2.0 text.
  for (final (name, size, scale, base) in const [
    ('667x375', Size(667, 375), 1.0, 205.0),
    ('844x390', Size(844, 390), 1.0, 190.0),
    ('667x375', Size(667, 375), 2.0, 9.5),
    ('844x390', Size(844, 390), 2.0, 0.0),
  ]) {
    testWidgets('landscape phone $name x$scale: overflow no worse than before ($base px)', (t) async {
      final overflows = <double>[];
      final old = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = RegExp(r'overflowed by ([0-9.]+) pixels').firstMatch(d.toString());
        if (m != null) {
          overflows.add(double.parse(m.group(1)!));
        } else {
          old?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = old);
      await _openVoice(t, Coaches.ava, size, 0, 0, scale);
      final worst = overflows.isEmpty ? 0.0 : overflows.reduce((a, b) => a > b ? a : b);
      expect(worst, lessThanOrEqualTo(base + 0.5), reason: 'overflow $worst px');
      expect(_r(t, 'chat-menu').top, greaterThanOrEqualTo(0));
    });
  }

}
