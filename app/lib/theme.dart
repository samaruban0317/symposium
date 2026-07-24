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
///
/// Tuned for an editorial, calm depth: the surface ladder now climbs in even,
/// perceptible steps (bg → surface → raised) so elevation reads without heavy
/// shadow, and the hairline sits just bright enough to draw a clean 1px edge.
const _lamplight = SymPalette(
  bg: Color(0xFF0E0C09),
  surface: Color(0xFF16130E),
  surfaceRaised: Color(0xFF201B14),
  hairline: Color(0xFF302A20),
  amber: Color(0xFFE4AC64),
  amberDim: Color(0xFF937039),
  teal: Color(0xFF74CFBD),
  tealDim: Color(0xFF3E7A6E),
  danger: Color(0xFFCB6752),
  ink: Color(0xFFEDE7D9),
  inkDim: Color(0xFF938A79),
  inkFaint: Color(0xFF5D5544),
);

/// "Daylight reading room": warm paper surfaces, the same amber/teal language
/// darkened until it reads as ink rather than light.
const _daylight = SymPalette(
  bg: Color(0xFFF8F3EA),
  surface: Color(0xFFF1EBDD),
  surfaceRaised: Color(0xFFEAE2D0),
  hairline: Color(0xFFDACFB6),
  amber: Color(0xFF95650F),
  amberDim: Color(0xFFBE9856),
  teal: Color(0xFF1B6759),
  tealDim: Color(0xFF6FA093),
  danger: Color(0xFFA53C29),
  ink: Color(0xFF29220F),
  inkDim: Color(0xFF6A6047),
  inkFaint: Color(0xFF9E937A),
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

  // ── Spacing scale ──────────────────────────────────────────────────────
  // An 8px rhythm (with a 4px half-step) so padding/gaps stay consistent
  // across the app. Prefer these over magic numbers.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;

  // ── Corner radii ───────────────────────────────────────────────────────
  static const double radiusSm = 6;
  static const double radiusMd = 10;
  static const double radiusLg = 14;
  static const Radius rSm = Radius.circular(radiusSm);
  static const Radius rMd = Radius.circular(radiusMd);
  static const Radius rLg = Radius.circular(radiusLg);

  // ── Motion ─────────────────────────────────────────────────────────────
  // Gentle, consistent micro-motion. Fast for hover/press, base for state
  // changes, slow for larger transitions.
  static const Duration motionFast = Duration(milliseconds: 120);
  static const Duration motionBase = Duration(milliseconds: 180);
  static const Duration motionSlow = Duration(milliseconds: 260);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;

  // ── Depth ──────────────────────────────────────────────────────────────
  /// A single hairline border side — the app's default 1px edge.
  static BorderSide get hairSide => BorderSide(color: _p.hairline, width: 1);

  /// A hairline border on all sides, optionally tinted by an accent.
  static Border hairBorder({Color? color, double width = 1}) =>
      Border.all(color: color ?? _p.hairline, width: width);

  /// Soft, low-opacity elevation. [level] 1 = resting card, 2 = raised
  /// surface / popover, 3 = dialog / floating panel. Never a harsh drop.
  static List<BoxShadow> shadow([int level = 1]) {
    final base = isDark ? 0.44 : 0.12;
    switch (level) {
      case 2:
        return [
          BoxShadow(color: Colors.black.withValues(alpha: base * 0.7), blurRadius: 18, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.black.withValues(alpha: base * 0.4), blurRadius: 4, offset: const Offset(0, 1)),
        ];
      case 3:
        return [
          BoxShadow(color: Colors.black.withValues(alpha: base), blurRadius: 40, offset: const Offset(0, 16)),
          BoxShadow(color: Colors.black.withValues(alpha: base * 0.5), blurRadius: 8, offset: const Offset(0, 2)),
        ];
      default:
        return [
          BoxShadow(color: Colors.black.withValues(alpha: base * 0.6), blurRadius: 10, offset: const Offset(0, 3)),
        ];
    }
  }

  /// A soft accent halo — the one confident "glow" moment per view (status
  /// dot, active pill, streaming cursor). Kept low-opacity and diffuse.
  static List<BoxShadow> glow(Color color, {double strength = 0.45, double blur = 12}) =>
      [BoxShadow(color: color.withValues(alpha: strength), blurRadius: blur)];

  /// A whisper-quiet vertical wash for accent surfaces (active tab, hero).
  static LinearGradient accentWash(Color color, {double top = 0.14, double bottom = 0.0}) =>
      LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: top), color.withValues(alpha: bottom)],
      );

  static TextStyle display({double size = 24, Color? color, FontWeight weight = FontWeight.w500}) =>
      TextStyle(fontFamily: 'Spectral', fontSize: size, color: color ?? _p.ink, fontWeight: weight, height: 1.2, letterSpacing: -0.2);

  static TextStyle body({double size = 15, Color? color, double height = 1.55, FontWeight weight = FontWeight.w400}) =>
      TextStyle(fontFamily: 'Spectral', fontSize: size, color: color ?? _p.ink, height: height, fontWeight: weight);

  static TextStyle mono({double size = 12, Color? color, FontWeight weight = FontWeight.w400, double spacing = 0}) =>
      TextStyle(fontFamily: 'IBMPlexMono', fontSize: size, color: color ?? _p.inkDim, fontWeight: weight, letterSpacing: spacing);

  /// Small-caps-style instrument label: `MODEL`, `TOK/S`, `CONTEXT`.
  static TextStyle label({Color? color, double size = 10, double spacing = 1.8}) =>
      TextStyle(fontFamily: 'IBMPlexMono', fontSize: size, color: color ?? _p.inkDim, fontWeight: FontWeight.w600, letterSpacing: spacing);

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
        splashColor: amber.withValues(alpha: 0.10),
        highlightColor: amber.withValues(alpha: 0.06),
        hoverColor: ink.withValues(alpha: 0.05),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: amber,
          selectionColor: amber.withValues(alpha: 0.25),
        ),
        tooltipTheme: TooltipThemeData(
          waitDuration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(
            color: surfaceRaised,
            borderRadius: const BorderRadius.all(rSm),
            border: Border.fromBorderSide(hairSide),
            boxShadow: shadow(2),
          ),
          textStyle: mono(size: 11, color: inkDim),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(hairline),
          thickness: WidgetStateProperty.all(4),
          radius: const Radius.circular(4),
        ),
        useMaterial3: true,
      );
}
