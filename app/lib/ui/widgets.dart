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
          const SizedBox(height: 2),
          Text(value,
              style: Sym.mono(
                  size: 14, color: valueColor ?? Sym.ink, weight: FontWeight.w600)),
        ],
      );
}

/// Status dot: amber pulse = online, faint = offline.
class StatusDot extends StatelessWidget {
  final bool online;
  const StatusDot({super.key, required this.online});

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: online ? Sym.teal : Sym.inkFaint,
          boxShadow: online
              ? [BoxShadow(color: Sym.teal.withValues(alpha: 0.5), blurRadius: 6)]
              : null,
        ),
      );
}
