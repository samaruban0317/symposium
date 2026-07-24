/// Shared visual vocabulary for the persona studio: the accent palette a
/// persona's `accentIndex` points into, the sigil avatar, and small controls.
library;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Muted companions to the lamplight/phosphor pair — an index into this list
/// is stored on the persona, so append, never reorder. A getter (not a final)
/// so the first two entries track the active palette.
List<Color> get personaAccents => <Color>[
      Sym.amber,
      Sym.teal,
      const Color(0xFFC7808B), // rose
      const Color(0xFFA08BC7), // violet
      const Color(0xFF9DB86E), // moss
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
          gradient: RadialGradient(
            colors: [
              accent.withValues(alpha: 0.16),
              accent.withValues(alpha: 0.06),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.14),
              blurRadius: size * 0.22,
            ),
          ],
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
  Widget build(BuildContext context) {
    final c = current ? Sym.amber : Sym.inkFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: current ? c.withValues(alpha: 0.12) : Colors.transparent,
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text('r$revision',
          style: Sym.mono(size: 9, color: c, spacing: 0.5)),
    );
  }
}

/// Bordered mono text button, the studio's workhorse control. A gentle hover
/// wash keeps it feeling alive without pulling focus.
class StudioButton extends StatefulWidget {
  final String label;
  final Color? color; // null = the palette's dim ink
  final VoidCallback? onTap;
  final bool filled;
  const StudioButton(
      {super.key,
      required this.label,
      this.color,
      this.onTap,
      this.filled = false});

  @override
  State<StudioButton> createState() => _StudioButtonState();
}

class _StudioButtonState extends State<StudioButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final c = enabled ? (widget.color ?? Sym.inkDim) : Sym.inkFaint;
    final fillAlpha = widget.filled
        ? (_hover ? 0.2 : 0.12)
        : (_hover && enabled ? 0.08 : 0.0);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
                color: c.withValues(alpha: widget.filled ? 0.9 : 0.45)),
            color: c.withValues(alpha: fillAlpha),
          ),
          child: Text(widget.label, style: Sym.label(size: 9, color: c)),
        ),
      ),
    );
  }
}
