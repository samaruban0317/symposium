/// Plain data classes. No Flutter imports here — these travel between
/// the engine layer and the UI and should stay framework-free.
library;

enum Role { user, assistant, system }

class ChatMessage {
  final Role role;
  final String content;
  final String? modelName; // which model produced an assistant message

  /// Attached images as base64 (no data-URI prefix). Only meaningful on user
  /// messages; vision models receive them as OpenAI image_url content parts.
  final List<String> images;

  /// An attached document: [docName] is shown in the UI, [docText] is the
  /// extracted text that rides along to the model but never clutters the
  /// visible transcript.
  final String? docName;
  final String? docText;

  const ChatMessage({
    required this.role,
    required this.content,
    this.modelName,
    this.images = const [],
    this.docName,
    this.docText,
  });

  ChatMessage copyWith({String? content}) => ChatMessage(
        role: role,
        content: content ?? this.content,
        modelName: modelName,
        images: images,
        docName: docName,
        docText: docText,
      );

  String get _roleWire => switch (role) {
        Role.user => 'user',
        Role.assistant => 'assistant',
        Role.system => 'system',
      };

  /// The model-facing text: typed text plus any document, clearly labeled so
  /// the model knows where the file starts.
  String get _wireText => docText == null
      ? content
      : '$content\n\n[Attached document: $docName]\n$docText';

  Map<String, dynamic> toOpenAi() => {
        'role': _roleWire,
        // Plain string normally; the multimodal parts array only when images
        // are attached, so text-only engines never see anything new.
        'content': images.isEmpty
            ? _wireText
            : [
                {'type': 'text', 'text': _wireText},
                for (final b64 in images)
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'data:image/jpeg;base64,$b64'},
                  },
              ],
      };

  // Disk format for conversation history — same role strings as the wire.
  Map<String, dynamic> toJson() => {
        'role': _roleWire,
        'content': content,
        if (modelName != null) 'model': modelName,
        if (images.isNotEmpty) 'images': images,
        if (docName != null) 'docName': docName,
        if (docText != null) 'docText': docText,
      };

  static ChatMessage fromJson(Map<String, dynamic> j) => ChatMessage(
        role: switch (j['role']) {
          'user' => Role.user,
          'system' => Role.system,
          _ => Role.assistant,
        },
        content: j['content'] as String? ?? '',
        modelName: j['model'] as String?,
        images: (j['images'] as List? ?? const []).cast<String>(),
        docName: j['docName'] as String?,
        docText: j['docText'] as String?,
      );
}

/// Sampling & steering knobs for the next request. Defaults match what the
/// server would assume if we sent nothing, so `isDefault` means the request
/// body carries no surprises and the chips row can stay empty.
class ChatParams {
  static const defaultTemperature = 0.7;
  static const defaultTopP = 1.0;

  final double temperature;
  final double topP;
  final int? maxTokens; // null = let the model run to its own limit
  final String systemPrompt; // '' = none

  const ChatParams({
    this.temperature = defaultTemperature,
    this.topP = defaultTopP,
    this.maxTokens,
    this.systemPrompt = '',
  });

  ChatParams copyWith({
    double? temperature,
    double? topP,
    int? maxTokens,
    bool clearMaxTokens = false,
    String? systemPrompt,
  }) =>
      ChatParams(
        temperature: temperature ?? this.temperature,
        topP: topP ?? this.topP,
        maxTokens: clearMaxTokens ? null : (maxTokens ?? this.maxTokens),
        systemPrompt: systemPrompt ?? this.systemPrompt,
      );

  bool get isDefault =>
      temperature == defaultTemperature &&
      topP == defaultTopP &&
      maxTokens == null &&
      systemPrompt.trim().isEmpty;
}

class ModelInfo {
  final String name;
  final int sizeBytes;
  final String? parameterSize; // e.g. "7.6B"
  final String? quantization; // e.g. "Q4_0"

  const ModelInfo({required this.name, required this.sizeBytes, this.parameterSize, this.quantization});

  String get sizeLabel {
    final gb = sizeBytes / (1024 * 1024 * 1024);
    return gb >= 1 ? '${gb.toStringAsFixed(1)} GB' : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

/// One progress line from a model download (Ollama `/api/pull` NDJSON stream).
class PullEvent {
  final String status;
  final int? total;
  final int? completed;
  final String? error;

  const PullEvent({required this.status, this.total, this.completed, this.error});

  double? get fraction =>
      (total != null && total! > 0 && completed != null) ? completed! / total! : null;
}
