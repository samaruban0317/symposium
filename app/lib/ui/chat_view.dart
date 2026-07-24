import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat.dart';
import '../state/app_state.dart';
import '../state/attachments_state.dart';
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
  bool _nearBottom = true; // autoscroll only while the reader is at the tail
  int? _editingIndex; // user message currently being rewritten inline

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty && ref.read(attachmentsProvider).isEmpty) return;
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

    // Keep the newest tokens on screen while streaming — but never fight a
    // reader who has deliberately scrolled up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && chat.isStreaming && _nearBottom) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });

    return Column(
      children: [
        Expanded(
          child: chat.messages.isEmpty
              ? _EmptyState(
                  model: model,
                  onSuggest: (text) {
                    _input.text = text;
                    setState(() {});
                  },
                )
              : Stack(
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        final near = n.metrics.pixels >=
                            n.metrics.maxScrollExtent - 120;
                        if (near != _nearBottom) {
                          setState(() => _nearBottom = near);
                        }
                        return false;
                      },
                      child: SelectionArea(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                              vertical: 28, horizontal: 8),
                          itemCount: chat.messages.length,
                          itemBuilder: (_, i) => _MessageBlock(
                            msg: chat.messages[i],
                            index: i,
                            isLast: i == chat.messages.length - 1,
                            streaming: chat.isStreaming &&
                                i == chat.messages.length - 1,
                            busy: chat.isStreaming,
                            editing: _editingIndex == i,
                            onEdit: () => _startEdit(i),
                            onEditSubmit: (text) => _submitEdit(i, text),
                            onEditCancel: () =>
                                setState(() => _editingIndex = null),
                            onRegenerate: () => ref
                                .read(chatControllerProvider.notifier)
                                .regenerate(),
                            onFork: () => _fork(i),
                          ),
                        ),
                      ),
                    ),
                    if (!_nearBottom)
                      Positioned(
                        right: 20,
                        bottom: 12,
                        child: Material(
                          color: Sym.surfaceRaised,
                          shape: const CircleBorder(),
                          elevation: 3,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              _scroll.jumpTo(_scroll.position.maxScrollExtent);
                              setState(() => _nearBottom = true);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(9),
                              child: Icon(Icons.arrow_downward,
                                  size: 16, color: Sym.amber),
                            ),
                          ),
                        ),
                      ),
                  ],
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
                Icon(Icons.error_outline, size: 14, color: Sym.danger),
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
  final ValueChanged<String> onSuggest;
  const _EmptyState({this.model, required this.onSuggest});

  static const _starters = [
    ('Explain something', 'Explain how a neural network learns, like I am twelve.'),
    ('Get writing help', 'Rewrite this to sound clearer and more confident: '),
    ('Reason it out', 'What are the strongest arguments for and against '),
    ('Code with me', 'Write a small Python script that '),
  ];

  @override
  Widget build(BuildContext context) => Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Emblem sits in a soft amber halo — the one glow of the view.
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      Sym.amber.withValues(alpha: 0.14),
                      Sym.amber.withValues(alpha: 0.0),
                    ]),
                  ),
                  child: Text('☙', style: Sym.display(size: 34, color: Sym.amber)),
                ),
                const SizedBox(height: 18),
                Text('The floor is yours.',
                    textAlign: TextAlign.center,
                    style: Sym.display(size: 32, weight: FontWeight.w400)),
                const SizedBox(height: 12),
                Text(
                  model == null
                      ? 'connect an engine and choose a model to begin'
                      : 'speaking with  $model',
                  style: Sym.mono(size: 11.5, color: Sym.inkDim, spacing: 0.5),
                ),
                if (model != null) ...[
                  const SizedBox(height: 30),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final (label, prompt) in _starters)
                        _StarterChip(label: label, onTap: () => onSuggest(prompt)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('or attach an image or document with the paperclip',
                      style: Sym.mono(size: 9.5, color: Sym.inkFaint)),
                ],
              ],
            ),
          ),
        ),
      );
}

/// A suggestion pill in the empty state. Warms toward amber on hover.
class _StarterChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _StarterChip({required this.label, required this.onTap});

  @override
  State<_StarterChip> createState() => _StarterChipState();
}

class _StarterChipState extends State<_StarterChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(
              color: _hover ? Sym.amber.withValues(alpha: 0.07) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _hover ? Sym.amber.withValues(alpha: 0.5) : Sym.hairline,
              ),
            ),
            child: Text(widget.label,
                style: Sym.mono(
                    size: 11, color: _hover ? Sym.amber : Sym.inkDim)),
          ),
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

    // The user's turn sits in a soft raised card; the assistant flows open
    // against an accent rail — a calm, clear distinction between the voices.
    final bodyPadding = _isUser
        ? const EdgeInsets.fromLTRB(16, 12, 16, 14)
        : const EdgeInsets.only(left: 16, top: 2);
    final decoration = _isUser
        ? BoxDecoration(
            color: Sym.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Sym.hairline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          )
        : BoxDecoration(
            border: Border(
              left: BorderSide(color: accent.withValues(alpha: 0.5), width: 2),
            ),
          );

    final block = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onLongPress: widget.editing ? null : _showActionSheet,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 780),
          margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
          padding: bodyPadding,
          decoration: decoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(right: 7),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    _isUser ? 'YOU' : (widget.msg.modelName ?? 'MODEL').toUpperCase(),
                    style: Sym.label(color: accent.withValues(alpha: 0.85), size: 9.5),
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
              const SizedBox(height: 8),
              if (widget.editing)
                _InlineEditor(
                  initial: widget.msg.content,
                  onSubmit: widget.onEditSubmit,
                  onCancel: widget.onEditCancel,
                )
              else if (widget.msg.content.isEmpty && widget.streaming)
                const StreamingCursor()
              else if (_isUser) ...[
                if (widget.msg.images.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final b64 in widget.msg.images)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              base64Decode(b64),
                              width: 140,
                              height: 140,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 140,
                                height: 140,
                                color: Sym.surface,
                                child: Icon(Icons.broken_image_outlined,
                                    size: 22, color: Sym.inkFaint),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (widget.msg.docName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined,
                            size: 13, color: Sym.tealDim),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(widget.msg.docName!,
                              style: Sym.mono(size: 10.5, color: Sym.tealDim),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                if (widget.msg.content.isNotEmpty)
                  Text(widget.msg.content, style: Sym.body(size: 15)),
              ] else ...[
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

    // Each turn drifts up and fades in once, keeping the transcript alive
    // without re-animating on every streamed rebuild.
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.index),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: block,
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
                borderSide: BorderSide(color: Sym.amberDim),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: Sym.amber),
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

class _Composer extends ConsumerStatefulWidget {
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
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(attachmentsProvider);

    final focused = _focus.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      constraints: const BoxConstraints(maxWidth: 780),
      decoration: BoxDecoration(
        color: Sym.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? Sym.amber.withValues(alpha: 0.55) : Sym.hairline,
          width: focused ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: focused
                ? Sym.amber.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.14),
            blurRadius: focused ? 16 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!pending.isEmpty || pending.error != null)
            _PendingAttachmentsRow(pending: pending),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Speak as a persona: sets system prompt + knobs in one tap.
              const PersonaChipButton(),
              Padding(
                padding: const EdgeInsets.all(6),
                child: IconButton(
                  onPressed: widget.onToggleLab,
                  tooltip:
                      widget.labOpen ? 'Close parameter lab' : 'Parameter lab',
                  icon: Icon(Icons.tune,
                      size: 18, color: widget.labOpen ? Sym.amber : Sym.inkDim),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Attach',
                color: Sym.surfaceRaised,
                icon: Icon(Icons.attach_file, size: 18, color: Sym.inkDim),
                onSelected: (v) => v == 'image'
                    ? ref.read(attachmentsProvider.notifier).pickImage()
                    : ref.read(attachmentsProvider.notifier).pickDocument(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'image',
                    child: Row(children: [
                      Icon(Icons.image_outlined, size: 15, color: Sym.tealDim),
                      const SizedBox(width: 8),
                      Text('image — vision models',
                          style: Sym.mono(size: 11, color: Sym.ink)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'doc',
                    child: Row(children: [
                      Icon(Icons.description_outlined,
                          size: 15, color: Sym.tealDim),
                      const SizedBox(width: 8),
                      Text('document — pdf, text, code',
                          style: Sym.mono(size: 11, color: Sym.ink)),
                    ]),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
                  child: TextField(
                    controller: widget.input,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    minLines: 1,
                    maxLines: 8,
                    style: Sym.body(size: 15),
                    onSubmitted: (_) => widget.onSend(),
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: widget.enabled
                          ? 'Address the symposium…'
                          : 'no model selected',
                      hintStyle: Sym.body(size: 15, color: Sym.inkFaint),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 8, 6),
                child: widget.streaming
                    ? IconButton(
                        onPressed: widget.onStop,
                        tooltip: 'Stop generation',
                        icon:
                            Icon(Icons.stop_circle_outlined, color: Sym.danger),
                      )
                    : Tooltip(
                        message: 'Send',
                        child: Material(
                          color: widget.enabled
                              ? Sym.amber
                              : Sym.hairline.withValues(alpha: 0.6),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: widget.enabled ? widget.onSend : null,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.arrow_upward,
                                size: 18,
                                color: widget.enabled ? Sym.bg : Sym.inkFaint,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What's clipped to the next message: image thumbnails and the document
/// chip, each with its own remove ✕, plus any attach error.
class _PendingAttachmentsRow extends ConsumerWidget {
  final PendingAttachments pending;
  const _PendingAttachmentsRow({required this.pending});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(attachmentsProvider.notifier);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < pending.images.length; i++)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    base64Decode(pending.images[i]),
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 54,
                      height: 54,
                      color: Sym.surface,
                      child: Icon(Icons.broken_image_outlined,
                          size: 18, color: Sym.inkFaint),
                    ),
                  ),
                ),
                Positioned(
                  top: 1,
                  right: 1,
                  child: InkWell(
                    onTap: () => ctrl.removeImage(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Sym.bg.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 11, color: Sym.ink),
                    ),
                  ),
                ),
              ],
            ),
          if (pending.docName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Sym.tealDim.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined,
                      size: 13, color: Sym.tealDim),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(pending.docName!,
                        style: Sym.mono(size: 10.5, color: Sym.ink),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 4),
                  Text('${((pending.docText?.length ?? 0) / 1000).ceil()}k chars',
                      style: Sym.mono(size: 9, color: Sym.inkFaint)),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: ctrl.removeDoc,
                    child: Icon(Icons.close, size: 12, color: Sym.inkDim),
                  ),
                ],
              ),
            ),
          if (pending.images.isNotEmpty)
            Text('needs a vision model — llava, gemma3, qwen2.5vl…',
                style: Sym.mono(size: 9, color: Sym.inkFaint)),
          if (pending.error != null)
            Text(pending.error!, style: Sym.mono(size: 9.5, color: Sym.danger)),
        ],
      ),
    );
  }
}
