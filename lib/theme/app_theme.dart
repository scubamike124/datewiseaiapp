import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// DateWise "Evening" design tokens (from the approved mockups' ds.css).
class AppColors {
  AppColors._();

  static const background = Color(0xFF150C10);
  static const background2 = Color(0xFF18110F);
  static const surface = Color(0xFF1E1518);
  static const surface2 = Color(0xFF2A1E21);
  static const line = Color(0x1FF6E6D6); // rgba(246,230,214,0.12)
  static const line2 = Color(0x33F6E6D6); // rgba(246,230,214,0.20)
  static const text = Color(0xFFF7EFE7);
  static const textMuted = Color(0xFFC2B2A8);
  static const faint = Color(0xFF9C8B82);
  static const gold = Color(0xFFDDB67F);
  static const goldLight = Color(0xFFE6C38F);
  static const gold2 = Color(0xFFC7995C);
  static const goldInk = Color(0xFF1C120D);
  static const rose = Color(0xFFE2899E);
  static const roseDeep = Color(0xFF8E3550);
  static const roseTop = Color(0xFFC4587A);
  static const roseBottom = Color(0xFFA23E5F);
  static const roseInk = Color(0xFFFFF4F6);
  static const ok = Color(0xFF8CC9A3);
  static const danger = Color(0xFFFF8A80);
  static const cardDeep = Color(0xFF22121A);

  // Names used by the shared legal / text widgets.
  static const primary = gold;
  static const accent = gold;
  static const cardBorder = line;

  static const goldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [goldLight, gold, gold2],
    stops: [0, 0.55, 1],
  );

  static const roseGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [roseTop, roseBottom],
  );

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEBC994), Color(0xFFD9849A)],
  );

  static const userBubble = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF3A2A1F), Color(0xFF2F2219)],
  );
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double gutter = 20;
}

class AppRadius {
  AppRadius._();
  static const double sm = 14;
  static const double md = 20;
  static const double lg = 28;
}

class AppFonts {
  AppFonts._();
  static const serif = 'Newsreader';
  static const sans = 'Inter';
}

/// Text styles used across screens.
class AppText {
  AppText._();

  static const display = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 40,
    height: 1.04,
    letterSpacing: -0.8,
    color: AppColors.text,
    fontWeight: FontWeight.w400,
  );

  static const title = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 32,
    height: 1.08,
    letterSpacing: -0.6,
    color: AppColors.text,
    fontWeight: FontWeight.w400,
  );

  static const name = TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 26,
    height: 1.05,
    color: AppColors.text,
    fontWeight: FontWeight.w400,
  );

  static const eyebrow = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.7,
    color: AppColors.gold,
  );

  static const body = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 16,
    height: 1.5,
    color: AppColors.textMuted,
  );

  static const label = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  static const small = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 12.5,
    height: 1.35,
    color: AppColors.faint,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: AppFonts.sans,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        onPrimary: AppColors.goldInk,
        secondary: AppColors.rose,
        onSecondary: AppColors.goldInk,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        error: AppColors.danger,
        outline: AppColors.line2,
      ),
      splashFactory: InkSparkle.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
        fontFamily: AppFonts.sans,
      ),
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: AppColors.gold,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.serif,
          fontSize: 20,
          color: AppColors.text,
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        showDragHandle: true,
        dragHandleColor: AppColors.line2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface2,
        titleTextStyle: TextStyle(fontFamily: AppFonts.serif, fontSize: 22, color: AppColors.text),
        contentTextStyle: TextStyle(fontFamily: AppFonts.sans, fontSize: 15, height: 1.45, color: AppColors.textMuted),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surface2,
        contentTextStyle: TextStyle(color: AppColors.text, fontFamily: AppFonts.sans),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.goldInk : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.gold : AppColors.surface2),
        trackOutlineColor: const WidgetStatePropertyAll(AppColors.line2),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.gold,
        selectionColor: Color(0x55DDB67F),
        selectionHandleColor: AppColors.gold,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: AppColors.faint),
        border: InputBorder.none,
      ),
    );
  }
}
