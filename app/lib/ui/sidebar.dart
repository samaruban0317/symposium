import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/conversation.dart';
import '../models/source.dart';
import '../net/protocol.dart';
import '../state/app_state.dart';
import '../state/arena_state.dart';
import '../state/history_state.dart';
import '../state/net_state.dart';
import '../state/sources_contract.dart';
import '../state/sources_state.dart';
import '../theme.dart';
import 'about_dialog.dart';
import 'pull_dialog.dart';
import 'widgets.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sourcesLoadProvider); // hydrate saved sources from disk once
    final models = ref.watch(modelsProvider);
    final selected = ref.watch(selectedModelProvider);
    final online = ref.watch(serverOnlineProvider).valueOrNull ?? false;
    final endpoint = ref.watch(endpointProvider);
    final pull = ref.watch(pullControllerProvider);
    final active = ref.watch(activeSourceProvider);
    final isCloud = active.kind == SourceKind.cloud;

    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: Sym.surface,
        border: Border(right: BorderSide(color: Sym.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Endpoint tile
          _EndpointTile(
            online: online,
            isCloud: isCloud,
            label: active.label,
            endpoint: endpoint,
            onTap: () => _editEndpoint(context, ref, endpoint),
          ),
          const Divider(height: 1),
          const _ConversationsSection(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('MODELS', style: Sym.label()),
          ),
          Expanded(
            child: models.when(
              loading: () => ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (var i = 0; i < 5; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBar(width: 130 - i * 12.0, height: 12),
                          const SizedBox(height: 6),
                          const SkeletonBar(width: 80, height: 9),
                        ],
                      ),
                    ),
                ],
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      online
                          ? 'Could not list models.\n$e'
                          : 'No engine at this address.\nIs Ollama running?',
                      style: Sym.mono(size: 11, color: Sym.inkDim),
                    ),
                    // One click instead of "open a terminal and run ollama
                    // serve" — only offered where that could actually work.
                    if (!online &&
                        endpoint.contains('127.0.0.1') &&
                        !Platform.isAndroid &&
                        !Platform.isIOS) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () => _launchOllama(ref),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Sym.teal,
                          side: BorderSide(color: Sym.tealDim),
                        ),
                        child: Text('START OLLAMA',
                            style: Sym.label(color: Sym.teal, size: 9)),
                      ),
                    ],
                  ],
                ),
              ),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No models yet.\nInstall one below — it is one click.',
                        style: Sym.mono(size: 11, color: Sym.inkDim),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final m = list[i];
                        return _ModelTile(
                          name: m.name,
                          subtitle: [
                            if (m.parameterSize != null) m.parameterSize!,
                            if (m.quantization != null) m.quantization!,
                            m.sizeLabel,
                          ].join(' · '),
                          selected: m.name == selected,
                          onTap: () => ref
                              .read(selectedModelProvider.notifier)
                              .state = m.name,
                        );
                      },
                    ),
            ),
          ),
          const Divider(height: 1),
          const _CloudSection(),
          const Divider(height: 1),
          const _NetworkSection(),
          if (pull != null) _PullBanner(pull: pull),
          // Cloud providers host their own catalog — nothing to download there.
          if (!isCloud) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const PullDialog(),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Sym.amber,
                  side: BorderSide(color: Sym.amberDim),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.download_outlined, size: 16),
                label:
                    Text('INSTALL MODEL', style: Sym.label(color: Sym.amber)),
              ),
            ),
          ],
          const Divider(height: 1),
          InkWell(
            onTap: () => showSymAbout(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text('SYMPOSIUM · BY VISIONARY SPARKS',
                    style: Sym.label(color: Sym.inkFaint)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Fire-and-forget `ollama serve`, then re-ping. If the CLI is missing or
  /// the port is already taken this silently does nothing and the offline
  /// message simply stays — no worse than before the click.
  Future<void> _launchOllama(WidgetRef ref) async {
    try {
      await Process.start('ollama', ['serve'],
          mode: ProcessStartMode.detached, runInShell: true);
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 2));
    ref.invalidate(serverOnlineProvider);
    ref.invalidate(modelsProvider);
  }

  void _editEndpoint(BuildContext context, WidgetRef ref, String current) {
    final ctrl = TextEditingController(text: current);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sym.surfaceRaised,
        title: Text('Engine address', style: Sym.display(size: 20)),
        content: SizedBox(
          width: dialogWidth(ctx, 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Point Symposium at any OpenAI-compatible server —\nlocal Ollama, or a friend\'s PC on your network.',
                style: Sym.mono(size: 11, color: Sym.inkDim),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                style: Sym.mono(size: 13, color: Sym.ink),
                decoration: InputDecoration(
                  hintText: 'http://192.168.1.42:11434',
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Sym.hairline),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: Sym.label()),
          ),
          TextButton(
            onPressed: () {
              var url = ctrl.text.trim();
              if (url.isEmpty) return;
              if (!url.startsWith('http')) url = 'http://$url';
              ref.read(pairingCodeProvider.notifier).state = null;
              ref.read(endpointProvider.notifier).state =
                  url.replaceAll(RegExp(r'/+$'), '');
              Navigator.pop(ctx);
            },
            child: Text('CONNECT', style: Sym.label(color: Sym.amber)),
          ),
        ],
      ),
    );
  }
}

/// The connection tile at the top of the sidebar — status dot, ENGINE/CLOUD
/// label, address, and an edit affordance that brightens on hover.
class _EndpointTile extends StatefulWidget {
  final bool online;
  final bool isCloud;
  final String label;
  final String endpoint;
  final VoidCallback onTap;

  const _EndpointTile({
    required this.online,
    required this.isCloud,
    required this.label,
    required this.endpoint,
    required this.onTap,
  });

  @override
  State<_EndpointTile> createState() => _EndpointTileState();
}

class _EndpointTileState extends State<_EndpointTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Sym.fast,
            color: _hover
                ? Sym.surfaceRaised.withValues(alpha: 0.45)
                : Colors.transparent,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                StatusDot(online: widget.online),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          widget.isCloud
                              ? 'CLOUD · ${widget.label.toUpperCase()}'
                              : 'ENGINE',
                          style: Sym.label()),
                      const SizedBox(height: 2),
                      Text(
                        widget.endpoint.replaceFirst(RegExp('^https?://'), ''),
                        style: Sym.mono(
                            size: 11,
                            color: widget.online ? Sym.ink : Sym.inkFaint),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: _hover ? 1 : 0.5,
                  duration: Sym.fast,
                  child: Icon(Icons.edit_outlined,
                      size: 14,
                      color: _hover ? Sym.amber : Sym.inkFaint),
                ),
              ],
            ),
          ),
        ),
      );
}

/// A model in the sidebar list. Selected = raised surface + amber rail +
/// ink text; hover = a faint surface tint. The rail width animates so
/// selection reads as a small, deliberate shift rather than a flicker.
class _ModelTile extends StatefulWidget {
  final String name;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModelTile({
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ModelTile> createState() => _ModelTileState();
}

class _ModelTileState extends State<_ModelTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Sym.fast,
            curve: Sym.ease,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: sel
                  ? Sym.surfaceRaised
                  : (_hover
                      ? Sym.surfaceRaised.withValues(alpha: 0.5)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
              border: Border(
                left: BorderSide(
                  color: sel ? Sym.amber : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  style: Sym.mono(
                    size: 12.5,
                    color: sel || _hover ? Sym.ink : Sym.inkDim,
                    weight: sel ? FontWeight.w600 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(widget.subtitle,
                    style: Sym.mono(size: 10, color: Sym.inkFaint)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Past conversations — tap to reopen, keep talking, and the same history
/// entry updates. The active one carries the amber edge like a selected model.
class _ConversationsSection extends ConsumerWidget {
  const _ConversationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(historyLoadProvider); // hydrate saved conversations once
    final conversations = ref.watch(conversationsProvider);
    final activeId = ref.watch(activeConversationIdProvider);

    void closeDrawerIfOpen() {
      final scaffold = Scaffold.maybeOf(context);
      if (scaffold?.isDrawerOpen ?? false) Navigator.pop(context);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('CONVERSATIONS', style: Sym.label())),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  ref.read(chatControllerProvider.notifier).newConversation();
                  ref.read(homeTabProvider.notifier).state = HomeTab.chat;
                  closeDrawerIfOpen();
                },
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.add, size: 14, color: Sym.inkDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (conversations.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('your past chats will appear here',
                  style: Sym.mono(size: 10, color: Sym.inkFaint)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 176),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: conversations.length,
                itemBuilder: (_, i) {
                  final c = conversations[i];
                  final active = c.id == activeId;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        ref.read(chatControllerProvider.notifier).open(c);
                        ref.read(homeTabProvider.notifier).state = HomeTab.chat;
                        closeDrawerIfOpen();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: active ? Sym.amber : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.title,
                                    style: Sym.mono(
                                        size: 11.5,
                                        color: active ? Sym.ink : Sym.inkDim,
                                        weight: active
                                            ? FontWeight.w600
                                            : FontWeight.w400),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    '${_relativeTime(c.updatedAt)} · ${c.messages.length} msg',
                                    style: Sym.mono(
                                        size: 9.5, color: Sym.inkFaint),
                                  ),
                                ],
                              ),
                            ),
                            _ConversationMenu(conversation: c),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ConversationMenu extends ConsumerWidget {
  final Conversation conversation;
  const _ConversationMenu({required this.conversation});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        color: Sym.surfaceRaised,
        icon: Icon(Icons.more_horiz, size: 14, color: Sym.inkFaint),
        onSelected: (v) {
          switch (v) {
            case 'rename':
              _showRenameDialog(context, ref, conversation);
            case 'export':
              _export(context, conversation);
            case 'delete':
              ref.read(historyRepoProvider).remove(conversation.id);
              if (ref.read(activeConversationIdProvider) == conversation.id) {
                ref.read(chatControllerProvider.notifier).newConversation();
              }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'rename',
              child: Text('rename', style: Sym.mono(size: 11, color: Sym.ink))),
          PopupMenuItem(
              value: 'export',
              child: Text('export markdown',
                  style: Sym.mono(size: 11, color: Sym.ink))),
          PopupMenuItem(
              value: 'delete',
              child:
                  Text('delete', style: Sym.mono(size: 11, color: Sym.danger))),
        ],
      );

  /// Clipboard always; a file in Downloads too where that folder exists.
  Future<void> _export(BuildContext context, Conversation c) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: conversationMarkdown(c)));
    final path = await exportConversationFile(c);
    messenger?.showSnackBar(SnackBar(
      backgroundColor: Sym.surfaceRaised,
      content: Text(
        path == null ? 'copied as Markdown' : 'copied · saved to $path',
        style: Sym.mono(size: 11, color: Sym.ink),
      ),
    ));
  }
}

void _showRenameDialog(BuildContext context, WidgetRef ref, Conversation c) {
  final ctrl = TextEditingController(text: c.title);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Sym.surfaceRaised,
      title: Text('Rename conversation', style: Sym.display(size: 20)),
      content: SizedBox(
        width: dialogWidth(ctx, 360),
        child: TextField(
          controller: ctrl,
          autofocus: true,
          style: Sym.mono(size: 13, color: Sym.ink),
          onSubmitted: (t) {
            if (t.trim().isNotEmpty) {
              ref.read(historyRepoProvider).rename(c.id, t.trim());
            }
            Navigator.pop(ctx);
          },
          decoration: InputDecoration(
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Sym.hairline)),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: Sym.label())),
        TextButton(
          onPressed: () {
            final t = ctrl.text.trim();
            if (t.isNotEmpty) ref.read(historyRepoProvider).rename(c.id, t);
            Navigator.pop(ctx);
          },
          child: Text('SAVE', style: Sym.label(color: Sym.amber)),
        ),
      ],
    ),
  );
}

/// "just now", "5m", "3h", "2d", then a date — compact enough for the sidebar.
String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// Saved cloud providers — the "bring your own API key" shelf. A provider is
/// just one more OpenAI-compatible URL; the key rides along via the
/// engine-level auth registry, so tapping one works exactly like tapping a
/// peer: it only moves the global endpoint.
class _CloudSection extends ConsumerWidget {
  const _CloudSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clouds = [
      for (final s in ref.watch(savedSourcesProvider))
        if (s.kind == SourceKind.cloud) s,
    ];
    final endpoint = ref.watch(endpointProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('CLOUD', style: Sym.label())),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _showAddCloudDialog(context, ref),
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.add, size: 14, color: Sym.inkDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (clouds.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('add an API key — OpenAI, Gemini, Anthropic…',
                  style: Sym.mono(size: 10, color: Sym.inkFaint)),
            )
          else
            for (final s in clouds)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    ref.read(pairingCodeProvider.notifier).state = null;
                    ref.read(endpointProvider.notifier).state = s.baseUrl;
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: s.baseUrl == endpoint
                              ? Sym.amber
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 4),
                        Icon(Icons.cloud_outlined,
                            size: 13, color: Sym.tealDim),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.label,
                                  style: Sym.mono(
                                      size: 11.5,
                                      color: Sym.ink,
                                      weight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                s.baseUrl
                                    .replaceFirst(RegExp('^https?://'), ''),
                                style: Sym.mono(size: 9.5, color: Sym.inkFaint),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        _CloudMenu(source: s),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _CloudMenu extends ConsumerWidget {
  final ModelSource source;
  const _CloudMenu({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        color: Sym.surfaceRaised,
        icon: Icon(Icons.more_horiz, size: 14, color: Sym.inkFaint),
        onSelected: (v) {
          final repo = ref.read(sourcesRepoProvider);
          switch (v) {
            case 'key':
              _showEditKeyDialog(context, ref, source);
            case 'remove':
              repo.remove(source);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'key',
              child: Text('change key',
                  style: Sym.mono(size: 11, color: Sym.ink))),
          PopupMenuItem(
              value: 'remove',
              child:
                  Text('remove', style: Sym.mono(size: 11, color: Sym.danger))),
        ],
      );
}

void _showEditKeyDialog(
    BuildContext context, WidgetRef ref, ModelSource source) {
  final ctrl = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Sym.surfaceRaised,
      title: Text('New key for ${source.label}', style: Sym.display(size: 20)),
      content: SizedBox(
        width: dialogWidth(ctx, 380),
        child: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          style: Sym.mono(size: 13, color: Sym.ink),
          decoration: InputDecoration(
            hintText: presetFor(source.providerId).keyHint,
            hintStyle: Sym.mono(size: 12, color: Sym.inkFaint),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Sym.hairline)),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: Sym.label())),
        TextButton(
          onPressed: () {
            final key = ctrl.text.trim();
            if (key.isEmpty) return;
            ref.read(sourcesRepoProvider).updateKey(source, key);
            Navigator.pop(ctx);
          },
          child: Text('SAVE', style: Sym.label(color: Sym.amber)),
        ),
      ],
    ),
  );
}

/// Add-provider flow: pick a preset, paste a key, validate against the real
/// API (a spinner, then a model count or an actionable error), save.
void _showAddCloudDialog(BuildContext context, WidgetRef ref) {
  var preset = kCloudPresets.first;
  var custom = false;
  final keyCtrl = TextEditingController();
  final urlCtrl = TextEditingController();
  String? status; // null = idle, otherwise message
  var busy = false;
  var validatedOk = false;

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> validateAndSave({required bool saveAnyway}) async {
          final key = keyCtrl.text.trim();
          if (key.isEmpty) return;
          final chosen = custom
              ? const CloudPreset(
                  id: 'custom',
                  label: 'Custom',
                  baseUrl: '',
                  keyHint: 'API key')
              : preset;
          final url = custom ? urlCtrl.text.trim() : null;
          if (custom && (url == null || url.isEmpty)) return;
          final repo = ref.read(sourcesRepoProvider);
          if (!saveAnyway) {
            setState(() {
              busy = true;
              status = null;
              validatedOk = false;
            });
            try {
              final n = await repo.validate(
                  preset: chosen, key: key, customBaseUrl: url);
              setState(() {
                busy = false;
                validatedOk = true;
                status = 'connected · $n models';
              });
            } catch (e) {
              setState(() {
                busy = false;
                status = '$e'.replaceFirst('Exception: ', '');
              });
              return;
            }
          }
          await repo.addCloud(preset: chosen, key: key, customBaseUrl: url);
          if (ctx.mounted) Navigator.pop(ctx);
        }

        return AlertDialog(
          backgroundColor: Sym.surfaceRaised,
          title: Text('Add a cloud provider', style: Sym.display(size: 20)),
          content: SizedBox(
            width: dialogWidth(ctx),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste an API key and that provider joins the sidebar\nlike any other engine — same chat, same arena.',
                  style: Sym.mono(size: 11, color: Sym.inkDim),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final p in kCloudPresets)
                      _providerChip(p.label, !custom && preset.id == p.id, () {
                        setState(() {
                          preset = p;
                          custom = false;
                          status = null;
                        });
                      }),
                    _providerChip('Custom', custom, () {
                      setState(() {
                        custom = true;
                        status = null;
                      });
                    }),
                  ],
                ),
                if (custom) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: urlCtrl,
                    style: Sym.mono(size: 12, color: Sym.ink),
                    decoration: InputDecoration(
                      hintText: 'https://my-server.example.com/v1',
                      hintStyle: Sym.mono(size: 11, color: Sym.inkFaint),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Sym.hairline)),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: keyCtrl,
                  autofocus: true,
                  obscureText: true,
                  style: Sym.mono(size: 13, color: Sym.ink),
                  onSubmitted: (_) => validateAndSave(saveAnyway: false),
                  decoration: InputDecoration(
                    hintText: custom ? 'API key' : preset.keyHint,
                    hintStyle: Sym.mono(size: 12, color: Sym.inkFaint),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Sym.hairline)),
                  ),
                ),
                const SizedBox(height: 10),
                if (busy)
                  Row(children: [
                    SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Sym.amberDim)),
                    const SizedBox(width: 8),
                    Text('checking the key…',
                        style: Sym.mono(size: 10, color: Sym.inkDim)),
                  ])
                else if (status != null)
                  Text(status!,
                      style: Sym.mono(
                          size: 10, color: validatedOk ? Sym.teal : Sym.danger),
                      maxLines: 3),
                Text(
                  'the key is stored only on this device',
                  style: Sym.mono(size: 9, color: Sym.inkFaint),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('CANCEL', style: Sym.label())),
            // Validation failed but the user knows better (e.g. a provider
            // whose /models endpoint is blocked while chat works).
            if (!busy && status != null && !validatedOk)
              TextButton(
                onPressed: () => validateAndSave(saveAnyway: true),
                child: Text('SAVE ANYWAY', style: Sym.label()),
              ),
            TextButton(
              onPressed: busy ? null : () => validateAndSave(saveAnyway: false),
              child:
                  Text('VALIDATE & SAVE', style: Sym.label(color: Sym.amber)),
            ),
          ],
        );
      },
    ),
  );
}

Widget _providerChip(String label, bool selected, VoidCallback onTap) =>
    InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Sym.amber : Sym.hairline),
          color: selected ? Sym.surface : Colors.transparent,
        ),
        child: Text(label,
            style: Sym.mono(
                size: 10.5,
                color: selected ? Sym.amber : Sym.inkDim,
                weight: selected ? FontWeight.w600 : FontWeight.w400)),
      ),
    );

/// Host toggle + discovered peers. This is idea 2 from the original brief:
/// a friend's PC flips the switch, your sidebar sees it appear, one tap
/// (plus their 6-digit code) and you're using their models.
class _NetworkSection extends ConsumerWidget {
  const _NetworkSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(hostControllerProvider);
    final peers = ref.watch(discoveredHostsProvider).valueOrNull ?? const [];
    final hosting = host?.running == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('HOST ON NETWORK', style: Sym.label())),
              SizedBox(
                height: 24,
                child: FittedBox(
                  child: Switch(
                    value: hosting,
                    activeThumbColor: Sym.amber,
                    activeTrackColor: Sym.amberDim,
                    inactiveThumbColor: Sym.inkFaint,
                    inactiveTrackColor: Sym.surfaceRaised,
                    onChanged: (on) => on
                        ? ref.read(hostControllerProvider.notifier).enable()
                        : ref.read(hostControllerProvider.notifier).disable(),
                  ),
                ),
              ),
            ],
          ),
          if (hosting) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text('CODE', style: Sym.label(color: Sym.tealDim, size: 9)),
                const SizedBox(width: 8),
                SelectableText(
                  host!.code,
                  style: Sym.mono(
                      size: 16,
                      color: Sym.teal,
                      weight: FontWeight.w600,
                      spacing: 3),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('friends need this to connect',
                style: Sym.mono(size: 9.5, color: Sym.inkFaint)),
            if (host.addresses.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('THIS PC', style: Sym.label(color: Sym.tealDim, size: 9)),
              const SizedBox(height: 2),
              for (final a in host.addresses)
                SelectableText('$a:${host.port}',
                    style: Sym.mono(size: 11, color: Sym.ink)),
              const SizedBox(height: 2),
              Text(
                'not visible on phones? allow Symposium through\nthe firewall (private networks), or join by IP',
                style: Sym.mono(size: 9, color: Sym.inkFaint),
              ),
            ],
          ] else if (host?.error != null) ...[
            const SizedBox(height: 4),
            Text(host!.error!,
                style: Sym.mono(size: 9.5, color: Sym.danger), maxLines: 2),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text('PEERS', style: Sym.label())),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _joinByIp(context, ref),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text('JOIN BY IP',
                      style: Sym.label(color: Sym.tealDim, size: 8.5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('listening for hosts…',
                  style: Sym.mono(size: 10, color: Sym.inkFaint)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 132),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in peers)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _connectToPeer(context, ref, p),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          child: Row(
                            children: [
                              Icon(Icons.dns_outlined,
                                  size: 13, color: Sym.tealDim),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name,
                                        style: Sym.mono(
                                            size: 11.5,
                                            color: Sym.ink,
                                            weight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis),
                                    Text(
                                      '${p.address} · ${p.models.length} model${p.models.length == 1 ? '' : 's'}',
                                      style: Sym.mono(
                                          size: 9.5, color: Sym.inkFaint),
                                    ),
                                  ],
                                ),
                              ),
                              if (p.pairing)
                                Icon(Icons.lock_outline,
                                    size: 12, color: Sym.inkFaint),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Discovery uses UDP broadcast, which firewalls and some Wi-Fi setups eat.
  /// This is the guaranteed path: type the host's IP (shown on their screen)
  /// and the 6-digit code, and connect straight to the proxy.
  void _joinByIp(BuildContext context, WidgetRef ref) {
    final ipCtrl = TextEditingController();
    final codeCtrl = TextEditingController();

    void connect(BuildContext ctx) {
      var addr = ipCtrl.text.trim();
      if (addr.isEmpty) return;
      addr = addr
          .replaceFirst(RegExp('^https?://'), '')
          .replaceAll(RegExp(r'/+$'), '');
      if (!addr.contains(':')) addr = '$addr:$kProxyPort';
      final code = codeCtrl.text.trim();
      ref.read(pairingCodeProvider.notifier).state = code.isEmpty ? null : code;
      ref.read(endpointProvider.notifier).state = 'http://$addr';
      Navigator.pop(ctx);
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sym.surfaceRaised,
        title: Text('Join by IP', style: Sym.display(size: 20)),
        content: SizedBox(
          width: dialogWidth(ctx),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The host PC shows its address under\nHOST ON NETWORK → THIS PC.',
                style: Sym.mono(size: 11, color: Sym.inkDim),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ipCtrl,
                autofocus: true,
                style: Sym.mono(size: 13, color: Sym.ink),
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: '192.168.1.42:$kProxyPort',
                  hintStyle: Sym.mono(size: 12, color: Sym.inkFaint),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Sym.hairline)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: codeCtrl,
                maxLength: 6,
                keyboardType: TextInputType.number,
                style: Sym.mono(size: 16, color: Sym.teal, spacing: 4),
                onSubmitted: (_) => connect(ctx),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '6-digit code',
                  hintStyle: Sym.mono(size: 12, color: Sym.inkFaint),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Sym.hairline)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: Sym.label()),
          ),
          TextButton(
            onPressed: () => connect(ctx),
            child: Text('JOIN', style: Sym.label(color: Sym.amber)),
          ),
        ],
      ),
    );
  }

  void _connectToPeer(
      BuildContext context, WidgetRef ref, DiscoveredHost peer) {
    final ctrl = TextEditingController();

    void connect(BuildContext ctx) {
      if (peer.pairing && ctrl.text.trim().length != 6) return;
      ref.read(pairingCodeProvider.notifier).state =
          peer.pairing ? ctrl.text.trim() : null;
      ref.read(endpointProvider.notifier).state = peer.baseUrl;
      Navigator.pop(ctx);
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sym.surfaceRaised,
        title: Text('Join ${peer.name}', style: Sym.display(size: 20)),
        content: SizedBox(
          width: dialogWidth(ctx, 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (peer.models.isNotEmpty) ...[
                Text('SERVING', style: Sym.label(size: 9)),
                const SizedBox(height: 4),
                Text(peer.models.join('\n'),
                    style: Sym.mono(size: 11, color: Sym.inkDim), maxLines: 6),
                const SizedBox(height: 12),
              ],
              if (peer.pairing) ...[
                Text('Enter the 6-digit code shown on their screen:',
                    style: Sym.mono(size: 11, color: Sym.inkDim)),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLength: 6,
                  style: Sym.mono(size: 18, color: Sym.teal, spacing: 4),
                  onSubmitted: (_) => connect(ctx),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '······',
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Sym.hairline),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: Sym.label()),
          ),
          TextButton(
            onPressed: () => connect(ctx),
            child: Text('JOIN', style: Sym.label(color: Sym.amber)),
          ),
        ],
      ),
    );
  }
}

class _PullBanner extends ConsumerWidget {
  final PullState pull;
  const _PullBanner({required this.pull});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = pull.error != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Sym.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: failed ? Sym.danger : Sym.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pull.model,
                  style: Sym.mono(
                      size: 11.5, color: Sym.ink, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pull.done || failed)
                GestureDetector(
                  onTap: () =>
                      ref.read(pullControllerProvider.notifier).dismiss(),
                  child: Icon(Icons.close, size: 13, color: Sym.inkFaint),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (!failed) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pull.fraction,
                minHeight: 4,
                backgroundColor: Sym.hairline,
                color: pull.done ? Sym.teal : Sym.amber,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              pull.done
                  ? 'ready — it is in your model list'
                  : '${pull.status}${pull.fraction != null ? '  ${(pull.fraction! * 100).toStringAsFixed(0)}%' : ''}',
              style:
                  Sym.mono(size: 10, color: pull.done ? Sym.teal : Sym.inkDim),
            ),
          ] else
            Text(pull.error!, style: Sym.mono(size: 10, color: Sym.danger)),
        ],
      ),
    );
  }
}
