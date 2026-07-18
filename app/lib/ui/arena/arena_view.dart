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
        ? Row(children: const [
            Expanded(child: ArenaPane(side: ArenaSide.left, ownComposer: true)),
            VerticalDivider(width: 1, color: Sym.hairline),
            Expanded(child: ArenaPane(side: ArenaSide.right, ownComposer: true)),
          ])
        : Column(children: const [
            Expanded(child: ArenaPane(side: ArenaSide.left, ownComposer: true)),
            Divider(height: 1, color: Sym.hairline),
            Expanded(child: ArenaPane(side: ArenaSide.right, ownComposer: true)),
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

  const _ArenaToolbar({required this.arena, required this.tally, required this.pairing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duel = arena.mode == ArenaMode.duel;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
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
            icon: const Icon(Icons.restart_alt, size: 16, color: Sym.inkDim),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: active ? Sym.surfaceRaised : Colors.transparent,
            border: Border.all(color: active ? Sym.amberDim : Sym.hairline),
          ),
          child: Text(label,
              style: Sym.label(
                  color: active ? Sym.amber : Sym.inkDim, size: 8.5)),
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

class _VoteButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _VoteButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 180),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Text(
            label,
            style: Sym.mono(size: 10, color: color, weight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
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
                    icon: const Icon(Icons.stop_circle_outlined,
                        color: Sym.danger),
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
