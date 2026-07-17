import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../theme.dart';

/// One-click model install. Type any name from the Ollama library, or pick a
/// small starter model. Progress shows in the sidebar so this can close.
class PullDialog extends ConsumerStatefulWidget {
  const PullDialog({super.key});

  @override
  ConsumerState<PullDialog> createState() => _PullDialogState();
}

class _PullDialogState extends ConsumerState<PullDialog> {
  final _ctrl = TextEditingController();

  static const _suggestions = <(String, String)>[
    ('qwen2.5:0.5b', '~400 MB · tiny & fast'),
    ('llama3.2:1b', '~1.3 GB · small all-rounder'),
    ('qwen2.5:1.5b', '~1 GB · good quality/size'),
    ('gemma2:2b', '~1.6 GB · strong for its size'),
    ('deepseek-r1:1.5b', '~1.1 GB · shows its reasoning'),
  ];

  void _start(String name) {
    if (name.trim().isEmpty) return;
    ref.read(pullControllerProvider.notifier).start(name.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Sym.surfaceRaised,
      title: Text('Install a model', style: Sym.display(size: 20)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downloads happen inside the app — no terminal.\nAny name from ollama.com/library works.',
              style: Sym.mono(size: 11, color: Sym.inkDim),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: Sym.mono(size: 13, color: Sym.ink),
              onSubmitted: _start,
              decoration: const InputDecoration(
                hintText: 'model:tag  (e.g. qwen2.5:0.5b)',
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Sym.hairline),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('GOOD FIRST MODELS', style: Sym.label()),
            const SizedBox(height: 8),
            ..._suggestions.map(
              (s) => Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _start(s.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                    child: Row(
                      children: [
                        Text(s.$1,
                            style: Sym.mono(size: 12, color: Sym.amber, weight: FontWeight.w600)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(s.$2, style: Sym.mono(size: 11, color: Sym.inkFaint)),
                        ),
                        const Icon(Icons.download_outlined, size: 14, color: Sym.inkFaint),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL', style: Sym.label()),
        ),
        TextButton(
          onPressed: () => _start(_ctrl.text),
          child: Text('INSTALL', style: Sym.label(color: Sym.amber)),
        ),
      ],
    );
  }
}
