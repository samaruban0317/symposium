import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../theme.dart';

/// Renders one assistant message as markdown.
///
/// gpt_markdown was chosen because it is built for LLM output: it parses
/// incrementally-growing text without throwing on unclosed fences, so the
/// message doesn't flicker or reflow wildly while tokens stream in.
class MessageMarkdown extends StatelessWidget {
  final String text;
  const MessageMarkdown({super.key, required this.text});

  @override
  Widget build(BuildContext context) => GptMarkdown(
        text,
        style: Sym.body(size: 15.5),
        codeBuilder: (context, name, code, closed) =>
            _CodeBlock(language: name, code: code, closed: closed),
        highlightBuilder: (context, text, style) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Sym.surfaceRaised,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Sym.hairline),
          ),
          child: Text(text, style: Sym.mono(size: 12.5, color: Sym.teal)),
        ),
      );
}

/// Fenced code block: instrument-panel framing, language tag, copy button.
class _CodeBlock extends StatefulWidget {
  final String language;
  final String code;
  final bool closed; // false while the closing ``` hasn't streamed in yet

  const _CodeBlock(
      {required this.language, required this.code, required this.closed});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Sym.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Sym.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 30,
              padding: const EdgeInsets.only(left: 12, right: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Sym.hairline)),
              ),
              child: Row(
                children: [
                  Text(
                    widget.language.isEmpty
                        ? 'CODE'
                        : widget.language.toUpperCase(),
                    style: Sym.label(size: 9, color: Sym.inkFaint),
                  ),
                  if (!widget.closed) ...[
                    const SizedBox(width: 8),
                    Text('…', style: Sym.mono(size: 11, color: Sym.tealDim)),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: _copied ? 'Copied' : 'Copy code',
                    onPressed: _copy,
                    visualDensity: VisualDensity.compact,
                    icon: AnimatedSwitcher(
                      duration: Sym.med,
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_all_outlined,
                        key: ValueKey(_copied),
                        size: 14,
                        color: _copied ? Sym.teal : Sym.inkDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Text(widget.code,
                  style: Sym.mono(size: 12.5, color: Sym.ink)),
            ),
          ],
        ),
      );
}
