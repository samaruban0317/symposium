/// The editor half of the studio: identity (name/glyph/accent), the
/// instructions draft, sampling knobs, and the persona's lifecycle buttons
/// (apply, export, import, duplicate, delete, pin).
///
/// Identity and knobs commit straight onto the persona — they don't affect
/// the revision counter. Instructions go through the studio's DRAFT so that
/// `rN` stamps mean "applied wording N", not "keystroke N".
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/persona.dart';
import '../../state/local_store.dart';
import '../../state/persona_state.dart';
import '../../theme.dart';
import 'persona_common.dart';

class PersonaEditor extends ConsumerWidget {
  final Persona persona;
  const PersonaEditor({super.key, required this.persona});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioProvider);
    final controller = ref.read(studioProvider.notifier);
    final roster = ref.read(personasProvider.notifier);
    final accent = personaAccent(persona.accentIndex);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        // -- identity --------------------------------------------------------
        Row(
          children: [
            PersonaSigil(glyph: persona.glyph, accent: accent, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: _IdentityField(
                key: ValueKey('name-${persona.id}'),
                initial: persona.name,
                hint: 'persona name',
                style: Sym.display(size: 20, weight: FontWeight.w500),
                onCommit: (v) =>
                    roster.upsert(persona.copyWith(name: v.trim().isEmpty ? 'Unnamed' : v.trim())),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 44,
              child: _IdentityField(
                key: ValueKey('glyph-${persona.id}'),
                initial: persona.glyph,
                hint: '✶',
                maxLength: 2, // many emoji are two UTF-16 units
                textAlign: TextAlign.center,
                style: Sym.display(size: 18, color: accent),
                onCommit: (v) =>
                    roster.upsert(persona.copyWith(glyph: v.isEmpty ? '✶' : v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('ACCENT', style: Sym.label(size: 9)),
            const SizedBox(width: 12),
            for (var i = 0; i < personaAccents.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => roster.upsert(persona.copyWith(accentIndex: i)),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: personaAccents[i].withValues(alpha: 0.85),
                      border: Border.all(
                        color: i == persona.accentIndex ? Sym.ink : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 18),
        const Divider(height: 1),
        const SizedBox(height: 14),

        // -- instructions ----------------------------------------------------
        Row(
          children: [
            Text('INSTRUCTIONS', style: Sym.label(color: Sym.amberDim)),
            const SizedBox(width: 8),
            RevisionChip(revision: persona.instructionsRevision, current: true),
            if (studio.draftDirty) ...[
              const SizedBox(width: 8),
              Text('unapplied edits',
                  style: Sym.mono(size: 9, color: Sym.amber, spacing: 0.5)),
            ],
            const Spacer(),
            StudioButton(
              label: 'APPLY → r${persona.instructionsRevision + (studio.draftDirty ? 1 : 0)}',
              color: Sym.amber,
              filled: studio.draftDirty,
              onTap: studio.draftDirty ? controller.applyDraft : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _InstructionsField(
          key: ValueKey('instr-${persona.id}'),
          initial: studio.draft,
          onChanged: controller.editDraft,
        ),

        const SizedBox(height: 18),
        const Divider(height: 1),
        const SizedBox(height: 14),

        // -- knobs -----------------------------------------------------------
        Text('SAMPLING', style: Sym.label(color: Sym.amberDim)),
        const SizedBox(height: 8),
        _PersonaSlider(
          label: 'TEMPERATURE',
          value: persona.temperature,
          min: 0,
          max: 2,
          onChanged: (v) => roster.upsert(persona.copyWith(temperature: v)),
        ),
        _PersonaSlider(
          label: 'TOP-P',
          value: persona.topP,
          min: 0.05,
          max: 1,
          onChanged: (v) => roster.upsert(persona.copyWith(topP: v)),
        ),
        Row(
          children: [
            SizedBox(width: 110, child: Text('MAX TOKENS', style: Sym.label(size: 9))),
            SizedBox(
              width: 80,
              child: _MaxTokensField(
                key: ValueKey('maxtok-${persona.id}'),
                value: persona.maxTokens,
                onChanged: (v) => roster.upsert(v == null
                    ? persona.copyWith(maxTokens: null)
                    : persona.copyWith(maxTokens: v)),
              ),
            ),
            const SizedBox(width: 10),
            Text(persona.maxTokens == null ? 'unbounded' : 'reply cap',
                style: Sym.mono(size: 10, color: Sym.inkFaint)),
          ],
        ),

        const SizedBox(height: 18),
        const Divider(height: 1),
        const SizedBox(height: 14),

        // -- lifecycle -------------------------------------------------------
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StudioButton(
              label: 'EXPORT',
              color: Sym.teal,
              onTap: () => _export(context, persona),
            ),
            StudioButton(
              label: 'DUPLICATE',
              onTap: () {
                final copy = roster.duplicate(persona);
                ref.read(studioPersonaIdProvider.notifier).state = copy.id;
              },
            ),
            StudioButton(
              label: 'DELETE',
              color: Sym.danger,
              onTap: () => _confirmDelete(context, ref),
            ),
          ],
        ),

        const SizedBox(height: 14),
        // Pinning: remember where this persona likes to run, so opening it in
        // the studio (or importing it elsewhere) lands on the right model.
        Row(
          children: [
            Icon(Icons.push_pin_outlined,
                size: 13,
                color: persona.pinnedModel != null ? Sym.teal : Sym.inkFaint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                persona.pinnedModel != null
                    ? 'pinned to  ${persona.pinnedModel}'
                        '${persona.pinnedSourceId != null ? '  on ${persona.pinnedSourceId}' : ''}'
                    : 'not pinned — test chat uses whatever is selected',
                style: Sym.mono(size: 9.5, color: Sym.inkFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            StudioButton(
              label: persona.pinnedModel != null ? 'UNPIN' : 'PIN CURRENT',
              onTap: persona.pinnedModel != null
                  ? controller.unpin
                  : (studio.model != null ? controller.pinCurrent : null),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, Persona p) async {
    final json = const JsonEncoder.withIndent('  ').convert(p.toExport());
    await Clipboard.setData(ClipboardData(text: json));
    // Also drop a file next to the app's other data so the persona can be
    // sent to a friend as an attachment, not just pasted.
    String where = 'clipboard';
    try {
      final safe = p.name.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
      final f = await dataFile(
          'persona-${safe.isEmpty ? p.id : safe.replaceAll(' ', '-')}.json');
      await f.writeAsString(json, flush: true);
      where = f.path;
    } catch (_) {
      // Clipboard alone is still a successful export.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Sym.surfaceRaised,
        content: Text('copied to clipboard · saved to $where',
            style: Sym.mono(size: 10.5, color: Sym.ink)),
      ));
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sym.surface,
        title: Text('Delete ${persona.name}?', style: Sym.display(size: 17)),
        content: Text('its instructions and tuning are gone for good',
            style: Sym.mono(size: 11, color: Sym.inkDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('keep', style: Sym.mono(size: 12, color: Sym.inkDim)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(personasProvider.notifier).delete(persona.id);
              ref.read(studioPersonaIdProvider.notifier).state = null;
            },
            child: Text('delete', style: Sym.mono(size: 12, color: Sym.danger)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Import dialog — shared with the roster and the empty state
// ---------------------------------------------------------------------------

/// Paste-JSON import. Clipboard-based on purpose: it needs no file-picker
/// plugin and matches how the export lands (as text a friend sent you).
Future<void> showImportPersonaDialog(
    BuildContext context, WidgetRef ref, ValueChanged<String> onImported) {
  final input = TextEditingController();
  String? error;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: Sym.surface,
        title: Text('Import persona', style: Sym.display(size: 17)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: input,
                minLines: 5,
                maxLines: 10,
                autofocus: true,
                style: Sym.mono(size: 10.5, color: Sym.ink),
                decoration: InputDecoration(
                  hintText: '{ "type": "symposium_persona", … }',
                  hintStyle: Sym.mono(size: 10.5, color: Sym.inkFaint),
                  contentPadding: const EdgeInsets.all(10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Sym.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Sym.amberDim),
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: Sym.mono(size: 10, color: Sym.danger)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('cancel', style: Sym.mono(size: 12, color: Sym.inkDim)),
          ),
          TextButton(
            onPressed: () {
              try {
                final decoded = jsonDecode(input.text);
                if (decoded is! Map<String, dynamic>) {
                  throw const FormatException('that is not a JSON object');
                }
                final p = Persona.fromExport(decoded);
                final added = ref.read(personasProvider.notifier).import(p);
                Navigator.of(ctx).pop();
                onImported(added.id);
              } on FormatException catch (e) {
                setState(() => error = e.message);
              } catch (_) {
                setState(() => error = 'could not parse that as JSON');
              }
            },
            child: Text('import', style: Sym.mono(size: 12, color: Sym.amber)),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------

/// One-line field that commits on every change but re-seeds only when the
/// persona underneath changes (via the ValueKey on the widget) — so external
/// updates can't fight the caret.
class _IdentityField extends StatefulWidget {
  final String initial;
  final String hint;
  final TextStyle style;
  final int? maxLength;
  final TextAlign textAlign;
  final ValueChanged<String> onCommit;

  const _IdentityField({
    super.key,
    required this.initial,
    required this.hint,
    required this.style,
    required this.onCommit,
    this.maxLength,
    this.textAlign = TextAlign.start,
  });

  @override
  State<_IdentityField> createState() => _IdentityFieldState();
}

class _IdentityFieldState extends State<_IdentityField> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        style: widget.style,
        maxLength: widget.maxLength,
        textAlign: widget.textAlign,
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          hintText: widget.hint,
          hintStyle: widget.style.copyWith(color: Sym.inkFaint),
          border: InputBorder.none,
        ),
        onChanged: widget.onCommit,
      );
}

class _InstructionsField extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onChanged;
  const _InstructionsField({super.key, required this.initial, required this.onChanged});

  @override
  State<_InstructionsField> createState() => _InstructionsFieldState();
}

class _InstructionsFieldState extends State<_InstructionsField> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        minLines: 6,
        maxLines: 14,
        style: Sym.body(size: 14),
        decoration: InputDecoration(
          hintText:
              'Who is this persona? Voice, expertise, rules, format — the whole steering wheel.',
          hintStyle: Sym.body(size: 14, color: Sym.inkFaint),
          contentPadding: const EdgeInsets.all(12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Sym.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Sym.amberDim),
          ),
        ),
        onChanged: widget.onChanged,
      );
}

class _PersonaSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _PersonaSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: Sym.label(size: 9))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: Sym.amber,
                inactiveTrackColor: Sym.hairline,
                thumbColor: Sym.amber,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                overlayColor: const Color(0x22E0A458),
                trackShape: const RectangularSliderTrackShape(),
              ),
              child: Slider(
                  value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(
              value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: Sym.mono(size: 12, color: Sym.amber, weight: FontWeight.w600),
            ),
          ),
        ],
      );
}

class _MaxTokensField extends StatefulWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  const _MaxTokensField({super.key, required this.value, required this.onChanged});

  @override
  State<_MaxTokensField> createState() => _MaxTokensFieldState();
}

class _MaxTokensFieldState extends State<_MaxTokensField> {
  late final _c = TextEditingController(text: widget.value?.toString() ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: Sym.mono(size: 12, color: Sym.ink, weight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          hintText: '∞',
          hintStyle: Sym.mono(size: 12, color: Sym.inkFaint),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: Sym.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: Sym.amberDim),
          ),
        ),
        onChanged: (t) => widget.onChanged(t.isEmpty ? null : int.tryParse(t)),
      );
}
