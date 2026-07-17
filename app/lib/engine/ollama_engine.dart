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
  /// to another PC's Symposium host proxy.
  final Map<String, String> headers;

  OllamaEngine(this.baseUrl, {this.headers = const {}});

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  /// True if a server is answering at [baseUrl].
  Future<bool> ping() async {
    try {
      final res = await http
          .get(_u('/api/version'), headers: headers)
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<ModelInfo>> listModels() async {
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

  /// Download a model by name ("qwen2.5:0.5b"). Emits progress as it arrives.
  /// Ollama streams newline-delimited JSON: one status object per line.
  Stream<PullEvent> pull(String model) async* {
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
  }) {
    final client = http.Client();
    final controller = StreamController<String>();

    () async {
      try {
        final req = http.Request('POST', _u('/v1/chat/completions'))
          ..headers['Content-Type'] = 'application/json'
          ..headers.addAll(headers)
          ..body = jsonEncode({
            'model': model,
            'stream': true,
            'temperature': temperature,
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
