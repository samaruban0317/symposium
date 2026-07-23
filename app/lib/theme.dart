import 'package:flutter/material.dart';

/// One complete set of Symposium colors. Two instances exist — lamplight
/// (dark) and daylight (light) — and [Sym] points at whichever is active.
class SymPalette {
  final Color bg, surface, surfaceRaised, hairline;
  final Color amber, amberDim, teal, tealDim, danger;
  final Color ink, inkDim, inkFaint;

  const SymPalette({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.hairline,
    required this.amber,
    required this.amberDim,
    required this.teal,
    required this.tealDim,
    required this.danger,
    required this.ink,
    required this.inkDim,
    required this.inkFaint,
  });
}

/// "Lamplight academy": warm ink-black surfaces, candlelight amber for the
/// human side, phosphor teal for machine telemetry.
const _lamplight = SymPalette(
  bg: Color(0xFF0F0D0A),
  surface: Color(0xFF171410),
  surfaceRaised: Color(0xFF1E1A14),
  hairline: Color(0xFF2A251D),
  amber: Color(0xFFE0A458),
  amberDim: Color(0xFF8A6836),
  teal: Color(0xFF6FC7B6),
  tealDim: Color(0xFF3E7A6E),
  danger: Color(0xFFC2604C),
  ink: Color(0xFFEAE3D4),
  inkDim: Color(0xFF8A8172),
  inkFaint: Color(0xFF57503F),
);

/// "Daylight reading room": warm paper surfaces, the same amber/teal language
/// darkened until it reads as ink rather than light.
const _daylight = SymPalette(
  bg: Color(0xFFF7F2E9),
  surface: Color(0xFFF0EADC),
  surfaceRaised: Color(0xFFE8E0CE),
  hairline: Color(0xFFD6CBB2),
  amber: Color(0xFF9C6B14),
  amberDim: Color(0xFFC09C5C),
  teal: Color(0xFF1E6B5C),
  tealDim: Color(0xFF6FA093),
  danger: Color(0xFFA8402D),
  ink: Color(0xFF2B2416),
  inkDim: Color(0xFF6E6450),
  inkFaint: Color(0xFFA2977E),
);

/// Symposium's visual identity. Serif display type (Spectral) over an
/// instrument-panel mono (IBM Plex Mono), in whichever palette is active.
///
/// The colors are static getters, not consts, so the whole app re-skins by
/// swapping the palette and rebuilding the tree (main.dart re-keys the home
/// subtree on toggle — cheaper than threading a theme object through every
/// widget in a two-palette app).
abstract class Sym {
  static SymPalette _p = _lamplight;

  static bool get isDark => identical(_p, _lamplight);
  static void setDark(bool dark) => _p = dark ? _lamplight : _daylight;

  // Surfaces
  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surfaceRaised => _p.surfaceRaised;
  static Color get hairline => _p.hairline;

  // Accents
  static Color get amber => _p.amber; // lamplight — the human side
  static Color get amberDim => _p.amberDim;
  static Color get teal => _p.teal; // phosphor — the machine side
  static Color get tealDim => _p.tealDim;
  static Color get danger => _p.danger;

  // Text
  static Color get ink => _p.ink;
  static Color get inkDim => _p.inkDim;
  static Color get inkFaint => _p.inkFaint;

  // ---- Motion ------------------------------------------------------------
  // Shared timings so every micro-interaction in the app feels like it came
  // from one hand. Fast = hover/press feedback; med = panels & selections;
  // slow = view transitions. The curve is the house easing.

  /// Hover, press, and focus feedback — barely-there, never laggy.
  static const Duration fast = Duration(milliseconds: 120);

  /// Selections, panels opening, chips settling.
  static const Duration med = Duration(milliseconds: 200);

  /// View cross-fades and larger reveals.
  static const Duration slow = Duration(milliseconds: 320);

  /// The house easing — a gentle decelerate that reads as "settling", not
  /// "snapping". Used everywhere so motion stays consistent.
  static const Curve ease = Curves.easeOutCubic;

  /// Soft ambient lift for raised surfaces (composer, floating buttons,
  /// dialogs). Tuned per palette so it reads on both ink and paper.
  static List<BoxShadow> lift({double strength = 1}) => [
        BoxShadow(
          color: (isDark ? Colors.black : const Color(0xFF6E6450))
              .withValues(alpha: (isDark ? 0.35 : 0.14) * strength),
          blurRadius: 18 * strength,
          offset: Offset(0, 6 * strength),
        ),
      ];

  /// A colored glow, for accent focus rings and live indicators.
  static List<BoxShadow> glow(Color c, {double strength = 1}) => [
        BoxShadow(
          color: c.withValues(alpha: 0.22 * strength),
          blurRadius: 14 * strength,
          spreadRadius: 0.5 * strength,
        ),
      ];

  static TextStyle display({double size = 24, Color? color, FontWeight weight = FontWeight.w500}) =>
      TextStyle(fontFamily: 'Spectral', fontSize: size, color: color ?? _p.ink, fontWeight: weight, height: 1.25);

  static TextStyle body({double size = 15, Color? color, double height = 1.55}) =>
      TextStyle(fontFamily: 'Spectral', fontSize: size, color: color ?? _p.ink, height: height);

  static TextStyle mono({double size = 12, Color? color, FontWeight weight = FontWeight.w400, double spacing = 0}) =>
      TextStyle(fontFamily: 'IBMPlexMono', fontSize: size, color: color ?? _p.inkDim, fontWeight: weight, letterSpacing: spacing);

  /// Small-caps-style instrument label: `MODEL`, `TOK/S`, `CONTEXT`.
  static TextStyle label({Color? color, double size = 10}) =>
      TextStyle(fontFamily: 'IBMPlexMono', fontSize: size, color: color ?? _p.inkDim, fontWeight: FontWeight.w600, letterSpacing: 2.0);

  static ThemeData theme() => ThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: bg,
        colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
          primary: amber,
          secondary: teal,
          surface: surface,
          error: danger,
        ),
        dividerColor: hairline,
        splashFactory: InkSparkle.splashFactory,
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: amber,
          selectionColor: amber.withValues(alpha: 0.25),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(hairline),
          thickness: WidgetStateProperty.all(4),
        ),
        useMaterial3: true,
      );
}
