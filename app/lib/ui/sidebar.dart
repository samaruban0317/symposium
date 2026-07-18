import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/source.dart';
import '../net/protocol.dart';
import '../state/app_state.dart';
import '../state/net_state.dart';
import '../state/sources_contract.dart';
import '../state/sources_state.dart';
import '../theme.dart';
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
      decoration: const BoxDecoration(
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
                        Text(isCloud ? 'CLOUD · ${active.label.toUpperCase()}' : 'ENGINE',
                            style: Sym.label()),
                        const SizedBox(height: 2),
                        Text(
                          endpoint.replaceFirst(RegExp('^https?://'), ''),
                          style: Sym.mono(size: 11, color: online ? Sym.ink : Sym.inkFaint),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_outlined, size: 14, color: Sym.inkFaint),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('MODELS', style: Sym.label()),
          ),
          Expanded(
            child: models.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Sym.amberDim),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  online
                      ? 'Could not list models.\n$e'
                      : 'No engine at this address.\nIs Ollama running?',
                  style: Sym.mono(size: 11, color: Sym.inkDim),
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
                            color: isSel ? Sym.surfaceRaised : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () =>
                                  ref.read(selectedModelProvider.notifier).state = m.name,
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border(
                                    left: BorderSide(
                                      color: isSel ? Sym.amber : Colors.transparent,
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
                                        weight: isSel ? FontWeight.w600 : FontWeight.w400,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      [
                                        if (m.parameterSize != null) m.parameterSize!,
                                        if (m.quantization != null) m.quantization!,
                                        m.sizeLabel,
                                      ].join(' · '),
                                      style: Sym.mono(size: 10, color: Sym.inkFaint),
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
                  side: const BorderSide(color: Sym.amberDim),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text('INSTALL MODEL', style: Sym.label(color: Sym.amber)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _editEndpoint(BuildContext context, WidgetRef ref, String current) {
    final ctrl = TextEditingController(text: current);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sym.surfaceRaised,
        title: Text('Engine address', style: Sym.display(size: 20)),
        content: SizedBox(
          width: 380,
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
                decoration: const InputDecoration(
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
              ref.read(endpointProvider.notifier).state = url.replaceAll(RegExp(r'/+$'), '');
              Navigator.pop(ctx);
            },
            child: Text('CONNECT', style: Sym.label(color: Sym.amber)),
          ),
        ],
      ),
    );
  }
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
                child: const Padding(
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
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: s.baseUrl == endpoint ? Sym.amber : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 4),
                        const Icon(Icons.cloud_outlined, size: 13, color: Sym.tealDim),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.label,
                                  style: Sym.mono(
                                      size: 11.5, color: Sym.ink, weight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                s.baseUrl.replaceFirst(RegExp('^https?://'), ''),
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
        icon: const Icon(Icons.more_horiz, size: 14, color: Sym.inkFaint),
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
              child: Text('change key', style: Sym.mono(size: 11, color: Sym.ink))),
          PopupMenuItem(
              value: 'remove',
              child: Text('remove', style: Sym.mono(size: 11, color: Sym.danger))),
        ],
      );
}

void _showEditKeyDialog(BuildContext context, WidgetRef ref, ModelSource source) {
  final ctrl = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Sym.surfaceRaised,
      title: Text('New key for ${source.label}', style: Sym.display(size: 20)),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          style: Sym.mono(size: 13, color: Sym.ink),
          decoration: InputDecoration(
            hintText: presetFor(source.providerId).keyHint,
            hintStyle: Sym.mono(size: 12, color: Sym.inkFaint),
            enabledBorder:
                const UnderlineInputBorder(borderSide: BorderSide(color: Sym.hairline)),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text('CANCEL', style: Sym.label())),
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
                  id: 'custom', label: 'Custom', baseUrl: '', keyHint: 'API key')
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
            width: 400,
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
                      enabledBorder: const UnderlineInputBorder(
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
                    enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Sym.hairline)),
                  ),
                ),
                const SizedBox(height: 10),
                if (busy)
                  Row(children: [
                    const SizedBox(
                        width: 12,
                        height: 12,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: Sym.amberDim)),
                    const SizedBox(width: 8),
                    Text('checking the key…', style: Sym.mono(size: 10, color: Sym.inkDim)),
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
              child: Text('VALIDATE & SAVE', style: Sym.label(color: Sym.amber)),
            ),
          ],
        );
      },
    ),
  );
}

Widget _providerChip(String label, bool selected, VoidCallback onTap) => InkWell(
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
                  style: Sym.mono(size: 16, color: Sym.teal, weight: FontWeight.w600, spacing: 3),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('friends need this to connect',
                style: Sym.mono(size: 9.5, color: Sym.inkFaint)),
          ] else if (host?.error != null) ...[
            const SizedBox(height: 4),
            Text(host!.error!, style: Sym.mono(size: 9.5, color: Sym.danger), maxLines: 2),
          ],
          const SizedBox(height: 10),
          Text('PEERS', style: Sym.label()),
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
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.dns_outlined, size: 13, color: Sym.tealDim),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name,
                                        style: Sym.mono(
                                            size: 11.5, color: Sym.ink, weight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis),
                                    Text(
                                      '${p.address} · ${p.models.length} model${p.models.length == 1 ? '' : 's'}',
                                      style: Sym.mono(size: 9.5, color: Sym.inkFaint),
                                    ),
                                  ],
                                ),
                              ),
                              if (p.pairing)
                                const Icon(Icons.lock_outline, size: 12, color: Sym.inkFaint),
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

  void _connectToPeer(BuildContext context, WidgetRef ref, DiscoveredHost peer) {
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
          width: 360,
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
                  decoration: const InputDecoration(
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
                  style: Sym.mono(size: 11.5, color: Sym.ink, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pull.done || failed)
                GestureDetector(
                  onTap: () => ref.read(pullControllerProvider.notifier).dismiss(),
                  child: const Icon(Icons.close, size: 13, color: Sym.inkFaint),
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
              style: Sym.mono(size: 10, color: pull.done ? Sym.teal : Sym.inkDim),
            ),
          ] else
            Text(pull.error!, style: Sym.mono(size: 10, color: Sym.danger)),
        ],
      ),
    );
  }
}
