/// Plain data classes. No Flutter imports here — these travel between
/// the engine layer and the UI and should stay framework-free.
library;

enum Role { user, assistant, system }

class ChatMessage {
  final Role role;
  final String content;
  final String? modelName; // which model produced an assistant message

  const ChatMessage({required this.role, required this.content, this.modelName});

  ChatMessage copyWith({String? content}) =>
      ChatMessage(role: role, content: content ?? this.content, modelName: modelName);

  Map<String, dynamic> toOpenAi() => {
        'role': switch (role) {
          Role.user => 'user',
          Role.assistant => 'assistant',
          Role.system => 'system',
        },
        'content': content,
      };
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
