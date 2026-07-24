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
            const _ArenaSeam(),
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
            const _ArenaSeam(),
            Expanded(child: ArenaPane(side: ArenaSide.right, ownComposer: true)),
          ])
        : Column(children: [
            Expanded(child: ArenaPane(side: ArenaSide.left, ownComposer: true)),
            Divider(height: 1, color: Sym.hairline),
            Expanded(child: ArenaPane(side: ArenaSide.right, ownComposer: true)),
          ]);

    return Column(
      children: [
        _ArenaToolbar(arena: arena, tally: tally, pairing: pairing),
        Expanded(child: duel ? panes : panesIndependent),
        if (duel && arena.roundComplete && !arena.voted)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _VoteBar(
              leftModel: left.model ?? 'left',
              rightModel: right.model ?? 'right',
            ),
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

/// The seam where the two podiums meet — a hairline that warms to amber at the
/// left edge and cools to teal at the right, so the divider itself says "human
/// vs machine" without shouting.
class _ArenaSeam extends StatelessWidget {
  const _ArenaSeam();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Sym.amber.withValues(alpha: 0.28),
              Sym.hairline,
              Sym.hairline,
              Sym.teal.withValues(alpha: 0.28),
            ],
            stops: const [0.0, 0.22, 0.78, 1.0],
          ),
        ),
      );
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
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Sym.surface,
        border: Border(bottom: BorderSide(color: Sym.hairline)),
      ),
      child: Row(
        children: [
          // Segmented mode toggle — one hairline-bordered pill, two halves.
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              color: Sym.bg.withValues(alpha: 0.5),
              border: Border.all(color: Sym.hairline),
            ),
            child: Row(
              children: [
                _ModeChip(
                  label: 'DUEL',
                  active: duel,
                  onTap: () =>
                      ref.read(arenaProvider.notifier).setMode(ArenaMode.duel),
                ),
                _ModeChip(
                  label: 'INDEPENDENT',
                  active: !duel,
                  onTap: () => ref
                      .read(arenaProvider.notifier)
                      .setMode(ArenaMode.independent),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (duel && tally != null) ...[
            // The scoreboard: LEFT wins · ties · RIGHT wins for this pairing.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Sym.bg.withValues(alpha: 0.5),
                border: Border.all(color: Sym.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${tally!.left}',
                      style: Sym.mono(
                          size: 14, color: Sym.amber, weight: FontWeight.w700)),
                  Text('  ·  ',
                      style: Sym.mono(size: 11, color: Sym.inkFaint)),
                  Text('${tally!.ties}',
                      style: Sym.mono(size: 12, color: Sym.inkDim)),
                  Text('  ·  ',
                      style: Sym.mono(size: 11, color: Sym.inkFaint)),
                  Text('${tally!.right}',
                      style: Sym.mono(
                          size: 14, color: Sym.teal, weight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 12),
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

class _ModeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: active
                ? Sym.amber.withValues(alpha: 0.14)
                : Colors.transparent,
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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Sym.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sym.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
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
          const SizedBox(width: 8),
          _VoteButton(label: 'TIE', color: Sym.inkDim, onTap: () => vote(null)),
          const SizedBox(width: 8),
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

  const _VoteButton({required this.label, required this.color, required this.onTap});

  @override
  State<_VoteButton> createState() => _VoteButtonState();
}

class _VoteButtonState extends State<_VoteButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(maxWidth: 180),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: _hover
                  ? widget.color.withValues(alpha: 0.12)
                  : Colors.transparent,
              border: Border.all(
                  color:
                      widget.color.withValues(alpha: _hover ? 0.85 : 0.5)),
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
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      constraints: const BoxConstraints(maxWidth: 900),
      decoration: BoxDecoration(
        color: Sym.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sym.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 0, 8),
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
                    icon: Icon(Icons.stop_circle_outlined,
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
