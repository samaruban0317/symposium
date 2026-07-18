/// Shared visual vocabulary for the persona studio: the accent palette a
/// persona's `accentIndex` points into, the sigil avatar, and small controls.
library;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Muted companions to the lamplight/phosphor pair — an index into this list
/// is stored on the persona, so append, never reorder.
const personaAccents = <Color>[
  Sym.amber,
  Sym.teal,
  Color(0xFFC7808B), // rose
  Color(0xFFA08BC7), // violet
  Color(0xFF9DB86E), // moss
];

Color personaAccent(int index) =>
    personaAccents[index.clamp(0, personaAccents.length - 1)];

/// The persona's mark: its glyph in its accent, ringed by a hairline.
class PersonaSigil extends StatelessWidget {
  final String glyph;
  final Color accent;
  final double size;
  const PersonaSigil(
      {super.key, required this.glyph, required this.accent, this.size = 34});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent.withValues(alpha: 0.5)),
          color: accent.withValues(alpha: 0.08),
        ),
        child: Text(glyph,
            style: Sym.display(size: size * 0.44, color: accent),
            textAlign: TextAlign.center),
      );
}

/// Tiny mono revision chip: `r3`. Amber while it matches the latest applied
/// revision, dimmed once superseded — old answers visibly age.
class RevisionChip extends StatelessWidget {
  final int revision;
  final bool current;
  const RevisionChip({super.key, required this.revision, required this.current});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
              color: (current ? Sym.amber : Sym.inkFaint).withValues(alpha: 0.5)),
        ),
        child: Text('r$revision',
            style: Sym.mono(
                size: 9, color: current ? Sym.amber : Sym.inkFaint, spacing: 0.5)),
      );
}

/// Bordered mono text button, the studio's workhorse control.
class StudioButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool filled;
  const StudioButton(
      {super.key,
      required this.label,
      this.color = Sym.inkDim,
      this.onTap,
      this.filled = false});

  @override
  Widget build(BuildContext context) {
    final c = onTap == null ? Sym.inkFaint : color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.withValues(alpha: filled ? 0.9 : 0.45)),
          color: filled ? c.withValues(alpha: 0.12) : null,
        ),
        child: Text(label, style: Sym.label(size: 9, color: c)),
      ),
    );
  }
}
