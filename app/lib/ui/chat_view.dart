import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'message_markdown.dart';
import 'parameter_lab.dart';
import 'persona/persona_chip.dart';
import 'widgets.dart';

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key});

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _labOpen = false;
  int? _editingIndex; // user message currently being rewritten inline

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(chatControllerProvider.notifier).send(text);
  }

  void _startEdit(int index) => setState(() => _editingIndex = index);

  void _submitEdit(int index, String text) {
    setState(() => _editingIndex = null);
    ref.read(chatControllerProvider.notifier).editAndResend(index, text);
  }

  void _fork(int index) {
    setState(() => _editingIndex = null);
    ref.read(chatControllerProvider.notifier).forkFrom(index);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final model = ref.watch(selectedModelProvider);

    // Keep the newest tokens on screen while streaming.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && chat.isStreaming) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });

    return Column(
      children: [
        Expanded(
          child: chat.messages.isEmpty
              ? _EmptyState(model: model)
              : SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
                    itemCount: chat.messages.length,
                    itemBuilder: (_, i) => _MessageBlock(
                      msg: chat.messages[i],
                      index: i,
                      isLast: i == chat.messages.length - 1,
                      streaming: chat.isStreaming && i == chat.messages.length - 1,
                      busy: chat.isStreaming,
                      editing: _editingIndex == i,
                      onEdit: () => _startEdit(i),
                      onEditSubmit: (text) => _submitEdit(i, text),
                      onEditCancel: () => setState(() => _editingIndex = null),
                      onRegenerate: () =>
                          ref.read(chatControllerProvider.notifier).regenerate(),
                      onFork: () => _fork(i),
                    ),
                  ),
                ),
        ),
        if (chat.error != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Sym.danger),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: Sym.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(chat.error!,
                      style: Sym.mono(size: 11, color: Sym.danger), maxLines: 3),
                ),
              ],
            ),
          ),
        // AnimatedSize keeps open/close smooth without measuring the panel.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: _labOpen ? const ParameterLab() : const SizedBox.shrink(),
        ),
        ParamChips(onTap: () => setState(() => _labOpen = true)),
        _Composer(
          input: _input,
          onSend: _send,
          streaming: chat.isStreaming,
          onStop: () => ref.read(chatControllerProvider.notifier).stop(),
          enabled: model != null,
          labOpen: _labOpen,
          onToggleLab: () => setState(() => _labOpen = !_labOpen),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String? model;
  const _EmptyState({this.model});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('☙', style: Sym.display(size: 34, color: Sym.amberDim)),
            const SizedBox(height: 14),
            Text('The floor is yours.',
                style: Sym.display(size: 30, weight: FontWeight.w400)),
            const SizedBox(height: 10),
            Text(
              model == null
                  ? 'connect an engine and choose a model to begin'
                  : 'speaking with  $model',
              style: Sym.mono(size: 11.5, color: Sym.inkDim, spacing: 0.5),
            ),
          ],
        ),
      );
}

class _MessageBlock extends StatefulWidget {
  final ChatMessage msg;
  final int index;
  final bool isLast;
  final bool streaming; // this message is receiving tokens right now
  final bool busy; // anything is streaming — actions must stay out of the way
  final bool editing;
  final VoidCallback onEdit;
  final ValueChanged<String> onEditSubmit;
  final VoidCallback onEditCancel;
  final VoidCallback onRegenerate;
  final VoidCallback onFork;

  const _MessageBlock({
    required this.msg,
    required this.index,
    required this.isLast,
    required this.streaming,
    required this.busy,
    required this.editing,
    required this.onEdit,
    required this.onEditSubmit,
    required this.onEditCancel,
    required this.onRegenerate,
    required this.onFork,
  });

  @override
  State<_MessageBlock> createState() => _MessageBlockState();
}

class _MessageBlockState extends State<_MessageBlock> {
  bool _hover = false;

  bool get _isUser => widget.msg.role == Role.user;

  List<_MsgAction> get _actions => [
        _MsgAction(Icons.copy_all_outlined, 'Copy', () {
          Clipboard.setData(ClipboardData(text: widget.msg.content));
        }),
        if (_isUser && !widget.busy)
          _MsgAction(Icons.edit_outlined, 'Edit & resend', widget.onEdit),
        if (!_isUser && widget.isLast && !widget.busy)
          _MsgAction(Icons.refresh, 'Regenerate', widget.onRegenerate),
        if (!widget.busy && !widget.isLast)
          _MsgAction(Icons.call_split, 'Fork from here', widget.onFork),
      ];

  // Touch fallback for the hover row: same actions, bottom sheet.
  void _showActionSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Sym.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in _actions)
              ListTile(
                dense: true,
                leading: Icon(a.icon, size: 17, color: Sym.inkDim),
                title: Text(a.label, style: Sym.mono(size: 12.5, color: Sym.ink)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  a.run();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _isUser ? Sym.amber : Sym.teal;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onLongPress: widget.editing ? null : _showActionSheet,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 780),
          margin: const EdgeInsets.only(bottom: 22, left: 16, right: 16),
          padding: const EdgeInsets.only(left: 14),
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
                    _isUser ? 'YOU' : (widget.msg.modelName ?? 'MODEL').toUpperCase(),
                    style: Sym.label(color: accent.withValues(alpha: 0.8), size: 9.5),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _hover && !widget.editing ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final a in _actions)
                          _ActionIcon(icon: a.icon, tooltip: a.label, onTap: a.run),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (widget.editing)
                _InlineEditor(
                  initial: widget.msg.content,
                  onSubmit: widget.onEditSubmit,
                  onCancel: widget.onEditCancel,
                )
              else if (widget.msg.content.isEmpty && widget.streaming)
                const StreamingCursor()
              else if (_isUser)
                Text(widget.msg.content, style: Sym.body(size: 15))
              else ...[
                MessageMarkdown(text: widget.msg.content),
                if (widget.streaming)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: StreamingCursor(),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MsgAction {
  final IconData icon;
  final String label;
  final VoidCallback run;
  const _MsgAction(this.icon, this.label, this.run);
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ActionIcon({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 14, color: Sym.inkDim),
          ),
        ),
      );
}

/// Replaces a user bubble's text while rewriting it. Enter resends; the
/// transcript below the edited message is discarded by the controller.
class _InlineEditor extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  const _InlineEditor({
    required this.initial,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<_InlineEditor> createState() => _InlineEditorState();
}

class _InlineEditorState extends State<_InlineEditor> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _c,
            autofocus: true,
            minLines: 1,
            maxLines: 8,
            style: Sym.body(size: 15),
            textInputAction: TextInputAction.send,
            onSubmitted: widget.onSubmit,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.all(10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Sym.amberDim),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Sym.amber),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('everything after this message will be replaced',
                  style: Sym.mono(size: 9.5, color: Sym.inkFaint)),
              const Spacer(),
              TextButton(
                onPressed: widget.onCancel,
                child: Text('cancel', style: Sym.mono(size: 11, color: Sym.inkDim)),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => widget.onSubmit(_c.text),
                child: Text('resend', style: Sym.mono(size: 11, color: Sym.amber)),
              ),
            ],
          ),
        ],
      );
}

class _Composer extends StatelessWidget {
  final TextEditingController input;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final bool streaming;
  final bool enabled;
  final bool labOpen;
  final VoidCallback onToggleLab;

  const _Composer({
    required this.input,
    required this.onSend,
    required this.onStop,
    required this.streaming,
    required this.enabled,
    required this.labOpen,
    required this.onToggleLab,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      constraints: const BoxConstraints(maxWidth: 780),
      decoration: BoxDecoration(
        color: Sym.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sym.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Speak as a persona: sets system prompt + knobs in one tap.
          const PersonaChipButton(),
          Padding(
            padding: const EdgeInsets.all(6),
            child: IconButton(
              onPressed: onToggleLab,
              tooltip: labOpen ? 'Close parameter lab' : 'Parameter lab',
              icon: Icon(Icons.tune, size: 18, color: labOpen ? Sym.amber : Sym.inkDim),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
              child: TextField(
                controller: input,
                enabled: enabled,
                minLines: 1,
                maxLines: 8,
                style: Sym.body(size: 15),
                onSubmitted: (_) => onSend(),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: enabled ? 'Address the symposium…' : 'no model selected',
                  hintStyle: Sym.body(size: 15, color: Sym.inkFaint),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: streaming
                ? IconButton(
                    onPressed: onStop,
                    tooltip: 'Stop generation',
                    icon: const Icon(Icons.stop_circle_outlined, color: Sym.danger),
                  )
                : IconButton(
                    onPressed: enabled ? onSend : null,
                    tooltip: 'Send',
                    icon: Icon(Icons.arrow_upward,
                        color: enabled ? Sym.amber : Sym.inkFaint),
                  ),
          ),
        ],
      ),
    );
  }
}
