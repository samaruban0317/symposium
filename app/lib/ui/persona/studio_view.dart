/// The persona studio: roster on the left, the editor and a live test chat
/// side by side. The whole point of the layout is that instructions and their
/// consequences are visible at once — edit on the left, APPLY & RE-ASK, and
/// the new answer lands next to the old one stamped with its revision.
///
/// Under 720px the editor and test chat won't both fit legibly, so the studio
/// gets its own EDIT | TEST sub-tabs instead of cramming two panes onto a
/// phone. The roster collapses to a horizontal sigil strip.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/persona.dart';
import '../../state/persona_state.dart';
import '../../theme.dart';
import 'persona_common.dart';
import 'persona_editor.dart';
import 'test_chat.dart';

class StudioView extends ConsumerStatefulWidget {
  const StudioView({super.key});

  @override
  ConsumerState<StudioView> createState() => _StudioViewState();
}

enum _NarrowPane { edit, test }

class _StudioViewState extends ConsumerState<StudioView> {
  _NarrowPane _narrowPane = _NarrowPane.edit;

  @override
  Widget build(BuildContext context) {
    final personas = ref.watch(personasProvider);
    final selectedId = ref.watch(studioPersonaIdProvider);
    final selected =
        personas.where((p) => p.id == selectedId).cast<Persona?>().firstOrNull;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    // A dangling selection (deleted persona) or none at all: auto-open the
    // first persona so the studio never shows a stale editor.
    if (selected == null && personas.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final cur = ref.read(studioPersonaIdProvider);
        if (ref.read(personasProvider.notifier).byId(cur) == null) {
          ref.read(studioPersonaIdProvider.notifier).state = personas.first.id;
        }
      });
    }

    if (personas.isEmpty) return _EmptyStudio(onImported: _selectPersona);

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Roster(
            personas: personas,
            selectedId: selectedId,
            onSelect: _selectPersona,
            onImported: _selectPersona,
          ),
          if (selected != null) ...[
            Expanded(flex: 5, child: PersonaEditor(persona: selected)),
            const VerticalDivider(width: 1),
            Expanded(flex: 6, child: TestChatPane(persona: selected)),
          ] else
            const Expanded(child: SizedBox.shrink()),
        ],
      );
    }

    return Column(
      children: [
        _RosterStrip(
          personas: personas,
          selectedId: selectedId,
          onSelect: _selectPersona,
          onImported: _selectPersona,
        ),
        Container(
          height: 38,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Sym.hairline)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SubTab(
                label: 'EDIT',
                active: _narrowPane == _NarrowPane.edit,
                onTap: () => setState(() => _narrowPane = _NarrowPane.edit),
              ),
              const SizedBox(width: 4),
              _SubTab(
                label: 'TEST',
                active: _narrowPane == _NarrowPane.test,
                onTap: () => setState(() => _narrowPane = _NarrowPane.test),
              ),
            ],
          ),
        ),
        if (selected != null)
          Expanded(
            child: _narrowPane == _NarrowPane.edit
                ? PersonaEditor(persona: selected)
                : TestChatPane(persona: selected),
          ),
      ],
    );
  }

  void _selectPersona(String id) =>
      ref.read(studioPersonaIdProvider.notifier).state = id;
}

// ---------------------------------------------------------------------------
// Roster (wide): a narrow left rail of personas
// ---------------------------------------------------------------------------

class _Roster extends ConsumerWidget {
  final List<Persona> personas;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onImported;

  const _Roster({
    required this.personas,
    required this.selectedId,
    required this.onSelect,
    required this.onImported,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: Sym.surface.withValues(alpha: 0.4),
        border: Border(right: BorderSide(color: Sym.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(
              children: [
                Text('PERSONAS', style: Sym.label(color: Sym.amberDim)),
                const Spacer(),
                Text('${personas.length}',
                    style: Sym.mono(size: 10, color: Sym.inkFaint)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: personas.length,
              itemBuilder: (_, i) => _RosterTile(
                persona: personas[i],
                selected: personas[i].id == selectedId,
                onTap: () => onSelect(personas[i].id),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: StudioButton(
                    label: '+ NEW',
                    color: Sym.amber,
                    onTap: () =>
                        onSelect(ref.read(personasProvider.notifier).create().id),
                  ),
                ),
                const SizedBox(width: 8),
                StudioButton(
                  label: 'IMPORT',
                  onTap: () => showImportPersonaDialog(context, ref, onImported),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterTile extends StatefulWidget {
  final Persona persona;
  final bool selected;
  final VoidCallback onTap;

  const _RosterTile(
      {required this.persona, required this.selected, required this.onTap});

  @override
  State<_RosterTile> createState() => _RosterTileState();
}

class _RosterTileState extends State<_RosterTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final persona = widget.persona;
    final selected = widget.selected;
    final accent = personaAccent(persona.accentIndex);
    final preview = persona.instructions.trim().isEmpty
        ? 'no instructions yet'
        : persona.instructions.trim().split('\n').first;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Sym.surfaceRaised
                : (_hover ? Sym.surface : null),
            border: Border(
              left: BorderSide(
                  color: selected
                      ? accent
                      : (_hover
                          ? accent.withValues(alpha: 0.35)
                          : Colors.transparent),
                  width: 2),
            ),
          ),
          child: Row(
            children: [
              PersonaSigil(glyph: persona.glyph, accent: accent, size: 30),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(persona.name,
                        style: Sym.body(
                            size: 13.5,
                            color: selected ? Sym.ink : Sym.inkDim),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 1),
                    Text(preview,
                        style: Sym.mono(size: 9, color: Sym.inkFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Roster (narrow): a horizontal sigil strip
// ---------------------------------------------------------------------------

class _RosterStrip extends ConsumerWidget {
  final List<Persona> personas;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onImported;

  const _RosterStrip({
    required this.personas,
    required this.selectedId,
    required this.onSelect,
    required this.onImported,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Sym.hairline)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        children: [
          for (final p in personas)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                onTap: () => onSelect(p.id),
                borderRadius: BorderRadius.circular(20),
                child: Opacity(
                  opacity: p.id == selectedId ? 1 : 0.45,
                  child: PersonaSigil(
                      glyph: p.glyph, accent: personaAccent(p.accentIndex)),
                ),
              ),
            ),
          Center(
            child: StudioButton(
              label: '+',
              color: Sym.amber,
              onTap: () => onSelect(ref.read(personasProvider.notifier).create().id),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SubTab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: active ? Sym.amber : Colors.transparent, width: 2),
            ),
          ),
          child:
              Text(label, style: Sym.label(size: 9, color: active ? Sym.amber : Sym.inkDim)),
        ),
      );
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyStudio extends ConsumerWidget {
  final ValueChanged<String> onImported;
  const _EmptyStudio({required this.onImported});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('❖', style: Sym.display(size: 34, color: Sym.amberDim)),
            const SizedBox(height: 14),
            Text('Tune a mind of your own.',
                style: Sym.display(size: 28, weight: FontWeight.w400)),
            const SizedBox(height: 8),
            SizedBox(
              width: 380,
              child: Text(
                'a persona is instructions + settings, refined against a live '
                'model and shared as a small file',
                textAlign: TextAlign.center,
                style: Sym.mono(size: 10.5, color: Sym.inkDim, spacing: 0.5),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StudioButton(
                  label: 'CREATE PERSONA',
                  color: Sym.amber,
                  filled: true,
                  onTap: () {
                    final p = ref.read(personasProvider.notifier).create();
                    ref.read(studioPersonaIdProvider.notifier).state = p.id;
                  },
                ),
                const SizedBox(width: 10),
                StudioButton(
                  label: 'IMPORT',
                  onTap: () => showImportPersonaDialog(context, ref, onImported),
                ),
              ],
            ),
          ],
        ),
      );
}
