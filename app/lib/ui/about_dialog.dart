import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// Shown in the About dialog — keep in sync with pubspec.yaml `version:`.
const String kSymVersion = '0.2.1';

const String _siteUrl = 'https://visionarysparks.in/symposium';
const String _repoUrl = 'https://github.com/samaruban0317/symposium';

void showSymAbout(BuildContext context) =>
    showDialog(context: context, builder: (_) => const SymAboutDialog());

/// Branded About card: Symposium is a Visionary Sparks product.
class SymAboutDialog extends StatelessWidget {
  const SymAboutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // A gentle scale-and-fade entrance so the card arrives rather than pops.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Sym.slow,
      curve: Sym.ease,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
      ),
      child: Dialog(
        backgroundColor: Sym.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Sym.amberDim.withValues(alpha: 0.4)),
        ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('☙', style: Sym.display(size: 20, color: Sym.amberDim)),
                const SizedBox(width: 10),
                Text('Symposium',
                    style: Sym.display(
                        size: 22, weight: FontWeight.w600, color: Sym.ink)),
                const Spacer(),
                Text('v$kSymVersion',
                    style: Sym.mono(size: 11, color: Sym.inkFaint)),
              ]),
              const SizedBox(height: 6),
              Text('A VISIONARY SPARKS PRODUCT',
                  style: Sym.label(color: Sym.teal)),
              const SizedBox(height: 14),
              Text(
                'A gathering of minds — run local open-source models, share '
                'them across your network, race them in the arena, and train '
                'your own. Everything stays on your hardware.',
                style: Sym.body(size: 13.5, color: Sym.inkDim),
              ),
              const SizedBox(height: 18),
              Wrap(spacing: 8, runSpacing: 8, children: const [
                _LinkButton(label: 'VISIONARYSPARKS.IN', url: _siteUrl),
                _LinkButton(label: 'SOURCE · GITHUB', url: _repoUrl),
              ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('CLOSE', style: Sym.label(color: Sym.inkDim)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _LinkButton extends StatefulWidget {
  const _LinkButton({required this.label, required this.url});
  final String label;
  final String url;

  @override
  State<_LinkButton> createState() => _LinkButtonState();
}

class _LinkButtonState extends State<_LinkButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => launchUrl(Uri.parse(widget.url),
            mode: LaunchMode.externalApplication),
        child: AnimatedContainer(
          duration: Sym.fast,
          curve: Sym.ease,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color:
                _hover ? Sym.amber.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hover ? Sym.amber : Sym.amberDim),
          ),
          child: Text(widget.label, style: Sym.label(color: Sym.amber)),
        ),
      ),
    );
  }
}
