import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/terminal_state.dart';
import '../theme.dart';

/// The bottom terminal drawer — instrument-panel chrome, mono scrollback,
/// one input line. Docked under whatever tab is active, like VS Code's
/// panel: drag the top edge to resize, ↑/↓ recalls command history, and the
/// quick chips cover what people actually type here.
class TerminalPanel extends ConsumerStatefulWidget {
  const TerminalPanel({super.key});

  @override
  ConsumerState<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends ConsumerState<TerminalPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  int? _historyIndex; // null = live input; otherwise position in history

  static final _quickCommands = [
    'ollama list',
    'ollama ps',
    if (Platform.isWindows) 'ipconfig' else 'ifconfig',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String cmd) {
    _historyIndex = null;
    _input.clear();
    _focus.requestFocus();
    ref.read(terminalProvider.notifier).run(cmd);
  }

  /// ↑/↓ through past commands, shell-style. Editing resets to live input.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final history = ref.read(terminalProvider.notifier).history;
    if (history.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _historyIndex = _historyIndex == null
          ? history.length - 1
          : (_historyIndex! - 1).clamp(0, history.length - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_historyIndex == null) return KeyEventResult.ignored;
      _historyIndex =
          _historyIndex! + 1 >= history.length ? null : _historyIndex! + 1;
    } else {
      return KeyEventResult.ignored;
    }
    final text = _historyIndex == null ? '' : history[_historyIndex!];
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final term = ref.watch(terminalProvider);
    final height = ref.watch(terminalHeightProvider);

    // Keep the newest output on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });

    return SizedBox(
      height: height,
      child: Column(
        children: [
          // Drag handle: the whole header row doubles as the splitter.
          MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: (d) => ref
                  .read(terminalHeightProvider.notifier)
                  .state = (height - d.delta.dy).clamp(140.0, 560.0),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Sym.surface,
                  border: Border(
                    top: BorderSide(color: Sym.hairline),
                    bottom: BorderSide(color: Sym.hairline),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.drag_handle, size: 13, color: Sym.inkFaint),
                    const SizedBox(width: 8),
                    Text('TERMINAL', style: Sym.label(size: 9)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        term.cwd,
                        style: Sym.mono(size: 10, color: Sym.inkFaint),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (term.busy) ...[
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Sym.amberDim),
                      ),
                      const SizedBox(width: 8),
                      _HeaderIcon(
                        icon: Icons.stop_circle_outlined,
                        color: Sym.danger,
                        tooltip: 'Stop command',
                        onTap: () => ref.read(terminalProvider.notifier).kill(),
                      ),
                    ],
                    _HeaderIcon(
                      icon: Icons.copy_all_outlined,
                      tooltip: 'Copy output',
                      onTap: () => Clipboard.setData(ClipboardData(
                          text: term.lines.map((l) => l.text).join('\n'))),
                    ),
                    _HeaderIcon(
                      icon: Icons.block_outlined,
                      tooltip: 'Clear',
                      onTap: () =>
                          ref.read(terminalProvider.notifier).run('clear'),
                    ),
                    _HeaderIcon(
                      icon: Icons.close,
                      tooltip: 'Hide terminal',
                      onTap: () =>
                          ref.read(terminalOpenProvider.notifier).state = false,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: Sym.bg,
              child: SelectionArea(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: term.lines.length,
                  itemBuilder: (_, i) {
                    final l = term.lines[i];
                    return Padding(
                      padding: EdgeInsets.only(
                          top: l.kind == LineKind.input && i > 0 ? 8 : 0),
                      child: Text(
                        l.text,
                        style: Sym.mono(
                          size: 11.5,
                          weight: l.kind == LineKind.input
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: switch (l.kind) {
                            LineKind.input => Sym.amber,
                            LineKind.out => Sym.ink,
                            LineKind.err => Sym.danger,
                            LineKind.info => Sym.inkFaint,
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Sym.surface,
              border: Border(top: BorderSide(color: Sym.hairline)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                Text('❯', style: Sym.mono(size: 12, color: Sym.teal)),
                const SizedBox(width: 8),
                Expanded(
                  child: Focus(
                    onKeyEvent: _onKey,
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      enabled: !term.busy,
                      style: Sym.mono(size: 12, color: Sym.ink),
                      onSubmitted: _submit,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: term.busy
                            ? 'running…'
                            : 'type a command · ↑ for history',
                        hintStyle: Sym.mono(size: 11, color: Sym.inkFaint),
                      ),
                    ),
                  ),
                ),
                for (final cmd in _quickCommands) ...[
                  const SizedBox(width: 6),
                  _QuickCmdChip(
                    label: cmd,
                    onTap: term.busy ? null : () => _submit(cmd),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A one-tap terminal command chip (ollama list, ipconfig, …). Teal because
/// these are machine queries; brightens toward teal on hover.
class _QuickCmdChip extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const _QuickCmdChip({required this.label, required this.onTap});

  @override
  State<_QuickCmdChip> createState() => _QuickCmdChipState();
}

class _QuickCmdChipState extends State<_QuickCmdChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Sym.fast,
          curve: Sym.ease,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: _hover && enabled
                ? Sym.tealDim.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border.all(
                color: _hover && enabled ? Sym.tealDim : Sym.hairline),
          ),
          child: Text(widget.label,
              style: Sym.mono(
                  size: 9.5,
                  color: enabled
                      ? (_hover ? Sym.teal : Sym.tealDim)
                      : Sym.inkFaint)),
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _HeaderIcon(
      {required this.icon,
      required this.tooltip,
      this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Icon(icon, size: 14, color: color ?? Sym.inkDim),
          ),
        ),
      );
}
