import 'package:flutter/material.dart';

import 'palette.dart';

/// Az alkalmazás saját színszerepei, világos és sötét változatban.
@immutable
class BeleferColors extends ThemeExtension<BeleferColors> {
  const BeleferColors({
    required this.background,
    required this.raised,
    required this.sunken,
    required this.line,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.income,
    required this.expense,
    required this.heroBackground,
    required this.heroForeground,
    required this.heroMuted,
    required this.danger,
  });

  static const BeleferColors light = BeleferColors(
    background: Palette.paper,
    raised: Palette.paperRaised,
    sunken: Palette.paperSunken,
    line: Palette.paperLine,
    text: Palette.ink,
    textMuted: Palette.inkSoft,
    accent: Palette.teal,
    onAccent: Palette.ink,
    accentText: Palette.tealDeep,
    income: Palette.mint,
    expense: Palette.coral,
    heroBackground: Palette.ink,
    heroForeground: Palette.cream,
    heroMuted: Palette.creamSoft,
    danger: Palette.danger,
  );

  static const BeleferColors dark = BeleferColors(
    background: Palette.night,
    raised: Palette.nightRaised,
    sunken: Palette.nightSunken,
    line: Palette.nightLine,
    text: Palette.cream,
    textMuted: Palette.creamSoft,
    accent: Palette.tealBright,
    onAccent: Palette.ink,
    accentText: Palette.tealBright,
    income: Palette.mintBright,
    expense: Palette.coralBright,
    heroBackground: Palette.ink2,
    heroForeground: Palette.cream,
    heroMuted: Palette.creamSoft,
    danger: Palette.dangerBright,
  );

  final Color background;
  final Color raised;
  final Color sunken;
  final Color line;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color onAccent;

  /// Akcentus szöveghez és ikonhoz, megfelelő kontraszttal.
  final Color accentText;
  final Color income;
  final Color expense;
  final Color heroBackground;
  final Color heroForeground;
  final Color heroMuted;
  final Color danger;

  @override
  BeleferColors copyWith({
    Color? background,
    Color? raised,
    Color? sunken,
    Color? line,
    Color? text,
    Color? textMuted,
    Color? accent,
    Color? onAccent,
    Color? accentText,
    Color? income,
    Color? expense,
    Color? heroBackground,
    Color? heroForeground,
    Color? heroMuted,
    Color? danger,
  }) {
    return BeleferColors(
      background: background ?? this.background,
      raised: raised ?? this.raised,
      sunken: sunken ?? this.sunken,
      line: line ?? this.line,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentText: accentText ?? this.accentText,
      income: income ?? this.income,
      expense: expense ?? this.expense,
      heroBackground: heroBackground ?? this.heroBackground,
      heroForeground: heroForeground ?? this.heroForeground,
      heroMuted: heroMuted ?? this.heroMuted,
      danger: danger ?? this.danger,
    );
  }

  @override
  BeleferColors lerp(BeleferColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return BeleferColors(
      background: mix(background, other.background),
      raised: mix(raised, other.raised),
      sunken: mix(sunken, other.sunken),
      line: mix(line, other.line),
      text: mix(text, other.text),
      textMuted: mix(textMuted, other.textMuted),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentText: mix(accentText, other.accentText),
      income: mix(income, other.income),
      expense: mix(expense, other.expense),
      heroBackground: mix(heroBackground, other.heroBackground),
      heroForeground: mix(heroForeground, other.heroForeground),
      heroMuted: mix(heroMuted, other.heroMuted),
      danger: mix(danger, other.danger),
    );
  }
}

extension BeleferThemeContext on BuildContext {
  BeleferColors get colors =>
      Theme.of(this).extension<BeleferColors>() ?? BeleferColors.light;
}
