import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Symposium's visual identity: "lamplight academy".
/// Warm ink-black surfaces, candlelight amber for the human side,
/// phosphor teal for machine telemetry. Serif display type (Spectral)
/// over an instrument-panel mono (IBM Plex Mono).
abstract class Sym {
  // Surfaces (warm blacks, never pure #000)
  static const bg = Color(0xFF0F0D0A);
  static const surface = Color(0xFF171410);
  static const surfaceRaised = Color(0xFF1E1A14);
  static const hairline = Color(0xFF2A251D);

  // Accents
  static const amber = Color(0xFFE0A458); // lamplight — the human side
  static const amberDim = Color(0xFF8A6836);
  static const teal = Color(0xFF6FC7B6); // phosphor — the machine side
  static const tealDim = Color(0xFF3E7A6E);
  static const danger = Color(0xFFC2604C);

  // Text
  static const ink = Color(0xFFEAE3D4);
  static const inkDim = Color(0xFF8A8172);
  static const inkFaint = Color(0xFF57503F);

  static TextStyle display({double size = 24, Color color = ink, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.spectral(fontSize: size, color: color, fontWeight: weight, height: 1.25);

  static TextStyle body({double size = 15, Color color = ink, double height = 1.55}) =>
      GoogleFonts.spectral(fontSize: size, color: color, height: height);

  static TextStyle mono({double size = 12, Color color = inkDim, FontWeight weight = FontWeight.w400, double spacing = 0}) =>
      GoogleFonts.ibmPlexMono(fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing);

  /// Small-caps-style instrument label: `MODEL`, `TOK/S`, `CONTEXT`.
  static TextStyle label({Color color = inkDim, double size = 10}) =>
      GoogleFonts.ibmPlexMono(fontSize: size, color: color, fontWeight: FontWeight.w600, letterSpacing: 2.0);

  static ThemeData theme() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: amber,
          secondary: teal,
          surface: surface,
          error: danger,
        ),
        dividerColor: hairline,
        splashFactory: InkSparkle.splashFactory,
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: amber,
          selectionColor: Color(0x33E0A458),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(hairline),
          thickness: WidgetStateProperty.all(4),
        ),
        useMaterial3: true,
      );
}
