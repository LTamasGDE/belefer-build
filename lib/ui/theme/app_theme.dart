import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'belefer_colors.dart';
import 'palette.dart';

/// Térközök (4-es lépték).
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Képernyőszéli margó.
  static const double page = 20;
}

/// Lekerekítések.
abstract final class Radii {
  static const double field = 16;
  static const double card = 24;
  static const double hero = 28;
  static const double dialog = 28;
}

/// Tartalomszélesség széles kijelzőn (tablet, fekvő mód).
const double maxContentWidth = 720;

/// Összegekhez: táblázatos számjegyek, hogy a sorok egymás alá igazodjanak.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

abstract final class AppTheme {
  static final ThemeData light = _build(Brightness.light, BeleferColors.light);
  static final ThemeData dark = _build(Brightness.dark, BeleferColors.dark);

  static TextTheme _textTheme(BeleferColors c) {
    TextStyle poppins(double size, {double height = 1.2}) => TextStyle(
      fontFamily: 'Poppins',
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: height,
      letterSpacing: -0.2,
    );
    TextStyle inter(
      double size,
      FontWeight weight, {
      double height = 1.4,
      double letterSpacing = 0,
    }) => TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
    );
    return TextTheme(
      displayLarge: poppins(48, height: 1.1),
      displayMedium: poppins(40, height: 1.1),
      displaySmall: poppins(34, height: 1.15),
      headlineLarge: poppins(30),
      headlineMedium: poppins(26),
      headlineSmall: poppins(22),
      titleLarge: poppins(20),
      titleMedium: inter(16, FontWeight.w600, height: 1.3),
      titleSmall: inter(14, FontWeight.w600, height: 1.3),
      bodyLarge: inter(16, FontWeight.w400, height: 1.45),
      bodyMedium: inter(14.5, FontWeight.w400, height: 1.45),
      bodySmall: inter(12.5, FontWeight.w400),
      labelLarge: inter(15, FontWeight.w600, height: 1.2),
      labelMedium: inter(13, FontWeight.w600, height: 1.2),
      labelSmall: inter(11.5, FontWeight.w600, letterSpacing: 0.3),
    ).apply(bodyColor: c.text, displayColor: c.text);
  }

  static ThemeData _build(Brightness brightness, BeleferColors c) {
    final isDark = brightness == Brightness.dark;
    final text = _textTheme(c);
    final fieldBorder = isDark ? const Color(0xFF5B68A3) : Palette.inkMuted;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? Palette.tealBright : Palette.ink,
      onPrimary: isDark ? Palette.ink : Palette.cream,
      primaryContainer: c.sunken,
      onPrimaryContainer: c.text,
      secondary: c.accent,
      onSecondary: c.onAccent,
      secondaryContainer: c.accent.withValues(alpha: 0.24),
      onSecondaryContainer: c.text,
      tertiary: c.expense,
      onTertiary: isDark ? Palette.ink : Colors.white,
      error: c.danger,
      onError: isDark ? Palette.ink : Colors.white,
      surface: c.background,
      onSurface: c.text,
      onSurfaceVariant: c.textMuted,
      surfaceContainerLowest: c.raised,
      surfaceContainerLow: c.raised,
      surfaceContainer: c.raised,
      surfaceContainerHigh: c.raised,
      surfaceContainerHighest: c.sunken,
      surfaceTint: Colors.transparent,
      outline: fieldBorder,
      outlineVariant: c.line,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark ? Palette.cream : Palette.ink,
      onInverseSurface: isDark ? Palette.ink : Palette.cream,
      inversePrimary: Palette.teal,
    );

    OutlineInputBorder fieldOutline(Color color, [double width = 1.2]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.line,
      focusColor: c.accent.withValues(alpha: 0.28),
      visualDensity: VisualDensity.standard,
      extensions: [c],
      appBarTheme: AppBarThemeData(
        backgroundColor: c.background,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: c.raised,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accent.withValues(alpha: isDark ? 0.26 : 0.34),
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Inter',
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? c.text : c.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? c.text : c.textMuted,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.sunken,
          disabledForegroundColor: c.textMuted,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: BorderSide(color: fieldBorder, width: 1.2),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentText,
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 2,
        focusElevation: 3,
        hoverElevation: 3,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        extendedTextStyle: text.labelLarge,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: c.raised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.lg,
        ),
        border: fieldOutline(fieldBorder),
        enabledBorder: fieldOutline(fieldBorder),
        disabledBorder: fieldOutline(c.line),
        focusedBorder: fieldOutline(c.accentText, 2),
        errorBorder: fieldOutline(c.danger),
        focusedErrorBorder: fieldOutline(c.danger, 2),
        labelStyle: TextStyle(color: c.textMuted),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          if (states.contains(WidgetState.error)) {
            return TextStyle(color: c.danger, fontWeight: FontWeight.w600);
          }
          return TextStyle(
            color: states.contains(WidgetState.focused)
                ? c.accentText
                : c.textMuted,
            fontWeight: FontWeight.w600,
          );
        }),
        hintStyle: TextStyle(color: c.textMuted),
        errorStyle: TextStyle(color: c.danger, fontWeight: FontWeight.w500),
        suffixStyle: TextStyle(color: c.textMuted, fontWeight: FontWeight.w600),
        prefixIconColor: c.textMuted,
        errorMaxLines: 2,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.dialog),
        ),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.textMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? Palette.cream : Palette.ink,
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          color: isDark ? Palette.ink : Palette.cream,
        ),
        actionTextColor: isDark ? Palette.tealDeep : Palette.teal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.onAccent : c.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.accent : c.sunken,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : fieldBorder,
        ),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.raised,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: c.heroBackground,
        headerForegroundColor: c.heroForeground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.dialog),
        ),
        todayBorder: BorderSide(color: c.accentText, width: 1.5),
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.onAccent : c.text,
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.onAccent;
          if (states.contains(WidgetState.disabled)) {
            return c.textMuted.withValues(alpha: 0.5);
          }
          return c.text;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.accent : null,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accentText,
        selectionColor: c.accent.withValues(alpha: 0.35),
        selectionHandleColor: c.accentText,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? Palette.cream : Palette.ink,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color: isDark ? Palette.ink : Palette.cream,
        ),
      ),
    );
  }
}
