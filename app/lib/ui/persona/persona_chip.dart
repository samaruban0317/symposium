/// The persona picker that lives in the MAIN chat's composer. Selecting a
/// persona copies its instructions + sampling knobs into [chatParamsProvider]
/// — the same provider the parameter lab edits — so the lab's chips light up
/// with the persona's values and every downstream send just works.
///
/// Because it's a copy, later tweaks in the lab don't silently detach the
/// persona: we compare live params against the persona and mark the sigil
/// with an amber dot when they've diverged ("this is r4, plus your edits").
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat.dart';
import '../../models/persona.dart';
import '../../state/app_state.dart';
import '../../state/arena_state.dart';
import '../../state/persona_state.dart';
import '../../theme.dart';
import 'persona_common.dart';

const _kNone = '__none__';
const _kStudio = '__studio__';

class PersonaChipButton extends ConsumerWidget {
  const PersonaChipButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personasProvider);
    final activeId = ref.watch(activeChatPersonaProvider);
    final params = ref.watch(chatParamsProvider);
    final active =
        personas.where((p) => p.id == activeId).cast<Persona?>().firstOrNull;

    final diverged = active != null && !_matches(active, params);

    return PopupMenuButton<String>(
      tooltip: active == null ? 'Speak as a persona' : 'Persona: ${active.name}',
      color: Sym.surfaceRaised,
      onSelected: (value) => _select(ref, value),
      itemBuilder: (_) => [
        for (final p in personas)
          PopupMenuItem(
            value: p.id,
            child: Row(
              children: [
                PersonaSigil(
                    glyph: p.glyph, accent: personaAccent(p.accentIndex), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(p.name,
                      style: Sym.mono(size: 11.5, color: Sym.ink),
                      overflow: TextOverflow.ellipsis),
                ),
                if (p.id == activeId)
                  const Icon(Icons.check, size: 13, color: Sym.amber),
              ],
            ),
          ),
        if (personas.isNotEmpty)
          PopupMenuItem(
            value: _kNone,
            child: Text('none — plain defaults',
                style: Sym.mono(size: 11, color: Sym.inkDim)),
          ),
        PopupMenuItem(
          value: _kStudio,
          child: Text(
              personas.isEmpty ? 'create one in the studio →' : 'open studio →',
              style: Sym.mono(size: 11, color: Sym.tealDim)),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 13),
        child: active == null
            ? Icon(Icons.theater_comedy_outlined, size: 18, color: Sym.inkDim)
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  PersonaSigil(
                    glyph: active.glyph,
                    accent: personaAccent(active.accentIndex),
                    size: 24,
                  ),
                  // Diverged marker: the persona is on, but the lab has been
                  // twiddled past it.
                  if (diverged)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Sym.amber),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  void _select(WidgetRef ref, String value) {
    switch (value) {
      case _kStudio:
        ref.read(homeTabProvider.notifier).state = HomeTab.studio;
      case _kNone:
        ref.read(activeChatPersonaProvider.notifier).state = null;
        ref.read(chatParamsProvider.notifier).state = const ChatParams();
      default:
        final p = ref.read(personasProvider.notifier).byId(value);
        if (p == null) return;
        ref.read(activeChatPersonaProvider.notifier).state = p.id;
        ref.read(chatParamsProvider.notifier).state = ChatParams(
          temperature: p.temperature,
          topP: p.topP,
          maxTokens: p.maxTokens,
          systemPrompt: p.instructions,
        );
    }
  }

  bool _matches(Persona p, ChatParams params) =>
      params.temperature == p.temperature &&
      params.topP == p.topP &&
      params.maxTokens == p.maxTokens &&
      params.systemPrompt.trim() == p.instructions.trim();
}
