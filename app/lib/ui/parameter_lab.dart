import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// The parameter lab: sampling knobs + system prompt for the *next* request.
///
/// Deliberately an instrument panel, not a settings page — every control has
/// a live mono readout, and nothing here is saved anywhere: the values live
/// in [chatParamsProvider] and are read at send time.
class ParameterLab extends ConsumerWidget {
  const ParameterLab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = ref.watch(chatParamsProvider);
    final notifier = ref.read(chatParamsProvider.notifier);

    return Container(
      constraints: const BoxConstraints(maxWidth: 780),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Sym.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sym.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('PARAMETER LAB', style: Sym.label(color: Sym.amberDim)),
              const Spacer(),
              if (!params.isDefault)
                _GhostButton(
                  label: 'RESET',
                  onTap: () => notifier.state = const ChatParams(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _LabSlider(
            label: 'TEMPERATURE',
            value: params.temperature,
            min: 0,
            max: 2,
            display: params.temperature.toStringAsFixed(2),
            isDefault: params.temperature == ChatParams.defaultTemperature,
            onChanged: (v) => notifier.state = params.copyWith(temperature: v),
          ),
          _LabSlider(
            label: 'TOP-P',
            value: params.topP,
            min: 0.05,
            max: 1,
            display: params.topP.toStringAsFixed(2),
            isDefault: params.topP == ChatParams.defaultTopP,
            onChanged: (v) => notifier.state = params.copyWith(topP: v),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: Text('MAX TOKENS', style: Sym.label(size: 9)),
              ),
              SizedBox(
                width: 80,
                child: _MaxTokensField(
                  value: params.maxTokens,
                  onChanged: (v) => notifier.state = v == null
                      ? params.copyWith(clearMaxTokens: true)
                      : params.copyWith(maxTokens: v),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                params.maxTokens == null ? 'unbounded' : 'reply cap',
                style: Sym.mono(size: 10, color: Sym.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Text('SYSTEM PROMPT', style: Sym.label(size: 9)),
          const SizedBox(height: 6),
          _SystemPromptField(
            value: params.systemPrompt,
            onChanged: (v) => notifier.state = params.copyWith(systemPrompt: v),
          ),
        ],
      ),
    );
  }
}

/// Chips summarising every non-default knob, shown by the composer so the
/// active settings are never invisible. Tapping one opens the lab.
class ParamChips extends ConsumerWidget {
  final VoidCallback onTap;
  const ParamChips({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = ref.watch(chatParamsProvider);
    if (params.isDefault) return const SizedBox.shrink();

    final labels = <String>[
      if (params.temperature != ChatParams.defaultTemperature)
        'TEMP ${params.temperature.toStringAsFixed(2)}',
      if (params.topP != ChatParams.defaultTopP) 'TOP-P ${params.topP.toStringAsFixed(2)}',
      if (params.maxTokens != null) 'MAX ${params.maxTokens}',
      if (params.systemPrompt.trim().isNotEmpty) 'SYSTEM ●',
    ];

    return Container(
      constraints: const BoxConstraints(maxWidth: 780),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final l in labels) _ParamChip(label: l, onTap: onTap),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

/// One active-parameter chip beside the composer, with a gentle hover fill.
class _ParamChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _ParamChip({required this.label, required this.onTap});

  @override
  State<_ParamChip> createState() => _ParamChipState();
}

class _ParamChipState extends State<_ParamChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: _hover
                  ? Sym.amber.withValues(alpha: 0.1)
                  : Colors.transparent,
              border:
                  Border.all(color: Sym.amberDim.withValues(alpha: 0.6)),
            ),
            child: Text(widget.label,
                style: Sym.mono(size: 9.5, color: Sym.amber, spacing: 1)),
          ),
        ),
      );
}

class _LabSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final bool isDefault;
  final ValueChanged<double> onChanged;

  const _LabSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.isDefault,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: Sym.label(size: 9))),
          Expanded(
            // Thin hairline track + small thumb: a fader, not a Material pill.
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
              child: Slider(value: value, min: min, max: max, onChanged: onChanged),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: Sym.mono(
                size: 12,
                color: isDefault ? Sym.inkDim : Sym.amber,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
}

/// Digits only; blank means "no cap". Kept as a field because a slider over
/// an unbounded range would lie about where the interesting values are.
class _MaxTokensField extends StatefulWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  const _MaxTokensField({required this.value, required this.onChanged});

  @override
  State<_MaxTokensField> createState() => _MaxTokensFieldState();
}

class _MaxTokensFieldState extends State<_MaxTokensField> {
  late final _c = TextEditingController(text: widget.value?.toString() ?? '');

  @override
  void didUpdateWidget(_MaxTokensField old) {
    super.didUpdateWidget(old);
    final text = widget.value?.toString() ?? '';
    // Only follow external resets (e.g. the RESET button) — never fight typing.
    if (widget.value != old.value && _c.text != text) _c.text = text;
  }

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

class _SystemPromptField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _SystemPromptField({required this.value, required this.onChanged});

  @override
  State<_SystemPromptField> createState() => _SystemPromptFieldState();
}

class _SystemPromptFieldState extends State<_SystemPromptField> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_SystemPromptField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        minLines: 2,
        maxLines: 5,
        style: Sym.body(size: 13.5),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Who should the model be? Applied to every request, shown to no one.',
          hintStyle: Sym.body(size: 13.5, color: Sym.inkFaint),
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
        onChanged: widget.onChanged,
      );
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(label, style: Sym.label(size: 9, color: Sym.inkDim)),
        ),
      );
}
