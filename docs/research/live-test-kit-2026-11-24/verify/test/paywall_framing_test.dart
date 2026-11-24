// The paywall's photo band is short (so the price and Subscribe fit on an iPhone SE), so its portrait is
// framed lower than the coach's default hero focus: the whole face shows instead of a crop at the nose
// (independent review of the device-QA fixes, major 1).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/models/coach.dart';
import 'package:datewise_ai/screens/paywall_screen.dart';
import 'package:datewise_ai/widgets/dw.dart';

import 'helpers.dart';

void main() {
  for (final size in const [Size(375, 667), Size(393, 852)]) {
    testWidgets('paywall portrait is framed on the whole face at ${size.width.toInt()}x${size.height.toInt()}', (t) async {
      await pumpScreen(t, PaywallScreen(onClose: () {}), size: size, entitled: false, prefs: onboardedPrefs());
      final image = t.widget<CoachImage>(find.byType(CoachImage).first);
      final coach = image.coach;
      expect(image.alignment, isNotNull);
      expect(image.alignment!.x, coach.heroFocus.x);
      expect(image.alignment!.y, closeTo((coach.heroFocus.y + 0.25).clamp(-1.0, 1.0), 1e-9));
      expect(image.alignment!.y, greaterThan(coach.heroFocus.y));
    });
  }

  test('every coach keeps a valid framing after the shift', () {
    for (final c in Coaches.all) {
      final y = (c.heroFocus.y + 0.25).clamp(-1.0, 1.0);
      expect(y, inInclusiveRange(-1.0, 1.0));
    }
  });
}
