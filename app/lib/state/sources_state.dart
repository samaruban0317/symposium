/// The sources layer: saved cloud providers (bring-your-own-API-key) and
/// their persistence.
///
/// Chapter-0's rule survives contact with the cloud because every big
/// provider now speaks the OpenAI dialect. The only genuinely new problems
/// are (a) where the key lives and (b) how auth rides along on requests.
/// (a) is `sources.json` via local_store. (b) is the [OllamaEngine.cloudAuth]
/// registry: we register `baseUrl → headers` once here, and every engine
/// anyone constructs from that bare URL — the global chat, an arena pane —
/// inherits the key and the cloud dialect with zero extra plumbing. The
/// endpoint string stays the whole contract.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ollama_engine.dart';
import '../models/source.dart';
import 'app_state.dart';
import 'local_store.dart';
import 'sources_contract.dart';

// ---------------------------------------------------------------------------
// Provider presets
// ---------------------------------------------------------------------------

class CloudPreset {
  final String id; // matches ModelSource.providerId
  final String label;
  final String baseUrl; // OpenAI-compatible root INCLUDING version segment
  final String keyHint; // what the key looks like, shown in the add dialog

  const CloudPreset({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.keyHint,
  });

  /// Provider-specific auth. Anthropic wants `x-api-key` + a version header
  /// for its native endpoints (model listing) and accepts Bearer on the
  /// OpenAI-compatible chat surface — sending all three covers both.
  Map<String, String> headersFor(String key) => switch (id) {
        'anthropic' => {
            'x-api-key': key,
            'anthropic-version': '2023-06-01',
            'Authorization': 'Bearer $key',
          },
        _ => {'Authorization': 'Bearer $key'},
      };

  /// Anthropic rejects a chat request that has no max_tokens at all.
  int? get defaultMaxTokens => id == 'anthropic' ? 4096 : null;
}

const kCloudPresets = [
  CloudPreset(
    id: 'openai',
    label: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    keyHint: 'sk-…',
  ),
  CloudPreset(
    id: 'gemini',
    label: 'Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    keyHint: 'AIza… (Google AI Studio key)',
  ),
  CloudPreset(
    id: 'anthropic',
    label: 'Anthropic',
    baseUrl: 'https://api.anthropic.com/v1',
    keyHint: 'sk-ant-…',
  ),
];

CloudPreset presetFor(String? providerId) => kCloudPresets.firstWhere(
      (p) => p.id == providerId,
      orElse: () => const CloudPreset(
          id: 'custom', label: 'Custom', baseUrl: '', keyHint: 'API key'),
    );

/// Headers a [ModelSource] needs on every request (used by engine_factory).
Map<String, String> cloudHeadersFor(ModelSource s) =>
    s.apiKey == null ? const {} : presetFor(s.providerId).headersFor(s.apiKey!);

// ---------------------------------------------------------------------------
// Persistence + registry
// ---------------------------------------------------------------------------

final sourcesRepoProvider = Provider<SourcesRepo>((ref) => SourcesRepo(ref));

/// Kicked off by the sidebar's first build; the UI just watches
/// [savedSourcesProvider] and never touches disk itself.
final sourcesLoadProvider =
    FutureProvider<void>((ref) => ref.read(sourcesRepoProvider).load());

class SourcesRepo {
  final Ref ref;
  SourcesRepo(this.ref);

  Future<void> load() async {
    final raw = await readData('sources.json');
    if (raw == null) return;
    try {
      final saved = [
        for (final j in jsonDecode(raw) as List)
          ModelSource.fromJson(j as Map<String, dynamic>),
      ];
      _apply(saved);
    } catch (_) {
      // A corrupt file should never brick the app — start with just local.
    }
  }

  List<ModelSource> get _saved => [
        for (final s in ref.read(savedSourcesProvider))
          if (s.id != kLocalSource.id) s,
      ];

  Future<void> addCloud({
    required CloudPreset preset,
    required String key,
    String? customBaseUrl,
    String? label,
  }) async {
    final base = (customBaseUrl ?? preset.baseUrl).replaceAll(RegExp(r'/+$'), '');
    final source = ModelSource(
      id: 'cloud-${DateTime.now().millisecondsSinceEpoch}',
      label: label ?? preset.label,
      kind: SourceKind.cloud,
      baseUrl: base,
      apiKey: key,
      providerId: preset.id,
    );
    await _persist([..._saved.where((s) => s.baseUrl != base), source]);
  }

  Future<void> updateKey(ModelSource source, String key) async =>
      _persist([for (final s in _saved) s.id == source.id ? s.copyWith(apiKey: key) : s]);

  Future<void> remove(ModelSource source) async {
    OllamaEngine.cloudAuth.remove(source.baseUrl);
    await _persist([for (final s in _saved) if (s.id != source.id) s]);
  }

  Future<void> _persist(List<ModelSource> saved) async {
    _apply(saved);
    await writeData('sources.json', const JsonEncoder.withIndent('  ')
        .convert([for (final s in saved) s.toJson()]));
    // If the active endpoint's auth just changed, rebuild the engine.
    ref.invalidate(modelsProvider);
    ref.invalidate(serverOnlineProvider);
  }

  void _apply(List<ModelSource> saved) {
    for (final s in saved) {
      if (s.kind == SourceKind.cloud && s.apiKey != null) {
        final preset = presetFor(s.providerId);
        OllamaEngine.cloudAuth[s.baseUrl] = CloudAuth(
          preset.headersFor(s.apiKey!),
          defaultMaxTokens: preset.defaultMaxTokens,
        );
      }
    }
    ref.read(savedSourcesProvider.notifier).state = [kLocalSource, ...saved];
  }

  /// Try the source for real: list its models. Throws with an actionable
  /// message (the engine maps 401/403 to "key rejected").
  Future<int> validate({
    required CloudPreset preset,
    required String key,
    String? customBaseUrl,
  }) async {
    final base = (customBaseUrl ?? preset.baseUrl).replaceAll(RegExp(r'/+$'), '');
    final engine =
        OllamaEngine(base, headers: preset.headersFor(key), openAiCompat: true);
    return (await engine.listModels()).length;
  }
}

// ---------------------------------------------------------------------------
// What is the app pointed at right now?
// ---------------------------------------------------------------------------

/// Resolves the global endpoint back to a saved source — so the sidebar can
/// show a cloud label and hide the download UI when the active thing has no
/// concept of "pulling" a model.
final activeSourceProvider = Provider<ModelSource>((ref) {
  final url = ref.watch(endpointProvider);
  final saved = ref.watch(savedSourcesProvider);
  for (final s in saved) {
    if (s.baseUrl == url) return s;
  }
  // A peer or hand-typed URL — synthesize an unsaved descriptor for it.
  return ModelSource(
    id: 'adhoc',
    label: url.replaceFirst(RegExp('^https?://'), ''),
    kind: SourceKind.peer,
    baseUrl: url,
  );
});
