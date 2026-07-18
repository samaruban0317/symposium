import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat.dart';
import '../../state/arena_state.dart';
import '../../theme.dart';
import '../widgets.dart';
import 'pane_picker.dart';

/// One half of the arena: header strip (source · model · telemetry),
/// the conversation, and — in independent mode — its own composer.
class ArenaPane extends ConsumerStatefulWidget {
  final ArenaSide side;

  /// True in independent mode: this pane gets its own composer.
  final bool ownComposer;

  const ArenaPane({super.key, required this.side, required this.ownComposer});

  @override
  ConsumerState<ArenaPane> createState() => _ArenaPaneState();
}

class _ArenaPaneState extends ConsumerState<ArenaPane> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(paneProvider(widget.side).notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final pane = ref.watch(paneProvider(widget.side));
    final arena = ref.watch(arenaProvider);
    final isFirst = arena.mode == ArenaMode.duel &&
        arena.firstFinisher == widget.side &&
        pane.messages.isNotEmpty;

    // Keep the newest tokens on screen while streaming.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && pane.isStreaming) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });

    return Column(
      children: [
        _PaneHeader(side: widget.side, pane: pane, isFirst: isFirst),
        Expanded(
          child: pane.messages.isEmpty
              ? _PaneEmptyState(side: widget.side, pane: pane)
              : SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    padding:
                        const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
                    itemCount: pane.messages.length,
                    itemBuilder: (_, i) => _PaneMessage(
                      msg: pane.messages[i],
                      streaming:
                          pane.isStreaming && i == pane.messages.length - 1,
                    ),
                  ),
                ),
        ),
        if (pane.error != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Sym.danger),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 13, color: Sym.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(pane.error!,
                      style: Sym.mono(size: 10, color: Sym.danger),
                      maxLines: 3),
                ),
              ],
            ),
          ),
        if (widget.ownComposer)
          _PaneComposer(
            input: _input,
            onSend: _send,
            streaming: pane.isStreaming,
            onStop: () => ref.read(paneProvider(widget.side).notifier).stop(),
            enabled: pane.ready || pane.isStreaming,
          ),
      ],
    );
  }
}

class _PaneHeader extends ConsumerWidget {
  final ArenaSide side;
  final PaneState pane;
  final bool isFirst;

  const _PaneHeader({required this.side, required this.pane, required this.isFirst});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Sym.hairline)),
      ),
      child: Row(
        children: [
          StatusDot(online: pane.online),
          const SizedBox(width: 8),
          // Source chip → pane picker
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => showPanePicker(context, side),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  pane.sourceName,
                  style: Sym.mono(
                      size: 11,
                      color: pane.online ? Sym.ink : Sym.inkFaint,
                      weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Model chip → model picker
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => showPaneModelPicker(context, side),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: Sym.hairline),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        pane.checking
                            ? '…'
                            : (pane.model ?? 'no model'),
                        style: Sym.mono(
                            size: 10.5,
                            color: pane.model != null ? Sym.teal : Sym.inkFaint),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(Icons.unfold_more, size: 11, color: Sym.inkFaint),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          if (isFirst) ...[
            Text('FIRST', style: Sym.label(color: Sym.teal, size: 8.5)),
            const SizedBox(width: 8),
          ],
          if (pane.tokPerSec > 0)
            Text(
              '${pane.tokPerSec.toStringAsFixed(1)} tok/s',
              style: Sym.mono(
                  size: 10,
                  color: pane.isStreaming ? Sym.teal : Sym.inkDim),
            ),
          if (!pane.online && !pane.checking) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Retry connection',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () =>
                  ref.read(paneProvider(side).notifier).refresh(),
              icon: const Icon(Icons.refresh, size: 14, color: Sym.inkDim),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaneEmptyState extends StatelessWidget {
  final ArenaSide side;
  final PaneState pane;

  const _PaneEmptyState({required this.side, required this.pane});

  @override
  Widget build(BuildContext context) {
    final podium = side == ArenaSide.left ? 'left podium' : 'right podium';
    final hint = !pane.online
        ? 'tap the source name to connect an engine'
        : pane.model == null
            ? 'no model here yet — install one from the sidebar'
            : 'speaking with  ${pane.model}';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('☙', style: Sym.display(size: 24, color: Sym.amberDim)),
          const SizedBox(height: 10),
          Text(podium, style: Sym.display(size: 19, weight: FontWeight.w400)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: Sym.mono(size: 10.5, color: Sym.inkDim, spacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact cousin of chat_view's message block — same left-rail accent
/// language, slightly smaller type because panes are half width.
class _PaneMessage extends StatelessWidget {
  final ChatMessage msg;
  final bool streaming;

  const _PaneMessage({required this.msg, required this.streaming});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == Role.user;
    final accent = isUser ? Sym.amber : Sym.teal;

    return Container(
      margin: const EdgeInsets.only(bottom: 16, left: 10, right: 10),
      padding: const EdgeInsets.only(left: 11),
      decoration: BoxDecoration(
        border: Border(
            left: BorderSide(color: accent.withValues(alpha: 0.55), width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isUser ? 'YOU' : (msg.modelName ?? 'MODEL').toUpperCase(),
            style: Sym.label(color: accent.withValues(alpha: 0.8), size: 8.5),
          ),
          const SizedBox(height: 5),
          if (msg.content.isEmpty && streaming)
            const StreamingCursor()
          else
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: msg.content),
                  if (streaming) const WidgetSpan(child: StreamingCursor()),
                ],
              ),
              style: Sym.body(size: 13.5),
            ),
        ],
      ),
    );
  }
}

/// Per-pane composer for independent mode — a slimmer chat_view composer.
class _PaneComposer extends StatelessWidget {
  final TextEditingController input;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final bool streaming;
  final bool enabled;

  const _PaneComposer({
    required this.input,
    required this.onSend,
    required this.onStop,
    required this.streaming,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: Sym.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Sym.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
              child: TextField(
                controller: input,
                enabled: enabled && !streaming,
                minLines: 1,
                maxLines: 5,
                style: Sym.body(size: 13.5),
                onSubmitted: (_) => onSend(),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: enabled ? 'speak…' : 'no model',
                  hintStyle: Sym.body(size: 13.5, color: Sym.inkFaint),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: streaming
                ? IconButton(
                    onPressed: onStop,
                    tooltip: 'Stop generation',
                    iconSize: 20,
                    icon: const Icon(Icons.stop_circle_outlined,
                        color: Sym.danger),
                  )
                : IconButton(
                    onPressed: enabled ? onSend : null,
                    tooltip: 'Send',
                    iconSize: 20,
                    icon: Icon(Icons.arrow_upward,
                        color: enabled ? Sym.amber : Sym.inkFaint),
                  ),
          ),
        ],
      ),
    );
  }
}
