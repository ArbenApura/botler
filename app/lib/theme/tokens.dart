// COLOUR TOKENS: THE ONLY FILE IN lib/ WITH LITERAL COLOURS. A WIDGET READS context.colors; A TEST FAILS ON A LITERAL COLOUR ANYWHERE ELSE.
// Style: calm paper. Warm off-white in light, deep warm charcoal in dark, one soft sage accent. Danger, warning, success and info are fixed and never
// come from the accent; the accent never carries a status. Every text/background pair below passes AA (4.5:1), checked by test/theme_contrast_test.dart.
// The same values live in android/app/src/main/res/values(-night)/colors.xml for the home screen widget.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- TYPES -- //

@immutable
class BotlerColors extends ThemeExtension<BotlerColors> {
  const BotlerColors({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentText,
    required this.chip,
    required this.danger,
    required this.warning,
    required this.success,
    required this.info,
  });

  /// The page behind everything.
  final Color paper;

  /// Cards and sheets.
  final Color surface;
  final Color ink;

  /// Secondary text.
  final Color muted;
  final Color line;
  final Color accent;

  /// Text on the accent colour (a primary button).
  final Color onAccent;
  final Color accentSoft;

  /// Text on accentSoft.
  final Color accentText;

  /// The person's own messages.
  final Color chip;
  final Color danger;
  final Color warning;
  final Color success;
  final Color info;

  @override
  BotlerColors copyWith({
    Color? paper,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? accentText,
    Color? chip,
    Color? danger,
    Color? warning,
    Color? success,
    Color? info,
  }) => BotlerColors(
    paper: paper ?? this.paper,
    surface: surface ?? this.surface,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    accentSoft: accentSoft ?? this.accentSoft,
    accentText: accentText ?? this.accentText,
    chip: chip ?? this.chip,
    danger: danger ?? this.danger,
    warning: warning ?? this.warning,
    success: success ?? this.success,
    info: info ?? this.info,
  );

  @override
  BotlerColors lerp(ThemeExtension<BotlerColors>? other, double t) {
    if (other is! BotlerColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return BotlerColors(
      paper: mix(paper, other.paper),
      surface: mix(surface, other.surface),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      line: mix(line, other.line),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentSoft: mix(accentSoft, other.accentSoft),
      accentText: mix(accentText, other.accentText),
      chip: mix(chip, other.chip),
      danger: mix(danger, other.danger),
      warning: mix(warning, other.warning),
      success: mix(success, other.success),
      info: mix(info, other.info),
    );
  }
}

// -- CONSTANTS -- //

const BotlerColors lightColors = BotlerColors(
  paper: Color(0xFFFAF7F0),
  surface: Color(0xFFFFFDF8),
  ink: Color(0xFF2B2722),
  muted: Color(0xFF6A6358),
  line: Color(0xFFE4DED2),
  accent: Color(0xFF4F6F55),
  onAccent: Color(0xFFFFFFFF),
  accentSoft: Color(0xFFE3ECE0),
  accentText: Color(0xFF34503A),
  chip: Color(0xFFEEE8DA),
  danger: Color(0xFFA83A2A),
  warning: Color(0xFF8A5E0B),
  success: Color(0xFF2F6B3E),
  info: Color(0xFF2F6285),
);

const BotlerColors darkColors = BotlerColors(
  paper: Color(0xFF1F1C18),
  surface: Color(0xFF28241F),
  ink: Color(0xFFEDE7DA),
  muted: Color(0xFFABA495),
  line: Color(0xFF3A362F),
  accent: Color(0xFF8FB394),
  onAccent: Color(0xFF1B2A1E),
  accentSoft: Color(0xFF2D3A2F),
  accentText: Color(0xFFB9D4BD),
  chip: Color(0xFF353029),
  danger: Color(0xFFEE8F7E),
  warning: Color(0xFFE0B04F),
  success: Color(0xFF8CCB99),
  info: Color(0xFF8DBBDA),
);

// -- FUNCTIONS -- //

extension BotlerColorsOf on BuildContext {
  /// The tokens of the current mode.
  BotlerColors get colors =>
      Theme.of(this).extension<BotlerColors>() ?? lightColors;
}
