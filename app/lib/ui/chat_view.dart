import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key});

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(chatControllerProvider.notifier).send(text);
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
                      isLast: i == chat.messages.length - 1,
                      streaming: chat.isStreaming && i == chat.messages.length - 1,
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
        _Composer(
          input: _input,
          onSend: _send,
          streaming: chat.isStreaming,
          onStop: () => ref.read(chatControllerProvider.notifier).stop(),
          enabled: model != null,
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

class _MessageBlock extends StatelessWidget {
  final ChatMessage msg;
  final bool isLast;
  final bool streaming;

  const _MessageBlock({required this.msg, required this.isLast, required this.streaming});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == Role.user;
    final accent = isUser ? Sym.amber : Sym.teal;

    return Container(
      constraints: const BoxConstraints(maxWidth: 780),
      margin: const EdgeInsets.only(bottom: 22, left: 16, right: 16),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent.withValues(alpha: 0.55), width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isUser ? 'YOU' : (msg.modelName ?? 'MODEL').toUpperCase(),
            style: Sym.label(color: accent.withValues(alpha: 0.8), size: 9.5),
          ),
          const SizedBox(height: 6),
          if (msg.content.isEmpty && streaming)
            const StreamingCursor()
          else
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: msg.content),
                  if (streaming) const WidgetSpan(child: StreamingCursor()),
                ],
              ),
              style: Sym.body(size: isUser ? 15 : 15.5),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController input;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final bool streaming;
  final bool enabled;

  const _Composer({
    required this.input,
    required this.onSend,
    required this.onStop,
    required this.streaming,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      constraints: const BoxConstraints(maxWidth: 780),
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
