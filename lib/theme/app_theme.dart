import 'package:flutter/material.dart';

/// Midnight design system for DateWise AI.
///
/// A premium dark theme built on the palette in issue #4: a midnight-purple
/// canvas, layered plum surfaces, a violet primary and a rose-gold accent.
///
///   Background #120A1F · Surface #1C1030 · Raised #27163F · Plum #3B1240
///   Violet #8B5CF6 · Rose gold #E8B4A0 · Text #F5F0FA · Muted #B5A8C8
///
/// Contrast (WCAG): text on background 17.2:1, muted on background 8.6:1,
/// muted on raised 7.4:1, white on the brand gradient >= 5.7:1.
///
/// The colour names predate the dark theme (they were the cream/navy palette)
/// and are kept so every screen and other branches keep compiling; only the
/// values changed.
class AppColors {
  AppColors._();

  // Canvas and surfaces, darkest to lightest.
  static const Color background = Color(0xFF120A1F); // midnight purple
  static const Color surface = Color(0xFF1C1030); // cards, sheets, bars
  static const Color raised = Color(0xFF27163F); // inputs, chips, hover
  static const Color plum = Color(0xFF3B1240); // deep accent surface

  // Brand.
  static const Color primary = Color(0xFF8B5CF6); // violet (fills, icons)
  static const Color primaryDeep = Color(0xFF7C3AED); // fills behind white text
  static const Color primaryDark = Color(0xFF4C1D95);

  /// Violet for text and small marks on dark surfaces (>= 6.6:1 on surface).
  static const Color primarySoft = Color(0xFFC4B5FD);
  static const Color primaryLight = Color(0xFFA78BFA);
  static const Color accent = Color(0xFFE8B4A0); // rose gold

  /// Dark ink used on rose-gold fills (9.3:1).
  static const Color onAccent = Color(0xFF2A1230);

  // Text.
  static const Color text = Color(0xFFF5F0FA);
  static const Color textMuted = Color(0xFFB5A8C8);

  // Lines and glass.
  static const Color cardBorder = Color(0xFF34234F);
  static const Color glassFill = Color(0x14FFFFFF); // 8% white
  static const Color glassBorder = Color(0x24FFFFFF); // 14% white

  // Status (tuned for dark surfaces).
  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);

  /// Pricing card surfaces.
  static const Color flameTint = raised; // popular card
  static const Color magnetDark = plum; // premium card
  static const Color magnetDarkBorder = Color(0xFF6B2A6E);

  /// Primary brand gradient (violet → orchid plum) for buttons, badges,
  /// avatars and the user's chat bubbles. White text on it is >= 5.7:1.
  static const LinearGradient romanticGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDeep, Color(0xFFA0369F)],
  );

  /// Rose-gold gradient for small highlights (use [onAccent] text on it).
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE8B4A0), Color(0xFFF6D6C8)],
  );

  /// Soft top-down wash behind heroes and full-screen flows.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF231338), background],
  );

  /// Glass card fill: a faint light-to-dark sheen over the surface.
  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF241540), Color(0xFF1A0F2C)],
  );
}

/// Spacing scale (8pt grid).
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 40;
  static const double xxl = 64;
}

class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double pill = 999;
}

/// Motion tokens: short, eased, never bouncy.
class AppMotion {
  AppMotion._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 520);
  static const Curve curve = Curves.easeOutCubic;
}

class AppTheme {
  AppTheme._();

  /// Kept for existing callers (tests, other branches): the app now has one
  /// theme, and it is dark.
  static ThemeData get light => dark;

  static ThemeData get dark {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primaryLight,
      onPrimary: AppColors.background,
      primaryContainer: AppColors.primaryDeep,
      onPrimaryContainer: Colors.white,
      secondary: AppColors.accent,
      onSecondary: AppColors.onAccent,
      tertiary: AppColors.plum,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.textMuted,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.raised,
      surfaceContainerHighest: AppColors.raised,
      outline: AppColors.cardBorder,
      outlineVariant: AppColors.cardBorder,
      error: AppColors.danger,
      onError: AppColors.background,
    );

    final textTheme = _buildTextTheme(base.textTheme);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
    );
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDeep,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.raised,
          disabledForegroundColor: AppColors.textMuted,
          elevation: 0,
          shadowColor: AppColors.primary.withValues(alpha: 0.5),
          padding: buttonPadding,
          textStyle: textTheme.labelLarge,
          shape: buttonShape,
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.hovered) ? 6 : 0),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryDeep,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.raised,
          disabledForegroundColor: AppColors.textMuted,
          padding: buttonPadding,
          textStyle: textTheme.labelLarge,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          disabledForegroundColor: AppColors.textMuted,
          side: const BorderSide(color: AppColors.glassBorder),
          backgroundColor: AppColors.glassFill,
          padding: buttonPadding,
          textStyle: textTheme.labelLarge,
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primarySoft,
          textStyle: textTheme.labelLarge,
          shape: buttonShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.text),
      ),
      iconTheme: const IconThemeData(color: AppColors.text),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.raised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: inputBorder(AppColors.cardBorder),
        enabledBorder: inputBorder(AppColors.cardBorder),
        disabledBorder: inputBorder(AppColors.cardBorder),
        focusedBorder: inputBorder(AppColors.primaryLight, 1.5),
        errorBorder: inputBorder(AppColors.danger),
        focusedErrorBorder: inputBorder(AppColors.danger, 1.5),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        floatingLabelStyle: const TextStyle(color: AppColors.primarySoft),
        prefixIconColor: AppColors.textMuted,
        errorStyle: const TextStyle(color: AppColors.danger),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primaryLight,
        selectionColor: AppColors.primary.withValues(alpha: 0.4),
        selectionHandleColor: AppColors.primaryLight,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.cardBorder,
        thickness: 1,
        space: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.raised,
        side: const BorderSide(color: AppColors.cardBorder),
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? AppColors.primaryDeep
                  : AppColors.surface),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? Colors.white
                  : AppColors.textMuted),
          iconColor: const WidgetStatePropertyAll(Colors.white),
          side: const WidgetStatePropertyAll(
              BorderSide(color: AppColors.cardBorder)),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.22),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((s) =>
            (textTheme.labelMedium ?? const TextStyle()).copyWith(
              color: s.contains(WidgetState.selected)
                  ? AppColors.text
                  : AppColors.textMuted,
              fontWeight: s.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected)
                  ? AppColors.primarySoft
                  : AppColors.textMuted,
            )),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.cardBorder,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.raised,
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.raised,
        contentTextStyle: textTheme.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.primarySoft,
        textColor: AppColors.text,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.raised,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.cardBorder),
        ),
        textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryLight,
        linearTrackColor: AppColors.raised,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
            AppColors.textMuted.withValues(alpha: 0.35)),
      ),
    );
  }

  /// A refined type scale on the platform font: tight, heavy display sizes for
  /// headlines; relaxed line height for reading.
  static TextTheme _buildTextTheme(TextTheme base) {
    TextStyle? head(TextStyle? s, double spacing, double height,
            [FontWeight w = FontWeight.w700]) =>
        s?.copyWith(
          fontWeight: w,
          letterSpacing: spacing,
          height: height,
          color: AppColors.text,
        );

    return base
        .copyWith(
          displayLarge: head(base.displayLarge, -1.5, 1.04, FontWeight.w800),
          displayMedium: head(base.displayMedium, -1.2, 1.06, FontWeight.w800),
          displaySmall: head(base.displaySmall, -0.8, 1.1, FontWeight.w800),
          headlineLarge: head(base.headlineLarge, -0.6, 1.15),
          headlineMedium: head(base.headlineMedium, -0.5, 1.18),
          headlineSmall: head(base.headlineSmall, -0.3, 1.22),
          titleLarge: head(base.titleLarge, -0.2, 1.25),
          titleMedium: head(base.titleMedium, 0, 1.3, FontWeight.w600),
          titleSmall: head(base.titleSmall, 0.1, 1.3, FontWeight.w600),
          bodyLarge: base.bodyLarge?.copyWith(
            color: AppColors.text,
            height: 1.5,
          ),
          bodyMedium: base.bodyMedium?.copyWith(
            color: AppColors.text,
            height: 1.5,
          ),
          bodySmall: base.bodySmall?.copyWith(
            color: AppColors.textMuted,
            height: 1.45,
          ),
          labelLarge: base.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          labelMedium: base.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        )
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text);
  }
}
