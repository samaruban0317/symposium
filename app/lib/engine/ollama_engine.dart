import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat.dart';

/// The ONLY file that knows how to talk to a model server.
///
/// Two protocols are used deliberately:
///  - Management (list models, pull with progress) → Ollama's native REST API,
///    because the OpenAI-compatible surface has no notion of downloads.
///  - Chat → the OpenAI-compatible `/v1/chat/completions` SSE stream, because that
///    is the de-facto standard every engine speaks (Ollama, llama.cpp's
///    llama-server, vLLM, LM Studio…). Phase 2 points this same code at another
///    PC's URL and nothing else changes.
class OllamaEngine {
  final String baseUrl; // e.g. http://127.0.0.1:11434

  /// Extra headers on every request — carries the pairing code when talking
  /// to another PC's Symposium host proxy, or Bearer auth for a cloud API.
  final Map<String, String> headers;

  /// Cloud providers (OpenAI, Gemini, Anthropic) speak the SAME chat dialect,
  /// but their base URL already contains the version segment and they have no
  /// Ollama management API. When true: chat is `$base/chat/completions`,
  /// listing is GET `$base/models` (OpenAI `{data:[{id}]}` shape), and pull
  /// is unavailable.
  final bool openAiCompat;

  /// baseUrl → auth for saved cloud sources, populated by the sources layer.
  /// Exists so call sites that build an engine from a bare URL (the arena
  /// panes) inherit cloud auth + dialect without new plumbing — the endpoint
  /// string stays the whole contract, per chapter 0.
  static final Map<String, CloudAuth> cloudAuth = {};

  OllamaEngine(String baseUrl, {Map<String, String> headers = const {}, bool? openAiCompat})
      : baseUrl = baseUrl,
        headers = _withCloudAuth(baseUrl, headers),
        openAiCompat = openAiCompat ?? cloudAuth.containsKey(baseUrl);

  static Map<String, String> _withCloudAuth(String baseUrl, Map<String, String> given) {
    final auth = cloudAuth[baseUrl];
    if (auth == null) return given;
    return {...auth.headers, ...given}; // explicit headers win
  }

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  /// True if a server is answering at [baseUrl]. For cloud sources a 401/403
  /// still means "online" — the key problem surfaces in [listModels] where we
  /// can say something actionable.
  Future<bool> ping() async {
    try {
      final res = await http
          .get(_u(openAiCompat ? '/models' : '/api/version'), headers: headers)
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200 || res.statusCode == 401 || res.statusCode == 403;
    } catch (_) {
      return false;
    }
  }

  Future<List<ModelInfo>> listModels() async {
    if (openAiCompat) return _listModelsOpenAi();
    final res =
        await http.get(_u('/api/tags'), headers: headers).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception('Server answered ${res.statusCode} when listing models');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final models = (body['models'] as List? ?? []);
    return models.map((m) {
      final details = m['details'] as Map<String, dynamic>? ?? {};
      return ModelInfo(
        name: m['name'] as String,
        sizeBytes: (m['size'] as num?)?.toInt() ?? 0,
        parameterSize: details['parameter_size'] as String?,
        quantization: details['quantization_level'] as String?,
      );
    }).toList();
  }

  /// GET `$base/models` — the OpenAI shape `{data:[{id: "..."}]}`. Anthropic's
  /// native list happens to match (`data[].id`), so one parser covers all
  /// three providers. Cloud models have no local size/quantization.
  Future<List<ModelInfo>> _listModelsOpenAi() async {
    final res = await http
        .get(_u('/models'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('API key rejected (HTTP ${res.statusCode}) — check the key');
    }
    if (res.statusCode != 200) {
      throw Exception('Provider answered ${res.statusCode} when listing models');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final models = (body['data'] as List? ?? []);
    return [
      for (final m in models)
        if (m['id'] is String) ModelInfo(name: m['id'] as String, sizeBytes: 0),
    ];
  }

  /// Download a model by name ("qwen2.5:0.5b"). Emits progress as it arrives.
  /// Ollama streams newline-delimited JSON: one status object per line.
  Stream<PullEvent> pull(String model) async* {
    if (openAiCompat) {
      throw StateError('Cloud providers host their own models — nothing to download.');
    }
    final client = http.Client();
    try {
      final req = http.Request('POST', _u('/api/pull'))
        ..headers['Content-Type'] = 'application/json'
        ..headers.addAll(headers)
        ..body = jsonEncode({'model': model});
      final res = await client.send(req);
      if (res.statusCode != 200) {
        final text = await res.stream.bytesToString();
        throw Exception('Pull failed (${res.statusCode}): $text');
      }
      await for (final line in res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final j = jsonDecode(line) as Map<String, dynamic>;
        yield PullEvent(
          status: j['status'] as String? ?? '',
          total: (j['total'] as num?)?.toInt(),
          completed: (j['completed'] as num?)?.toInt(),
          error: j['error'] as String?,
        );
      }
    } finally {
      client.close();
    }
  }

  /// Stream a chat completion. Yields content deltas (token pieces).
  /// Closing the returned [ChatStream.cancel] aborts generation.
  ChatStream chat({
    required String model,
    required List<ChatMessage> messages,
    double temperature = 0.7,
    double? topP,
    int? maxTokens,
  }) {
    final client = http.Client();
    final controller = StreamController<String>();

    // Cloud bases already contain the version segment; Ollama's does not.
    final chatPath = openAiCompat ? '/chat/completions' : '/v1/chat/completions';
    // Anthropic requires max_tokens; newer Anthropic models reject temperature.
    // So for cloud: only send temperature when the user moved it off default,
    // and fall back to the provider's default token cap when none was chosen.
    final effectiveMaxTokens =
        maxTokens ?? (openAiCompat ? cloudAuth[baseUrl]?.defaultMaxTokens : null);
    final sendTemperature = !openAiCompat || temperature != 0.7;

    () async {
      try {
        final req = http.Request('POST', _u(chatPath))
          ..headers['Content-Type'] = 'application/json'
          ..headers.addAll(headers)
          ..body = jsonEncode({
            'model': model,
            'stream': true,
            if (sendTemperature) 'temperature': temperature,
            // Only sent when set — a body without these keys behaves exactly
            // as before, so older engines see nothing new.
            if (topP != null) 'top_p': topP,
            if (effectiveMaxTokens != null) 'max_tokens': effectiveMaxTokens,
            'messages': messages.map((m) => m.toOpenAi()).toList(),
          });
        final res = await client.send(req);
        if (res.statusCode != 200) {
          final text = await res.stream.bytesToString();
          throw Exception('Chat failed (${res.statusCode}): $text');
        }
        // Server-Sent Events: lines of `data: {json}` ending with `data: [DONE]`.
        await for (final line in res.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload == '[DONE]') break;
          final j = jsonDecode(payload) as Map<String, dynamic>;
          final delta = j['choices']?[0]?['delta']?['content'] as String?;
          if (delta != null && delta.isNotEmpty) controller.add(delta);
        }
        await controller.close();
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
      } finally {
        client.close();
      }
    }();

    return ChatStream(controller.stream, () => client.close());
  }
}

/// A cancellable stream of content deltas.
class ChatStream {
  final Stream<String> deltas;
  final void Function() cancel;
  ChatStream(this.deltas, this.cancel);
}

/// Auth + dialect quirks for one cloud base URL, registered by the sources
/// layer into [OllamaEngine.cloudAuth].
class CloudAuth {
  final Map<String, String> headers;

  /// Some providers (Anthropic) reject a chat request without max_tokens.
  /// Used only when the caller didn't set one explicitly.
  final int? defaultMaxTokens;

  const CloudAuth(this.headers, {this.defaultMaxTokens});
}
