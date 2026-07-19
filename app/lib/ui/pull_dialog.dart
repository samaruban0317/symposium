import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/catalog.dart';
import '../state/app_state.dart';
import '../state/catalog_state.dart';
import '../state/device_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// The install browser: every model on ollama.com/library, searchable, with
/// one tap per size. Typing also works as a direct install for any
/// `model:tag` the search doesn't know. Progress shows in the sidebar so
/// this can close immediately.
class PullDialog extends ConsumerStatefulWidget {
  const PullDialog({super.key});

  @override
  ConsumerState<PullDialog> createState() => _PullDialogState();
}

class _PullDialogState extends ConsumerState<PullDialog> {
  final _ctrl = TextEditingController();
  String _query = '';
  String? _capFilter; // null = all; otherwise "vision" | "tools" | …

  static const _capFilters = ['vision', 'tools', 'thinking', 'embedding'];

  void _start(String name) {
    if (name.trim().isEmpty) return;
    ref.read(pullControllerProvider.notifier).start(name.trim());
    Navigator.pop(context);
  }

  List<CatalogEntry> _filter(List<CatalogEntry> all) {
    final q = _query.trim().toLowerCase();
    // Search the part before any ":tag" — "qwen2.5:7b" should still match.
    final bare = q.split(':').first;
    return [
      for (final e in all)
        if ((_capFilter == null || e.capabilities.contains(_capFilter)) &&
            (bare.isEmpty ||
                e.name.toLowerCase().contains(bare) ||
                e.description.toLowerCase().contains(bare)))
          e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final ramGb = ref.watch(deviceRamGbProvider).valueOrNull;
    final maxH = MediaQuery.sizeOf(context).height * 0.6;

    return AlertDialog(
      backgroundColor: Sym.surfaceRaised,
      title: Row(
        children: [
          Expanded(child: Text('Install a model', style: Sym.display(size: 20))),
          if (catalog.valueOrNull != null)
            Text(
              catalog.valueOrNull!.live
                  ? '${catalog.valueOrNull!.entries.length} models · live'
                  : 'offline catalog',
              style: Sym.mono(size: 9.5, color: Sym.inkFaint),
            ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth(context, 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ramGb == null
                  ? 'Downloads happen inside the app — no terminal needed.'
                  : 'this device has ${ramGb.toStringAsFixed(0)} GB RAM — '
                      'sizes are colored by what fits',
              style: Sym.mono(size: 11, color: Sym.inkDim),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: Sym.mono(size: 13, color: Sym.ink),
              onChanged: (v) => setState(() => _query = v),
              onSubmitted: _start,
              decoration: InputDecoration(
                hintText: 'search, or type any model:tag',
                hintStyle: Sym.mono(size: 12, color: Sym.inkFaint),
                prefixIcon: Icon(Icons.search, size: 16, color: Sym.inkFaint),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Sym.hairline),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // What-can-it-do filters: the fastest answer to "which of these
            // see images?"
            Wrap(
              spacing: 5,
              children: [
                for (final cap in [null, ..._capFilters])
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _capFilter = cap),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: _capFilter == cap ? Sym.amber : Sym.hairline),
                      ),
                      child: Text(
                        cap?.toUpperCase() ?? 'ALL',
                        style: Sym.label(
                            size: 8,
                            color: _capFilter == cap ? Sym.amber : Sym.inkDim),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH < 220 ? 220 : maxH),
              child: catalog.when(
                loading: () => Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Sym.amberDim),
                    ),
                  ),
                ),
                // catalogProvider never throws — it falls back instead.
                error: (e, _) => Text('$e', style: Sym.mono(size: 11)),
                data: (cat) {
                  final list = _filter(cat.entries);
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'nothing matches — press INSTALL to pull\n"${_ctrl.text.trim()}" as typed',
                        style: Sym.mono(size: 11, color: Sym.inkDim),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) => _CatalogTile(
                      entry: list[i],
                      deviceRamGb: ramGb,
                      onInstall: _start,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL', style: Sym.label()),
        ),
        TextButton(
          onPressed: () => _start(_ctrl.text),
          child: Text('INSTALL', style: Sym.label(color: Sym.amber)),
        ),
      ],
    );
  }
}

/// One library model: name + pulls, capability badges, description, and a
/// chip per size showing its RAM requirement — colored by whether it fits
/// this device. Tapping the row installs the default tag; a chip installs
/// that size.
class _CatalogTile extends StatelessWidget {
  final CatalogEntry entry;
  final double? deviceRamGb;
  final ValueChanged<String> onInstall;

  const _CatalogTile(
      {required this.entry, required this.deviceRamGb, required this.onInstall});

  /// fits comfortably → teal · tight squeeze → amber · won't fit → danger.
  Color _fitColor(ModelReqs? reqs) {
    if (reqs == null || deviceRamGb == null) return Sym.teal;
    if (reqs.ramGB <= deviceRamGb! * 0.75) return Sym.teal;
    if (reqs.ramGB <= deviceRamGb!) return Sym.amber;
    return Sym.danger;
  }

  Widget _sizeChip(String size, ModelReqs? reqs) {
    final color = _fitColor(reqs);
    final wontFit = deviceRamGb != null && reqs != null && reqs.ramGB > deviceRamGb!;
    return Tooltip(
      message: reqs == null
          ? 'install ${size.isEmpty ? 'this tag' : size}'
          : 'download ~${reqs.downloadLabel} · needs ~${reqs.ramLabel} RAM'
              '${wontFit ? '\nmore than this device has — will run very slowly if at all' : ''}',
      textStyle: Sym.mono(size: 10, color: Sym.ink),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => onInstall(entry.tagFor(size)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Text(
            reqs == null ? size : '$size · ${reqs.ramLabel}',
            style: Sym.mono(size: 10, color: color),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => onInstall(entry.name),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(entry.name,
                          style: Sym.mono(
                              size: 12.5, color: Sym.amber, weight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    for (final cap in entry.capabilities) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                              color: Sym.tealDim.withValues(alpha: 0.6)),
                        ),
                        child: Text(cap.toUpperCase(),
                            style: Sym.label(size: 7, color: Sym.tealDim)),
                      ),
                    ],
                    const Spacer(),
                    if (entry.pulls != null)
                      Text('${entry.pulls} pulls',
                          style: Sym.mono(size: 9.5, color: Sym.inkFaint)),
                    const SizedBox(width: 6),
                    Icon(Icons.download_outlined, size: 14, color: Sym.inkFaint),
                  ],
                ),
                if (entry.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(entry.description,
                      style: Sym.mono(size: 10.5, color: Sym.inkDim),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                if (entry.sizes.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final s in entry.sizes)
                        _sizeChip(s, ModelReqs.forSize(s)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
