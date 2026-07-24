import 'package:flutter/material.dart';

import '../theme.dart';

/// Width for AlertDialog content: the desktop layouts ask for ~380–400px,
/// which overflows a 360dp phone once dialog insets are subtracted. Clamp to
/// what the screen actually offers.
double dialogWidth(BuildContext context, [double ideal = 400]) {
  final available = MediaQuery.sizeOf(context).width - 96;
  return available < ideal ? available : ideal;
}

/// Blinking generation cursor — the little "the machine is thinking" heartbeat.
class StreamingCursor extends StatefulWidget {
  const StreamingCursor({super.key});

  @override
  State<StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Text('▌', style: Sym.mono(size: 15, color: Sym.teal)),
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
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: Sym.motionBase,
            curve: Sym.ease,
            style: Sym.mono(
                size: 14,
                color: valueColor ?? Sym.ink,
                weight: FontWeight.w600,
                spacing: 0.3),
            child: Text(value),
          ),
        ],
      );
}

/// Status dot: a soft teal beacon that breathes when online, faint when off.
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
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

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
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Sym.inkFaint,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = 0.35 + 0.4 * _c.value; // gentle breathing halo
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Sym.teal,
            boxShadow: Sym.glow(Sym.teal, strength: t, blur: 7),
          ),
        );
      },
    );
  }
}
