import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// Shown in the About dialog — keep in sync with pubspec.yaml `version:`.
const String kSymVersion = '0.2.0';

const String _siteUrl = 'https://visionarysparks.in/symposium';
const String _repoUrl = 'https://github.com/samaruban0317/symposium';

void showSymAbout(BuildContext context) =>
    showDialog(context: context, builder: (_) => const SymAboutDialog());

/// Branded About card: Symposium is a Visionary Sparks product.
class SymAboutDialog extends StatelessWidget {
  const SymAboutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Sym.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
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
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      style: OutlinedButton.styleFrom(
        foregroundColor: Sym.amber,
        side: BorderSide(color: Sym.amberDim),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(label, style: Sym.label(color: Sym.amber)),
    );
  }
}
