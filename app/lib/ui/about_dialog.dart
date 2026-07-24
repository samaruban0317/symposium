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
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Sym.surface,
            borderRadius: const BorderRadius.all(Sym.rLg),
            border: Border.all(color: Sym.amberDim.withValues(alpha: 0.35)),
            boxShadow: Sym.shadow(3),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Sym.rLg),
            child: Container(
              // A whisper of amber warmth pooled at the top — the one accent
              // moment for the card.
              decoration:
                  BoxDecoration(gradient: Sym.accentWash(Sym.amber, top: 0.06)),
              padding: const EdgeInsets.fromLTRB(
                  Sym.space6, Sym.space6, Sym.space6, Sym.space4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('☙',
                        style: Sym.display(size: 20, color: Sym.amber)),
                    const SizedBox(width: Sym.space3),
                    Text('Symposium',
                        style: Sym.display(
                            size: 22, weight: FontWeight.w600, color: Sym.ink)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(Sym.rSm),
                        border: Border.fromBorderSide(Sym.hairSide),
                      ),
                      child: Text('v$kSymVersion',
                          style: Sym.mono(size: 11, color: Sym.inkDim)),
                    ),
                  ]),
                  const SizedBox(height: Sym.space2),
                  Text('A VISIONARY SPARKS PRODUCT',
                      style: Sym.label(color: Sym.teal)),
                  const SizedBox(height: Sym.space4),
                  Text(
                    'A gathering of minds — run local open-source models, share '
                    'them across your network, race them in the arena, and train '
                    'your own. Everything stays on your hardware.',
                    style: Sym.body(size: 13.5, color: Sym.inkDim, height: 1.6),
                  ),
                  const SizedBox(height: Sym.space5),
                  Wrap(spacing: Sym.space2, runSpacing: Sym.space2, children: const [
                    _LinkButton(label: 'VISIONARYSPARKS.IN', url: _siteUrl),
                    _LinkButton(label: 'SOURCE · GITHUB', url: _repoUrl),
                  ]),
                  const SizedBox(height: Sym.space2),
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
        side: BorderSide(color: Sym.amberDim.withValues(alpha: 0.7)),
        backgroundColor: Sym.amber.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Sym.rSm)),
      ),
      child: Text(label, style: Sym.label(color: Sym.amber)),
    );
  }
}
