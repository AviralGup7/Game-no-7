/// Colour and type system. Contrast targets: >=7:1 (AAA) in high contrast,
/// >=4.5:1 (AA) otherwise. The clue numerals and the filled squares ARE the
/// content here, so they get the strongest contrast in the palette.
library;

import 'package:flutter/material.dart';

class AppTheme {
  static const seed = Color(0xFF0F6B5C);   // deep teal
  static const accent = Color(0xFFB4530A);

  static ThemeData light({bool highContrast = false}) {
    final s = highContrast
        ? const ColorScheme.light(
            primary: Color(0xFF00382E), onPrimary: Colors.white,
            secondary: Color(0xFF7A3400), surface: Colors.white,
            onSurface: Color(0xFF000000), outline: Color(0xFF000000),
            error: Color(0xFFB00020))
        : ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return _base(s, highContrast);
  }

  static ThemeData dark({bool highContrast = false}) {
    final s = highContrast
        ? const ColorScheme.dark(
            primary: Color(0xFF7FE7D2), onPrimary: Color(0xFF000000),
            secondary: Color(0xFFFFC46B), surface: Color(0xFF000000),
            onSurface: Color(0xFFFFFFFF), outline: Color(0xFFFFFFFF),
            error: Color(0xFFFF8A80))
        : ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return _base(s, highContrast);
  }

  static ThemeData _base(ColorScheme s, bool hc) => ThemeData(
        useMaterial3: true,
        colorScheme: s,
        scaffoldBackgroundColor: s.surface,
        visualDensity: VisualDensity.comfortable,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(88, 60),
            textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(88, 60),
            side: BorderSide(color: s.outline, width: hc ? 2.5 : 1.5),
            textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        appBarTheme: AppBarTheme(
          centerTitle: true, backgroundColor: s.surface,
          foregroundColor: s.onSurface, elevation: 0,
          titleTextStyle: TextStyle(
              fontSize: 23, fontWeight: FontWeight.w700, color: s.onSurface),
        ),
        sliderTheme: const SliderThemeData(
            trackHeight: 8,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 16)),
        cardTheme: CardThemeData(
          elevation: hc ? 0 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: hc ? BorderSide(color: s.outline, width: 2) : BorderSide.none,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          contentTextStyle: const TextStyle(fontSize: 17),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  static Color givenText(ColorScheme s) => s.onSurface;
  static Color enteredText(ColorScheme s) =>
      s.brightness == Brightness.dark ? const Color(0xFF7FE7D2) : const Color(0xFF0B5F51);
  static Color wrongText(ColorScheme s) =>
      s.brightness == Brightness.dark ? const Color(0xFFFF9E9E) : const Color(0xFFC02626);
  static Color selectedFill(ColorScheme s) =>
      s.primary.withValues(alpha: s.brightness == Brightness.dark ? .36 : .22);
  static Color peerFill(ColorScheme s) =>
      s.primary.withValues(alpha: s.brightness == Brightness.dark ? .13 : .075);
  static Color hintFill(ColorScheme s) => const Color(0xFF2E9B57).withValues(alpha: .40);

  /// A filled square. Near-solid, because the picture is the whole point and a
  /// washed-out fill makes it unreadable at arm's length.
  /// A shaded-out cell. Near-solid: the shading IS the answer, so a washed-out
  /// fill makes the picture unreadable at arm's length.
  static Color shadedCell(ColorScheme s) =>
      s.brightness == Brightness.dark
          ? const Color(0xFF9DB4AE)
          : const Color(0xFF1B2B28);

  /// The number printed on a shaded cell. Kept legible on purpose: players
  /// re-check what they shaded constantly, and hiding it would force an undo
  /// just to look.
  static Color onShaded(ColorScheme s) =>
      s.brightness == Brightness.dark
          ? const Color(0xFF16211F)
          : const Color(0xFFD6E4E0);

  /// The ring marking a cell the player has proved must stay. A different HUE
  /// from the shading, not just a different lightness, so the two states
  /// survive colour-blindness.
  static Color circleColour(ColorScheme s) =>
      s.brightness == Brightness.dark
          ? const Color(0xFFFFC46B)
          : const Color(0xFFB4530A);
}
