/// The test-chat half of the studio: a real conversation with the persona
/// under its *applied* instructions, each answer stamped with the revision
/// that produced it. APPLY & RE-ASK is the loop this whole tab exists for —
/// commit the draft, repeat the last question, compare r3 with r4 in place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat.dart';
import '../../models/persona.dart';
import '../../models/source.dart';
import '../../state/persona_state.dart';
import '../../state/sources_contract.dart';
import '../../theme.dart';
import '../message_markdown.dart';
import '../widgets.dart';
import 'persona_common.dart';

class TestChatPane extends ConsumerStatefulWidget {
  final Persona persona;
  const TestChatPane({super.key, required this.persona});

  @override
  ConsumerState<TestChatPane> createState() => _TestChatPaneState();
}

class _TestChatPaneState extends ConsumerState<TestChatPane> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(studioProvider.notifier).send(text);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studio = ref.watch(studioProvider);
    final controller = ref.read(studioProvider.notifier);
    final sources = ref.watch(savedSourcesProvider);
    final persona = widget.persona;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && studio.isStreaming) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });

    return Column(
      children: [
        _TestChatHeader(
          studio: studio,
          sources: sources,
          onSource: controller.setSource,
          onModel: controller.selectModel,
          onRefresh: controller.refresh,
          onClear: controller.clearConversation,
        ),
        Expanded(
          child: studio.messages.isEmpty
              ? _TestEmptyState(persona: persona, ready: studio.ready)
              : SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 6),
                    itemCount: studio.messages.length,
                    itemBuilder: (_, i) => _StampedBlock(
                      stamped: studio.messages[i],
                      currentRevision: persona.instructionsRevision,
                      streaming:
                          studio.isStreaming && i == studio.messages.length - 1,
                    ),
                  ),
                ),
        ),
        if (studio.error != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Sym.danger),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 13, color: Sym.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(studio.error!,
                      style: Sym.mono(size: 10.5, color: Sym.danger), maxLines: 3),
                ),
              ],
            ),
          ),
        // The loop button rides above the composer: always the same spot,
        // label says exactly what it will do.
        if (studio.lastQuestion != null)
          Container(
            constraints: const BoxConstraints(maxWidth: 780),
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
            decoration: BoxDecoration(
              color: Sym.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Sym.hairline),
            ),
            child: Row(
              children: [
                Icon(Icons.replay, size: 13, color: Sym.inkFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '“${studio.lastQuestion}”',
                    style: Sym.mono(size: 9.5, color: Sym.inkDim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StudioButton(
                  label: studio.draftDirty ? 'APPLY & RE-ASK' : 'RE-ASK',
                  color: Sym.amber,
                  filled: studio.draftDirty,
                  onTap: studio.ready ? controller.applyAndReAsk : null,
                ),
              ],
            ),
          ),
        _TestComposer(
          input: _input,
          persona: persona,
          onSend: _send,
          streaming: studio.isStreaming,
          onStop: controller.stop,
          enabled: studio.ready,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header: where the persona is speaking from
// ---------------------------------------------------------------------------

class _TestChatHeader extends StatelessWidget {
  final StudioState studio;
  final List<ModelSource> sources;
  final ValueChanged<String> onSource;
  final ValueChanged<String> onModel;
  final VoidCallback onRefresh;
  final VoidCallback onClear;

  const _TestChatHeader({
    required this.studio,
    required this.sources,
    required this.onSource,
    required this.onModel,
    required this.onRefresh,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final source = sources
        .where((s) => s.id == studio.sourceId)
        .cast<ModelSource?>()
        .firstOrNull;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Sym.surface.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(color: Sym.hairline)),
      ),
      child: Row(
        children: [
          StatusDot(online: studio.online),
          const SizedBox(width: 10),
          // Source picker — every saved source (local, peers, clouds) is a
          // candidate stage for the persona.
          PopupMenuButton<String>(
            tooltip: 'test source',
            color: Sym.surfaceRaised,
            onSelected: onSource,
            itemBuilder: (_) => [
              for (final s in sources)
                PopupMenuItem(
                  value: s.id,
                  child: Text(s.label, style: Sym.mono(size: 11.5, color: Sym.ink)),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(source?.label ?? studio.sourceId,
                    style: Sym.mono(size: 10.5, color: Sym.inkDim)),
                Icon(Icons.arrow_drop_down, size: 15, color: Sym.inkFaint),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Model picker for the chosen source.
          if (studio.models.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'model',
              color: Sym.surfaceRaised,
              onSelected: onModel,
              itemBuilder: (_) => [
                for (final m in studio.models)
                  PopupMenuItem(
                    value: m.name,
                    child:
                        Text(m.name, style: Sym.mono(size: 11.5, color: Sym.ink)),
                  ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Sym.teal.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Sym.tealDim.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        studio.model ?? '—',
                        style: Sym.mono(
                            size: 10.5,
                            color: Sym.teal,
                            weight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, size: 14, color: Sym.tealDim),
                  ],
                ),
              ),
            )
          else if (studio.checking)
            Text('checking…', style: Sym.mono(size: 10, color: Sym.inkFaint))
          else
            Text('offline', style: Sym.mono(size: 10, color: Sym.inkFaint)),
          const Spacer(),
          if (studio.tokPerSec > 0)
            Text(
              '${studio.tokPerSec.toStringAsFixed(1)} tok/s',
              style: Sym.mono(
                  size: 10, color: studio.isStreaming ? Sym.teal : Sym.inkDim),
            ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Re-check source',
            onPressed: onRefresh,
            icon: Icon(Icons.refresh, size: 15, color: Sym.inkDim),
          ),
          IconButton(
            tooltip: 'Clear test conversation',
            onPressed: onClear,
            icon: Icon(Icons.restart_alt, size: 15, color: Sym.inkDim),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

class _StampedBlock extends StatelessWidget {
  final StampedMessage stamped;
  final int currentRevision;
  final bool streaming;

  const _StampedBlock({
    required this.stamped,
    required this.currentRevision,
    required this.streaming,
  });

  @override
  Widget build(BuildContext context) {
    final msg = stamped.msg;
    final isUser = msg.role == Role.user;
    final accent = isUser ? Sym.amber : Sym.teal;

    return Container(
      constraints: const BoxConstraints(maxWidth: 780),
      margin: const EdgeInsets.only(bottom: 18, left: 12, right: 12),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border:
            Border(left: BorderSide(color: accent.withValues(alpha: 0.55), width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isUser ? 'YOU' : (msg.modelName ?? 'MODEL').toUpperCase(),
                style: Sym.label(color: accent.withValues(alpha: 0.8), size: 9),
              ),
              // The whole studio in one chip: which wording produced this.
              if (!isUser && stamped.revision != null) ...[
                const SizedBox(width: 8),
                RevisionChip(
                  revision: stamped.revision!,
                  current: stamped.revision == currentRevision,
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          if (msg.content.isEmpty && streaming)
            const StreamingCursor()
          else if (isUser)
            Text(msg.content, style: Sym.body(size: 14.5))
          else ...[
            MessageMarkdown(text: msg.content),
            if (streaming)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: StreamingCursor(),
              ),
          ],
        ],
      ),
    );
  }
}

class _TestEmptyState extends StatelessWidget {
  final Persona persona;
  final bool ready;
  const _TestEmptyState({required this.persona, required this.ready});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PersonaSigil(
                glyph: persona.glyph,
                accent: personaAccent(persona.accentIndex),
                size: 46),
            const SizedBox(height: 12),
            Text('Audition ${persona.name}.',
                style: Sym.display(size: 22, weight: FontWeight.w400)),
            const SizedBox(height: 8),
            Text(
              ready
                  ? 'ask something — then edit the instructions and RE-ASK it'
                  : 'pick an online source and model above to begin',
              style: Sym.mono(size: 10.5, color: Sym.inkDim, spacing: 0.5),
            ),
          ],
        ),
      );
}

class _TestComposer extends StatelessWidget {
  final TextEditingController input;
  final Persona persona;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final bool streaming;
  final bool enabled;

  const _TestComposer({
    required this.input,
    required this.persona,
    required this.onSend,
    required this.onStop,
    required this.streaming,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        constraints: const BoxConstraints(maxWidth: 780),
        decoration: BoxDecoration(
          color: Sym.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Sym.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 0, 12),
              child: PersonaSigil(
                  glyph: persona.glyph,
                  accent: personaAccent(persona.accentIndex),
                  size: 22),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
                child: TextField(
                  controller: input,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 6,
                  style: Sym.body(size: 14.5),
                  onSubmitted: (_) => onSend(),
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: enabled
                        ? 'test ${persona.name}…'
                        : 'no model available',
                    hintStyle: Sym.body(size: 14.5, color: Sym.inkFaint),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(5),
              child: streaming
                  ? IconButton(
                      onPressed: onStop,
                      tooltip: 'Stop generation',
                      icon: Icon(Icons.stop_circle_outlined,
                          size: 20, color: Sym.danger),
                    )
                  : IconButton(
                      onPressed: enabled ? onSend : null,
                      tooltip: 'Send',
                      icon: Icon(Icons.arrow_upward,
                          size: 20, color: enabled ? Sym.amber : Sym.inkFaint),
                    ),
            ),
          ],
        ),
      );
}
