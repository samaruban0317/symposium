import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/arena_state.dart';
import '../../theme.dart';
import 'arena_pane.dart';

/// Phase 3 — the split screen. Two panes, two endpoints, two models.
/// Duel mode races one prompt on both; independent mode is two chats.
class ArenaView extends ConsumerStatefulWidget {
  const ArenaView({super.key});

  @override
  ConsumerState<ArenaView> createState() => _ArenaViewState();
}

class _ArenaViewState extends ConsumerState<ArenaView> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _sendDuel() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(arenaProvider.notifier).sendDuel(text);
  }

  @override
  Widget build(BuildContext context) {
    final arena = ref.watch(arenaProvider);
    final left = ref.watch(paneProvider(ArenaSide.left));
    final right = ref.watch(paneProvider(ArenaSide.right));
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final duel = arena.mode == ArenaMode.duel;

    // Scoreboard shows the tally for whatever pairing is on stage right now.
    final pairing = (left.model != null && right.model != null)
        ? '${left.model} ⇄ ${right.model}'
        : null;
    final tally = pairing == null ? null : arena.scores[pairing];

    final anyStreaming = left.isStreaming || right.isStreaming;
    final bothReady = left.ready && right.ready;

    // On phones the panes stack vertically — comparing answers by scrolling
    // beats squeezing two columns of prose into a 400px screen.
    final panes = wide
        ? Row(children: [
            const Expanded(
                child: ArenaPane(side: ArenaSide.left, ownComposer: false)),
            Container(width: 1, color: Sym.hairline),
            const Expanded(
                child: ArenaPane(side: ArenaSide.right, ownComposer: false)),
          ])
        : Column(children: [
            const Expanded(
                child: ArenaPane(side: ArenaSide.left, ownComposer: false)),
            Container(height: 1, color: Sym.hairline),
            const Expanded(
                child: ArenaPane(side: ArenaSide.right, ownComposer: false)),
          ]);

    final panesIndependent = wide
        ? Row(children: [
            Expanded(child: ArenaPane(side: ArenaSide.left, ownComposer: true)),
            VerticalDivider(width: 1, color: Sym.hairline),
            Expanded(
                child: ArenaPane(side: ArenaSide.right, ownComposer: true)),
          ])
        : Column(children: [
            Expanded(child: ArenaPane(side: ArenaSide.left, ownComposer: true)),
            Divider(height: 1, color: Sym.hairline),
            Expanded(
                child: ArenaPane(side: ArenaSide.right, ownComposer: true)),
          ]);

    return Column(
      children: [
        _ArenaToolbar(arena: arena, tally: tally, pairing: pairing),
        Expanded(child: duel ? panes : panesIndependent),
        if (duel && arena.roundComplete && !arena.voted)
          _VoteBar(
            leftModel: left.model ?? 'left',
            rightModel: right.model ?? 'right',
          ),
        if (duel)
          _DuelComposer(
            input: _input,
            onSend: _sendDuel,
            streaming: anyStreaming,
            onStop: () => ref.read(arenaProvider.notifier).stopBoth(),
            enabled: bothReady,
          ),
      ],
    );
  }
}

class _ArenaToolbar extends ConsumerWidget {
  final ArenaState arena;
  final Tally? tally;
  final String? pairing;

  const _ArenaToolbar(
      {required this.arena, required this.tally, required this.pairing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duel = arena.mode == ArenaMode.duel;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Sym.hairline)),
      ),
      child: Row(
        children: [
          _ModeChip(
            label: 'DUEL',
            active: duel,
            onTap: () =>
                ref.read(arenaProvider.notifier).setMode(ArenaMode.duel),
          ),
          const SizedBox(width: 6),
          _ModeChip(
            label: 'INDEPENDENT',
            active: !duel,
            onTap: () =>
                ref.read(arenaProvider.notifier).setMode(ArenaMode.independent),
          ),
          const Spacer(),
          if (duel && tally != null) ...[
            // The scoreboard: LEFT wins · ties · RIGHT wins for this pairing.
            Text('${tally!.left}',
                style: Sym.mono(
                    size: 14, color: Sym.amber, weight: FontWeight.w600)),
            Text('  ·  ', style: Sym.mono(size: 11, color: Sym.inkFaint)),
            Text('${tally!.ties}',
                style: Sym.mono(size: 12, color: Sym.inkDim)),
            Text('  ·  ', style: Sym.mono(size: 11, color: Sym.inkFaint)),
            Text('${tally!.right}',
                style: Sym.mono(
                    size: 14, color: Sym.teal, weight: FontWeight.w600)),
            const SizedBox(width: 14),
          ],
          IconButton(
            tooltip: 'Clear both conversations',
            onPressed: () => ref.read(arenaProvider.notifier).clearAll(),
            icon: Icon(Icons.restart_alt, size: 16, color: Sym.inkDim),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeChip(
      {required this.label, required this.active, required this.onTap});

  @override
  State<_ModeChip> createState() => _ModeChipState();
}

class _ModeChipState extends State<_ModeChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Sym.fast,
            curve: Sym.ease,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: widget.active
                  ? Sym.surfaceRaised
                  : (_hover
                      ? Sym.surfaceRaised.withValues(alpha: 0.5)
                      : Colors.transparent),
              border: Border.all(
                  color: widget.active
                      ? Sym.amberDim
                      : (_hover ? Sym.inkFaint : Sym.hairline)),
            ),
            child: Text(widget.label,
                style: Sym.label(
                    color: widget.active
                        ? Sym.amber
                        : (_hover ? Sym.ink : Sym.inkDim),
                    size: 8.5)),
          ),
        ),
      );
}

/// After both speakers finish, the audience votes.
class _VoteBar extends ConsumerWidget {
  final String leftModel;
  final String rightModel;

  const _VoteBar({required this.leftModel, required this.rightModel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vote = ref.read(arenaProvider.notifier).vote;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Sym.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Sym.hairline),
      ),
      child: Row(
        children: [
          Text('WHO SPOKE BETTER?', style: Sym.label(size: 8.5)),
          const Spacer(),
          _VoteButton(
            label: '◀ $leftModel',
            color: Sym.amber,
            onTap: () => vote(ArenaSide.left),
          ),
          const SizedBox(width: 6),
          _VoteButton(label: 'TIE', color: Sym.inkDim, onTap: () => vote(null)),
          const SizedBox(width: 6),
          _VoteButton(
            label: '$rightModel ▶',
            color: Sym.teal,
            onTap: () => vote(ArenaSide.right),
          ),
        ],
      ),
    );
  }
}

class _VoteButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _VoteButton(
      {required this.label, required this.color, required this.onTap});

  @override
  State<_VoteButton> createState() => _VoteButtonState();
}

class _VoteButtonState extends State<_VoteButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Sym.fast,
            curve: Sym.ease,
            constraints: const BoxConstraints(maxWidth: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: _hover
                  ? widget.color.withValues(alpha: 0.12)
                  : Colors.transparent,
              border: Border.all(
                  color: widget.color.withValues(alpha: _hover ? 0.9 : 0.55)),
            ),
            child: Text(
              widget.label,
              style: Sym.mono(
                  size: 10, color: widget.color, weight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
}

/// The shared duel composer — one prompt, two speakers.
class _DuelComposer extends StatelessWidget {
  final TextEditingController input;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final bool streaming;
  final bool enabled;

  const _DuelComposer({
    required this.input,
    required this.onSend,
    required this.onStop,
    required this.streaming,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      constraints: const BoxConstraints(maxWidth: 900),
      decoration: BoxDecoration(
        color: Sym.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sym.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 0, 6),
              child: TextField(
                controller: input,
                enabled: enabled && !streaming,
                minLines: 1,
                maxLines: 6,
                style: Sym.body(size: 14.5),
                onSubmitted: (_) => onSend(),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: enabled
                      ? 'Put one question to both speakers…'
                      : 'both podiums need an online engine and a model',
                  hintStyle: Sym.body(size: 14.5, color: Sym.inkFaint),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: streaming
                ? IconButton(
                    onPressed: onStop,
                    tooltip: 'Stop both',
                    icon: Icon(Icons.stop_circle_outlined, color: Sym.danger),
                  )
                : IconButton(
                    onPressed: enabled ? onSend : null,
                    tooltip: 'Send to both',
                    icon: Icon(Icons.arrow_upward,
                        color: enabled ? Sym.amber : Sym.inkFaint),
                  ),
          ),
        ],
      ),
    );
  }
}
