import 'package:flutter/material.dart';

import '../theme.dart';

/// Width for AlertDialog content: the desktop layouts ask for ~380–400px,
/// which overflows a 360dp phone once dialog insets are subtracted. Clamp to
/// what the screen actually offers.
double dialogWidth(BuildContext context, [double ideal = 400]) {
  final available = MediaQuery.sizeOf(context).width - 96;
  return available < ideal ? available : ideal;
}

/// A wrapper that gives any child a subtle press-in and hover feedback —
/// the tactile "this is a control" cue desktop apps get from cursors and
/// mobile apps get from ripples. Scales down a hair on press, lifts a hair
/// on hover. Pure built-in animation; no dependency.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final double pressScale;
  final bool hoverFade; // brighten slightly on hover

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.tooltip,
    this.pressScale = 0.94,
    this.hoverFade = false,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    Widget child = AnimatedScale(
      scale: _down ? widget.pressScale : 1,
      duration: Sym.fast,
      curve: Sym.ease,
      child: widget.hoverFade
          ? AnimatedOpacity(
              opacity: !enabled ? 0.5 : (_hover ? 1 : 0.82),
              duration: Sym.fast,
              child: widget.child,
            )
          : widget.child,
    );

    child = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        child: child,
      ),
    );

    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

/// The "machine is thinking" heartbeat: three phosphor dots that breathe in
/// sequence, like a level meter settling. Reads as *typing* rather than a bare
/// blinking block, and stays on-brand (teal = the machine side).
class StreamingCursor extends StatefulWidget {
  const StreamingCursor({super.key});

  @override
  State<StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 16,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                _Dot(phase: (_c.value + i * 0.18) % 1.0),
              ],
            ],
          ),
        ),
      );
}

class _Dot extends StatelessWidget {
  final double phase; // 0..1
  const _Dot({required this.phase});

  @override
  Widget build(BuildContext context) {
    // A soft rise-and-fall — brightest at the crest, dim at the trough.
    final t = (0.5 - (phase - 0.5).abs()) * 2; // 0..1..0 triangle
    final glow = Curves.easeInOut.transform(t);
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(Sym.tealDim, Sym.teal, glow),
        boxShadow: glow > 0.6
            ? [BoxShadow(color: Sym.teal.withValues(alpha: 0.5 * glow), blurRadius: 5)]
            : null,
      ),
    );
  }
}

/// A shimmering placeholder bar for loading lists — sweeps a soft highlight
/// across a hairline block, the "content is on its way" cue.
class SkeletonBar extends StatefulWidget {
  final double width;
  final double height;
  final EdgeInsets margin;
  const SkeletonBar({
    super.key,
    this.width = double.infinity,
    this.height = 11,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<SkeletonBar> createState() => _SkeletonBarState();
}

class _SkeletonBarState extends State<SkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        width: widget.width,
        height: widget.height,
        margin: widget.margin,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: Sym.hairline.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => FractionallySizedBox(
            widthFactor: 0.4,
            alignment: Alignment(-1 + _c.value * 2.6, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Sym.amberDim.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// Instrument-panel readout: a tiny mono label over a value.
class Readout extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor; // null = the palette's ink

  const Readout({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Sym.label()),
          const SizedBox(height: 2),
          Text(value,
              style: Sym.mono(
                  size: 14, color: valueColor ?? Sym.ink, weight: FontWeight.w600)),
        ],
      );
}

/// Status dot: a slow phosphor breath = online, a still faint dot = offline.
/// The pulse is the whole tell that a live connection is holding — worth the
/// one ticker.
class StatusDot extends StatefulWidget {
  final bool online;
  const StatusDot({super.key, required this.online});

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.online) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.online && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.online && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.online) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Sym.inkFaint),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value); // 0..1
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(Sym.tealDim, Sym.teal, t),
            boxShadow: [
              BoxShadow(
                color: Sym.teal.withValues(alpha: 0.35 + 0.35 * t),
                blurRadius: 5 + 4 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}
