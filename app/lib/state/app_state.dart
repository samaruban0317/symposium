import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ollama_engine.dart';
import '../models/chat.dart';
import '../net/protocol.dart';

/// Where the app points — an endpoint is just a base URL. It can be typed by
/// hand or filled in by tapping a discovered peer in the sidebar.
final endpointProvider = StateProvider<String>((ref) => 'http://127.0.0.1:11434');

/// Set when the endpoint is another PC's Symposium host proxy; sent as a
/// header on every request. Null when talking to your own local engine.
final pairingCodeProvider = StateProvider<String?>((ref) => null);

final engineProvider = Provider<OllamaEngine>((ref) {
  final code = ref.watch(pairingCodeProvider);
  return OllamaEngine(
    ref.watch(endpointProvider),
    headers: code == null ? const {} : {kPairingHeader: code},
  );
});

final serverOnlineProvider = FutureProvider<bool>(
  (ref) => ref.watch(engineProvider).ping(),
);

final modelsProvider = FutureProvider<List<ModelInfo>>(
  (ref) => ref.watch(engineProvider).listModels(),
);

final selectedModelProvider = StateProvider<String?>((ref) {
  final models = ref.watch(modelsProvider).valueOrNull;
  return models != null && models.isNotEmpty ? models.first.name : null;
});

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------

class ChatState {
  final List<ChatMessage> messages;
  final bool isStreaming;
  final double tokPerSec;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.tokPerSec = 0,
    this.error,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    double? tokPerSec,
    String? error,
    bool clearError = false,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        tokPerSec: tokPerSec ?? this.tokPerSec,
        error: clearError ? null : (error ?? this.error),
      );
}

class ChatController extends StateNotifier<ChatState> {
  final Ref ref;
  ChatStream? _active;

  ChatController(this.ref) : super(const ChatState());

  Future<void> send(String text) async {
    final model = ref.read(selectedModelProvider);
    if (model == null || state.isStreaming || text.trim().isEmpty) return;

    final engine = ref.read(engineProvider);
    final history = [
      ...state.messages,
      ChatMessage(role: Role.user, content: text.trim()),
    ];
    state = state.copyWith(
      messages: [
        ...history,
        ChatMessage(role: Role.assistant, content: '', modelName: model),
      ],
      isStreaming: true,
      tokPerSec: 0,
      clearError: true,
    );

    final stopwatch = Stopwatch()..start();
    var chunks = 0;
    final chat = engine.chat(model: model, messages: history);
    _active = chat;

    try {
      await for (final delta in chat.deltas) {
        chunks++;
        final msgs = [...state.messages];
        final last = msgs.last;
        msgs[msgs.length - 1] = last.copyWith(content: last.content + delta);
        final secs = stopwatch.elapsedMilliseconds / 1000;
        state = state.copyWith(
          messages: msgs,
          // Each SSE chunk carries roughly one token, so chunks/sec ≈ tok/s.
          tokPerSec: secs > 0.2 ? chunks / secs : 0,
        );
      }
    } catch (e) {
      state = state.copyWith(error: '$e');
    } finally {
      _active = null;
      // Drop an assistant bubble that never received any content.
      final msgs = [...state.messages];
      if (msgs.isNotEmpty && msgs.last.role == Role.assistant && msgs.last.content.isEmpty) {
        msgs.removeLast();
      }
      state = state.copyWith(messages: msgs, isStreaming: false);
    }
  }

  void stop() => _active?.cancel();

  void clear() {
    stop();
    state = const ChatState();
  }
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>((ref) => ChatController(ref));

// ---------------------------------------------------------------------------
// Model downloads (in-app install — no terminal)
// ---------------------------------------------------------------------------

class PullState {
  final String model;
  final String status;
  final double? fraction; // null = indeterminate
  final String? error;
  final bool done;

  const PullState({
    required this.model,
    this.status = 'starting…',
    this.fraction,
    this.error,
    this.done = false,
  });

  PullState copyWith({String? status, double? fraction, String? error, bool? done}) =>
      PullState(
        model: model,
        status: status ?? this.status,
        fraction: fraction ?? this.fraction,
        error: error ?? this.error,
        done: done ?? this.done,
      );
}

class PullController extends StateNotifier<PullState?> {
  final Ref ref;
  PullController(this.ref) : super(null);

  Future<void> start(String model) async {
    if (state != null && !(state!.done || state!.error != null)) return; // one at a time
    state = PullState(model: model);
    try {
      await for (final ev in ref.read(engineProvider).pull(model)) {
        if (ev.error != null) {
          state = state!.copyWith(error: ev.error);
          return;
        }
        state = state!.copyWith(status: ev.status, fraction: ev.fraction);
      }
      state = state!.copyWith(status: 'ready', fraction: 1, done: true);
      ref.invalidate(modelsProvider); // refresh the sidebar list
    } catch (e) {
      state = state!.copyWith(error: '$e');
    }
  }

  void dismiss() => state = null;
}

final pullControllerProvider =
    StateNotifierProvider<PullController, PullState?>((ref) => PullController(ref));
