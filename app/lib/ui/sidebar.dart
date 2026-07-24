import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ollama_probe.dart';
import '../models/conversation.dart';
import '../models/source.dart';
import '../net/host_limits.dart';
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

/// OS-aware "how do I start Ollama?" guidance, resolved only when the local
/// engine is down. Empty for remote/cloud endpoints, where systemctl/brew/
/// installer advice would just mislead. Gives Linux (Arch) and macOS users the
/// platform-correct steps instead of a blank offline state.
final _ollamaHintProvider = FutureProvider<String>((ref) async {
  final endpoint = ref.watch(endpointProvider);
  final isLoopback =
      endpoint.contains('127.0.0.1') || endpoint.contains('localhost');
  if (!isLoopback) return '';
  final status = await OllamaProbe.probe();
  return status.hint;
});

/// Live host-usage poll (~3s) for the admin readout. Only ticks while a server
/// is running; auto-disposes when the Host Controls widget leaves the tree
/// (i.e. hosting stops), so there is no timer running when nobody's watching.
final _hostStatsProvider = StreamProvider.autoDispose<Map<String, dynamic>?>(
  (ref) {
    Map<String, dynamic>? read() =>
        ref.read(hostControllerProvider.notifier).stats();
    final controller = StreamController<Map<String, dynamic>?>();
    controller.add(read());
    final timer = Timer.periodic(
        const Duration(seconds: 3), (_) => controller.add(read()));
    ref.onDispose(() {
      timer.cancel();
      controller.close();
    });
    return controller.stream;
  },
);

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
          InkWell(
            onTap: () => _editEndpoint(context, ref, endpoint),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  StatusDot(online: online),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            isCloud
                                ? 'CLOUD · ${active.label.toUpperCase()}'
                                : 'ENGINE',
                            style: Sym.label()),
                        const SizedBox(height: 2),
                        Text(
                          endpoint.replaceFirst(RegExp('^https?://'), ''),
                          style: Sym.mono(
                              size: 11, color: online ? Sym.ink : Sym.inkFaint),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.edit_outlined, size: 14, color: Sym.inkFaint),
                ],
              ),
            ),
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
              loading: () => Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Sym.amberDim),
                ),
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
                    // OS-aware next steps for a down LOCAL engine — Linux gets
                    // systemctl/pacman, macOS gets brew, Windows the installer.
                    if (!online)
                      Consumer(builder: (_, r, __) {
                        final hint = r.watch(_ollamaHintProvider).valueOrNull;
                        if (hint == null || hint.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            hint,
                            style: Sym.mono(size: 10, color: Sym.inkFaint),
                          ),
                        );
                      }),
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
                        final isSel = m.name == selected;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Material(
                            color:
                                isSel ? Sym.surfaceRaised : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => ref
                                  .read(selectedModelProvider.notifier)
                                  .state = m.name,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 9),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border(
                                    left: BorderSide(
                                      color: isSel
                                          ? Sym.amber
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.name,
                                      style: Sym.mono(
                                        size: 12.5,
                                        color: isSel ? Sym.ink : Sym.inkDim,
                                        weight: isSel
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      [
                                        if (m.parameterSize != null)
                                          m.parameterSize!,
                                        if (m.quantization != null)
                                          m.quantization!,
                                        m.sizeLabel,
                                      ].join(' · '),
                                      style: Sym.mono(
                                          size: 10, color: Sym.inkFaint),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
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
              ref.read(adminTokenProvider.notifier).state = null;
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
                    ref.read(adminTokenProvider.notifier).state = null;
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
            const SizedBox(height: 10),
            const _HostControls(),
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
    final adminCtrl = TextEditingController();

    void connect(BuildContext ctx) {
      final raw = ipCtrl.text.trim();
      if (raw.isEmpty) return;
      // Preserve an explicit https:// — the public cloud host
      // (host.visionarysparks.in) sits behind Caddy on 443. Only a bare LAN
      // address gets the default proxy port + http.
      final isHttps = raw.startsWith('https://');
      var addr = raw
          .replaceFirst(RegExp('^https?://'), '')
          .replaceAll(RegExp(r'/+$'), '');
      if (!addr.contains(':') && !isHttps) addr = '$addr:$kProxyPort';
      final code = codeCtrl.text.trim();
      final admin = adminCtrl.text.trim();
      ref.read(pairingCodeProvider.notifier).state = code.isEmpty ? null : code;
      ref.read(adminTokenProvider.notifier).state =
          admin.isEmpty ? null : admin;
      ref.read(endpointProvider.notifier).state =
          '${isHttps ? 'https' : 'http'}://$addr';
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
              const SizedBox(height: 8),
              TextField(
                controller: adminCtrl,
                obscureText: true,
                style: Sym.mono(size: 13, color: Sym.ink),
                onSubmitted: (_) => connect(ctx),
                decoration: InputDecoration(
                  hintText: 'admin token — hosts only, leave blank if guest',
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
      ref.read(adminTokenProvider.notifier).state = null;
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

/// The "router admin page" for a host: set the caps and watch live usage.
/// Collapsible so it never dominates the panel; edits are pushed onto the
/// running server immediately (no restart) via [HostController.updateLimits].
class _HostControls extends ConsumerStatefulWidget {
  const _HostControls();

  @override
  ConsumerState<_HostControls> createState() => _HostControlsState();
}

class _HostControlsState extends ConsumerState<_HostControls> {
  var _open = false;

  /// A labelled numeric field bound to one limits value. Reads the current
  /// [HostLimits] each build and writes back the whole object via [copyWith]
  /// so the running server updates live. `0 = unlimited` by contract.
  Widget _numField(
    String label,
    int value,
    HostLimits Function(HostLimits base, int v) apply,
  ) {
    final ctrl = TextEditingController(text: value.toString());
    ctrl.selection =
        TextSelection.collapsed(offset: ctrl.text.length);

    void save(String raw) {
      final v = int.tryParse(raw.trim());
      if (v == null || v < 0) return;
      final current = ref.read(hostLimitsProvider);
      ref.read(hostControllerProvider.notifier).updateLimits(apply(current, v));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Sym.mono(size: 10.5, color: Sym.inkDim)),
          ),
          SizedBox(
            width: 56,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              style: Sym.mono(size: 12, color: Sym.ink),
              onSubmitted: save,
              onEditingComplete: () => save(ctrl.text),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Sym.hairline)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Sym.amberDim)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: Sym.mono(
                  size: 14, color: Sym.teal, weight: FontWeight.w600)),
          Text(label, style: Sym.mono(size: 8.5, color: Sym.inkFaint)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final limits = ref.watch(hostLimitsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('HOST CONTROLS',
                      style: Sym.label(color: Sym.tealDim, size: 9)),
                ),
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 14, color: Sym.inkFaint),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 4),
          _numField('Max connections', limits.maxConnections,
              (b, v) => b.copyWith(maxConnections: v)),
          _numField('Max users/day', limits.maxUsersPerDay,
              (b, v) => b.copyWith(maxUsersPerDay: v)),
          _numField('Daily request cap', limits.dailyTotalCap,
              (b, v) => b.copyWith(dailyTotalCap: v)),
          _numField('Guest req/hour', limits.guestPerHour,
              (b, v) => b.copyWith(guestPerHour: v)),
          _numField('Student req/day', limits.studentPerDay,
              (b, v) => b.copyWith(studentPerDay: v)),
          Text('0 = unlimited · press Enter to apply',
              style: Sym.mono(size: 8.5, color: Sym.inkFaint)),
          const SizedBox(height: 10),
          Consumer(builder: (_, r, __) {
            final stats = r.watch(_hostStatsProvider).valueOrNull;
            final inFlight = stats?['in_flight'] ?? 0;
            final today = stats?['today_total'] ?? 0;
            final users = stats?['unique_users_today'] ?? 0;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _stat('in flight', '$inFlight'),
                _stat('today', '$today'),
                _stat('users', '$users'),
              ],
            );
          }),
        ],
      ],
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
            LinearProgressIndicator(
              value: pull.fraction,
              minHeight: 3,
              backgroundColor: Sym.hairline,
              color: pull.done ? Sym.teal : Sym.amber,
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
