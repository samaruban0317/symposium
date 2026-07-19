import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/source.dart';
import '../../net/protocol.dart';
import '../../state/arena_state.dart';
import '../../state/net_state.dart';
import '../../state/sources_contract.dart';
import '../../theme.dart';

/// Dialog that binds one arena pane to a source: this device's engine, a
/// discovered LAN peer, or a hand-typed address. Mirrors the sidebar's
/// connect flows, but writes to ONE pane instead of the global endpoint.
void showPanePicker(BuildContext context, ArenaSide side) {
  showDialog<void>(
    context: context,
    builder: (_) => _PanePickerDialog(side: side),
  );
}

class _PanePickerDialog extends ConsumerStatefulWidget {
  final ArenaSide side;
  const _PanePickerDialog({required this.side});

  @override
  ConsumerState<_PanePickerDialog> createState() => _PanePickerDialogState();
}

class _PanePickerDialogState extends ConsumerState<_PanePickerDialog> {
  /// Peer waiting on its 6-digit code; null shows the source list.
  DiscoveredHost? _codeFor;
  final _code = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    _url.dispose();
    super.dispose();
  }

  void _bind({required String endpoint, String? pairingCode, required String name}) {
    ref.read(paneProvider(widget.side).notifier).setSource(
        endpoint: endpoint, pairingCode: pairingCode, sourceName: name);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.side == ArenaSide.left ? 'Left speaker' : 'Right speaker';
    return AlertDialog(
      backgroundColor: Sym.surfaceRaised,
      title: Text(title, style: Sym.display(size: 20)),
      content: SizedBox(
        width: 380,
        child: _codeFor == null ? _sourceList() : _codeEntry(_codeFor!),
      ),
      actions: [
        if (_codeFor != null)
          TextButton(
            onPressed: () => setState(() => _codeFor = null),
            child: Text('BACK', style: Sym.label()),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL', style: Sym.label()),
        ),
        if (_codeFor != null)
          TextButton(
            onPressed: () => _joinPeer(_codeFor!),
            child: Text('JOIN', style: Sym.label(color: Sym.amber)),
          ),
      ],
    );
  }

  Widget _sourceList() {
    final peers = ref.watch(discoveredHostsProvider).valueOrNull ?? const [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('THIS DEVICE', style: Sym.label(size: 9)),
        const SizedBox(height: 4),
        _tile(
          icon: Icons.computer_outlined,
          title: 'local engine',
          subtitle: '127.0.0.1:11434',
          onTap: () => _bind(
              endpoint: 'http://127.0.0.1:11434', name: 'this device'),
        ),
        const SizedBox(height: 14),
        Text('PEERS', style: Sym.label(size: 9)),
        const SizedBox(height: 4),
        if (peers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('listening for hosts…',
                style: Sym.mono(size: 10, color: Sym.inkFaint)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in peers)
                  _tile(
                    icon: Icons.dns_outlined,
                    title: p.name,
                    subtitle:
                        '${p.address} · ${p.models.length} model${p.models.length == 1 ? '' : 's'}',
                    trailing: p.pairing
                        ? Icon(Icons.lock_outline,
                            size: 12, color: Sym.inkFaint)
                        : null,
                    onTap: () {
                      if (p.pairing) {
                        setState(() => _codeFor = p);
                      } else {
                        _bind(endpoint: p.baseUrl, name: p.name);
                      }
                    },
                  ),
              ],
            ),
          ),
        // Saved cloud providers work here too — auth rides on the URL via the
        // engine-level registry, so a pane can duel your local model against
        // GPT or Gemini with no extra plumbing.
        ...(() {
          final clouds = [
            for (final s in ref.watch(savedSourcesProvider))
              if (s.kind == SourceKind.cloud) s,
          ];
          if (clouds.isEmpty) return const <Widget>[];
          return <Widget>[
            const SizedBox(height: 14),
            Text('CLOUD', style: Sym.label(size: 9)),
            const SizedBox(height: 4),
            for (final s in clouds)
              _tile(
                icon: Icons.cloud_outlined,
                title: s.label,
                subtitle: s.baseUrl.replaceFirst(RegExp('^https?://'), ''),
                onTap: () => _bind(endpoint: s.baseUrl, name: s.label),
              ),
          ];
        })(),
        const SizedBox(height: 14),
        Text('CUSTOM ADDRESS', style: Sym.label(size: 9)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _url,
                style: Sym.mono(size: 12, color: Sym.ink),
                onSubmitted: (_) => _connectCustom(),
                decoration: InputDecoration(
                  hintText: 'http://192.168.1.42:11434',
                  hintStyle: Sym.mono(size: 12, color: Sym.inkFaint),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Sym.hairline),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: _connectCustom,
              child: Text('CONNECT', style: Sym.label(color: Sym.amber, size: 9)),
            ),
          ],
        ),
      ],
    );
  }

  void _connectCustom() {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    _bind(
      endpoint: url,
      name: url.replaceFirst(RegExp('^https?://'), ''),
    );
  }

  Widget _codeEntry(DiscoveredHost peer) {
    return Column(
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
        Text('Enter the 6-digit code shown on ${peer.name}:',
            style: Sym.mono(size: 11, color: Sym.inkDim)),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          autofocus: true,
          maxLength: 6,
          style: Sym.mono(size: 18, color: Sym.teal, spacing: 4),
          onSubmitted: (_) => _joinPeer(peer),
          decoration: InputDecoration(
            counterText: '',
            hintText: '······',
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Sym.hairline),
            ),
          ),
        ),
      ],
    );
  }

  void _joinPeer(DiscoveredHost peer) {
    if (peer.pairing && _code.text.trim().length != 6) return;
    _bind(
      endpoint: peer.baseUrl,
      pairingCode: peer.pairing ? _code.text.trim() : null,
      name: peer.name,
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 13, color: Sym.tealDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Sym.mono(
                              size: 11.5, color: Sym.ink, weight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                      Text(subtitle,
                          style: Sym.mono(size: 9.5, color: Sym.inkFaint)),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      );
}

/// Small dialog listing the pane's models; tap to switch speakers.
void showPaneModelPicker(BuildContext context, ArenaSide side) {
  showDialog<void>(
    context: context,
    builder: (_) => Consumer(
      builder: (ctx, ref, __) {
        final pane = ref.watch(paneProvider(side));
        return AlertDialog(
          backgroundColor: Sym.surfaceRaised,
          title: Text('Choose a model', style: Sym.display(size: 20)),
          content: SizedBox(
            width: 340,
            child: pane.models.isEmpty
                ? Text(
                    pane.online
                        ? 'No models on this endpoint yet.'
                        : 'Endpoint is offline.',
                    style: Sym.mono(size: 11, color: Sym.inkDim),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final m in pane.models)
                          Material(
                            color: m.name == pane.model
                                ? Sym.surface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () {
                                ref
                                    .read(paneProvider(side).notifier)
                                    .selectModel(m.name);
                                Navigator.pop(ctx);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 9),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.name,
                                        style: Sym.mono(
                                            size: 12.5,
                                            color: m.name == pane.model
                                                ? Sym.ink
                                                : Sym.inkDim,
                                            weight: m.name == pane.model
                                                ? FontWeight.w600
                                                : FontWeight.w400),
                                        overflow: TextOverflow.ellipsis),
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
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('CLOSE', style: Sym.label()),
            ),
          ],
        );
      },
    ),
  );
}
