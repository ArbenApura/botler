// THE APP THEME BUILT FROM THE TOKENS: ONE TYPEFACE FAMILY (THE PHONE'S OWN), LIGHT LARGE NUMERALS FOR MONEY, TABULAR FIGURES SO AMOUNTS LINE UP

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import 'tokens.dart';

// -- CONSTANTS -- //

/// Tap targets are at least this big, in logical pixels (48 dp).
const double minTap = 48;

const List<FontFeature> tabular = <FontFeature>[FontFeature.tabularFigures()];

// -- FUNCTIONS -- //

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? darkColors : lightColors;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: c.onAccent,
        surface: c.surface,
        onSurface: c.ink,
        error: c.danger,
        outline: c.line,
      );
  final base = ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.paper,
    useMaterial3: true,
  );
  final text = base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink);
  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[c],
    textTheme: text.copyWith(
      // Balances and amounts: large, light, tabular
      displaySmall: text.displaySmall?.copyWith(
        fontWeight: FontWeight.w300,
        fontFeatures: tabular,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w300,
        fontFeatures: tabular,
      ),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w500),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.4),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(minTap, minTap),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accentText,
        minimumSize: const Size(minTap, minTap),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.line),
        minimumSize: const Size(minTap, minTap),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.paper),
    ),
    // Screens arrive through botlerPage (ui/transitions.dart), so the theme sets no page transition of its own
  );
}
