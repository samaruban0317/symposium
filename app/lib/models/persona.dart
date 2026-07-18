/// A persona is a portable "tuned mind": instructions + sampling knobs +
/// (optionally) a preferred source and model, refined in the studio's
/// edit-and-retest loop and shareable as a small JSON file. Framework-free,
/// like chat.dart — this travels between state, UI, and the clipboard.
library;

/// Bumped only when the export format changes shape incompatibly. Import
/// refuses files from the future rather than mis-reading them.
const kPersonaExportVersion = 1;
const kPersonaExportType = 'symposium_persona';

class Persona {
  final String id;
  final String name;

  /// One visible character (letter, symbol, emoji) — the persona's sigil.
  final String glyph;

  /// Index into the studio's accent palette; kept as an index so the palette
  /// can evolve without breaking saved/shared personas.
  final int accentIndex;

  /// The system prompt. The whole reason personas exist.
  final String instructions;

  final double temperature;
  final double topP;
  final int? maxTokens;

  /// Where this persona prefers to run. The source id is meaningful only on
  /// the machine that saved it (your friend's ids differ), so exports drop it
  /// but keep the model name, which is at least a good hint.
  final String? pinnedSourceId;
  final String? pinnedModel;

  /// Counts *applied* instruction versions — bumped when an edit is committed,
  /// not per keystroke — so test-chat answers can be stamped "r3" and the user
  /// can see exactly which wording produced which behavior.
  final int instructionsRevision;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Persona({
    required this.id,
    required this.name,
    required this.glyph,
    required this.accentIndex,
    required this.instructions,
    this.temperature = 0.7,
    this.topP = 1.0,
    this.maxTokens,
    this.pinnedSourceId,
    this.pinnedModel,
    this.instructionsRevision = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  static const _unset = Object();

  Persona copyWith({
    String? name,
    String? glyph,
    int? accentIndex,
    String? instructions,
    double? temperature,
    double? topP,
    Object? maxTokens = _unset,
    Object? pinnedSourceId = _unset,
    Object? pinnedModel = _unset,
    int? instructionsRevision,
    DateTime? updatedAt,
  }) =>
      Persona(
        id: id,
        name: name ?? this.name,
        glyph: glyph ?? this.glyph,
        accentIndex: accentIndex ?? this.accentIndex,
        instructions: instructions ?? this.instructions,
        temperature: temperature ?? this.temperature,
        topP: topP ?? this.topP,
        maxTokens: identical(maxTokens, _unset) ? this.maxTokens : maxTokens as int?,
        pinnedSourceId: identical(pinnedSourceId, _unset)
            ? this.pinnedSourceId
            : pinnedSourceId as String?,
        pinnedModel:
            identical(pinnedModel, _unset) ? this.pinnedModel : pinnedModel as String?,
        instructionsRevision: instructionsRevision ?? this.instructionsRevision,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'glyph': glyph,
        'accentIndex': accentIndex,
        'instructions': instructions,
        'temperature': temperature,
        'topP': topP,
        if (maxTokens != null) 'maxTokens': maxTokens,
        if (pinnedSourceId != null) 'pinnedSourceId': pinnedSourceId,
        if (pinnedModel != null) 'pinnedModel': pinnedModel,
        'instructionsRevision': instructionsRevision,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Persona fromJson(Map<String, dynamic> j) => Persona(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Unnamed',
        glyph: j['glyph'] as String? ?? '✶',
        accentIndex: (j['accentIndex'] as num?)?.toInt() ?? 0,
        instructions: j['instructions'] as String? ?? '',
        temperature: (j['temperature'] as num?)?.toDouble() ?? 0.7,
        topP: (j['topP'] as num?)?.toDouble() ?? 1.0,
        maxTokens: (j['maxTokens'] as num?)?.toInt(),
        pinnedSourceId: j['pinnedSourceId'] as String?,
        pinnedModel: j['pinnedModel'] as String?,
        instructionsRevision: (j['instructionsRevision'] as num?)?.toInt() ?? 1,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );

  /// The shareable wrapper: `{"type": "symposium_persona", "version": 1,
  /// "persona": {…}}`. Drops the machine-local pinned source id.
  Map<String, dynamic> toExport() {
    final body = toJson()..remove('pinnedSourceId');
    return {'type': kPersonaExportType, 'version': kPersonaExportVersion, 'persona': body};
  }

  /// Parses an exported persona. Throws [FormatException] with a
  /// human-readable message on anything that isn't one of ours.
  static Persona fromExport(Map<String, dynamic> j) {
    if (j['type'] != kPersonaExportType) {
      throw const FormatException('not a Symposium persona file');
    }
    final version = (j['version'] as num?)?.toInt() ?? 0;
    if (version > kPersonaExportVersion) {
      throw FormatException('persona was exported by a newer Symposium (v$version)');
    }
    final body = j['persona'];
    if (body is! Map<String, dynamic>) {
      throw const FormatException('persona payload is missing');
    }
    return fromJson(body);
  }
}
