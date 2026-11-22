// The midnight theme: dark, on the issue #4 palette, and readable.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datewise_ai/theme/app_theme.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final theme = AppTheme.dark;

  test('the theme is dark, on the midnight-purple canvas', () {
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF120A1F));
    expect(AppColors.background, const Color(0xFF120A1F));
    expect(AppColors.surface, const Color(0xFF1C1030));
    expect(AppColors.primary, const Color(0xFF8B5CF6));
    expect(AppColors.accent, const Color(0xFFE8B4A0));
    expect(
      AppTheme.light.brightness,
      Brightness.dark,
      reason: 'the legacy name returns the same theme',
    );
  });

  test('body text on the background is at least 7:1 (AAA)', () {
    final body = theme.textTheme.bodyLarge!.color!;
    expect(body, AppColors.text);
    expect(
      contrast(body, theme.scaffoldBackgroundColor),
      greaterThanOrEqualTo(7),
    );
    expect(
      contrast(theme.textTheme.bodyMedium!.color!, AppColors.background),
      greaterThanOrEqualTo(7),
    );
  });

  test(
    'muted text, links and button labels meet at least 4.5:1 where they are used',
    () {
      for (final bg in [
        AppColors.background,
        AppColors.surface,
        AppColors.raised,
      ]) {
        expect(
          contrast(AppColors.textMuted, bg),
          greaterThanOrEqualTo(4.5),
          reason: 'muted on $bg',
        );
        expect(
          contrast(AppColors.text, bg),
          greaterThanOrEqualTo(7),
          reason: 'text on $bg',
        );
        expect(
          contrast(AppColors.primarySoft, bg),
          greaterThanOrEqualTo(4.5),
          reason: 'violet text on $bg',
        );
        expect(
          contrast(AppColors.accent, bg),
          greaterThanOrEqualTo(4.5),
          reason: 'rose gold on $bg',
        );
      }
      // White labels on both ends of the brand gradient and on filled buttons.
      for (final c in AppColors.romanticGradient.colors) {
        expect(
          contrast(Colors.white, c),
          greaterThanOrEqualTo(4.5),
          reason: 'white on $c',
        );
      }
      expect(
        contrast(AppColors.onAccent, AppColors.accent),
        greaterThanOrEqualTo(7),
      );
    },
  );
}
