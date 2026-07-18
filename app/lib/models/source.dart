/// The shared contract for "a place where models live". Frozen interface:
/// the sources layer (sidebar, persistence) and the persona studio both build
/// against this file — extend it additively, never reshape it.
///
/// Chapter-0 rule, now with three flavors:
///  - local  → your own engine        (base http://127.0.0.1:11434, Ollama paths)
///  - peer   → a friend's PC          (same, plus the pairing-code header)
///  - cloud  → a hosted API via key   (OpenAI-compatible root INCLUDING the
///             version segment, e.g. https://api.openai.com/v1 — every big
///             provider now speaks this dialect, which is why "add an API key"
///             costs one enum value instead of a new integration)
library;

enum SourceKind { local, peer, cloud }

class ModelSource {
  final String id; // stable key for persistence ('local', 'peer-…', 'cloud-…')
  final String label; // what the user sees: 'This device', 'DESKTOP-4F2', 'Gemini'
  final SourceKind kind;

  /// local/peer: engine root like http://192.168.1.42:11434 (engine appends
  /// /api/* and /v1/*). cloud: OpenAI-compatible root already containing the
  /// version segment (engine appends /chat/completions and /models).
  final String baseUrl;

  final String? apiKey; // cloud only — stored locally on this device
  final String? pairingCode; // peer only
  final String? providerId; // cloud only: 'openai' | 'gemini' | 'anthropic' | 'custom'

  const ModelSource({
    required this.id,
    required this.label,
    required this.kind,
    required this.baseUrl,
    this.apiKey,
    this.pairingCode,
    this.providerId,
  });

  ModelSource copyWith({String? label, String? baseUrl, String? apiKey, String? pairingCode}) =>
      ModelSource(
        id: id,
        label: label ?? this.label,
        kind: kind,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        pairingCode: pairingCode ?? this.pairingCode,
        providerId: providerId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'baseUrl': baseUrl,
        if (apiKey != null) 'apiKey': apiKey,
        if (pairingCode != null) 'pairingCode': pairingCode,
        if (providerId != null) 'providerId': providerId,
      };

  static ModelSource fromJson(Map<String, dynamic> j) => ModelSource(
        id: j['id'] as String,
        label: j['label'] as String,
        kind: SourceKind.values.byName(j['kind'] as String),
        baseUrl: j['baseUrl'] as String,
        apiKey: j['apiKey'] as String?,
        pairingCode: j['pairingCode'] as String?,
        providerId: j['providerId'] as String?,
      );
}

/// The always-present default: the engine on this machine.
const kLocalSource = ModelSource(
  id: 'local',
  label: 'This device',
  kind: SourceKind.local,
  baseUrl: 'http://127.0.0.1:11434',
);
