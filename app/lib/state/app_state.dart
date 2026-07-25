import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../engine/ollama_engine.dart';
import '../models/chat.dart';
import '../models/conversation.dart';
import '../net/protocol.dart';
import 'attachments_state.dart';
import 'auth_state.dart';
import 'history_state.dart';

/// Where the app points — an endpoint is just a base URL. It can be typed by
/// hand or filled in by tapping a discovered peer in the sidebar.
final endpointProvider = StateProvider<String>((ref) => 'http://127.0.0.1:11434');

/// Set when the endpoint is another PC's Symposium host proxy; sent as a
/// header on every request. Null when talking to your own local engine.
final pairingCodeProvider = StateProvider<String?>((ref) => null);

/// Set when you connect to a host AS ITS ADMIN — sent as the admin header so
/// management calls (pull / delete / create) are allowed. Null for viewers
/// (friends), whose management calls the host answers with 403. Harmless on
/// chat/read requests, which the host never gates on it.
final adminTokenProvider = StateProvider<String?>((ref) => null);

final engineProvider = Provider<OllamaEngine>((ref) {
  final code = ref.watch(pairingCodeProvider);
  final admin = ref.watch(adminTokenProvider);
  // When signed in, ride the Supabase JWT along as a Bearer token so a host
  // that trusts our Supabase upgrades us from guest to the student tier. It's
  // harmless on the local engine and on hosts that don't enable student tier.
  final jwt = ref.watch(studentJwtProvider);
  return OllamaEngine(
    ref.watch(endpointProvider),
    headers: {
      if (code != null) kPairingHeader: code,
      if (admin != null) kAdminHeader: admin,
      if (jwt != null) 'Authorization': 'Bearer $jwt',
    },
  );
});

final serverOnlineProvider = FutureProvider<bool>(
  (ref) => ref.watch(engineProvider).ping(),
);

final modelsProvider = FutureProvider<List<ModelInfo>>(
  (ref) => ref.watch(engineProvider).listModels(),
);

/// The models installed on THIS machine's local engine, regardless of where
/// the client is currently pointed. Used by the host-controls "default model"
/// picker so an admin sharing their PC chooses from what they actually have.
final localModelsProvider = FutureProvider<List<ModelInfo>>(
  (ref) => OllamaEngine('http://127.0.0.1:11434').listModels(),
);

/// What a paired host tells a joining client about itself: its resolved tier,
/// the guest small-model allowlist, and — the key bit — the `default_model`
/// the host admin pinned. Only meaningful when connected to a host (i.e. a
/// pairing code is set); null when talking to the local engine.
class HostConfig {
  final String tier;
  final List<String> smallModels;
  final String defaultModel;

  const HostConfig({
    this.tier = 'guest',
    this.smallModels = const [],
    this.defaultModel = '',
  });

  /// True if [model] is one a guest may chat with (case-insensitive prefix
  /// match — mirrors the host's own allowlist check). An empty allowlist means
  /// "no restriction advertised", so everything passes.
  bool guestAllows(String model) {
    if (smallModels.isEmpty) return true;
    final m = model.toLowerCase();
    return smallModels.any((a) => m.startsWith(a.toLowerCase()));
  }
}

/// Fetched from `GET <host>/v1/mobile/config` whenever we're paired to a host.
/// Null (no request) when on the local engine. Failures resolve to null rather
/// than throwing — the client just falls back to its own model default.
final hostConfigProvider = FutureProvider<HostConfig?>((ref) async {
  final code = ref.watch(pairingCodeProvider);
  if (code == null) return null; // local engine — no host to ask
  final base = ref.watch(endpointProvider);
  final admin = ref.watch(adminTokenProvider);
  try {
    final res = await http.get(
      Uri.parse('$base/v1/mobile/config'),
      headers: {
        kPairingHeader: code,
        if (admin != null) kAdminHeader: admin,
      },
    ).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return HostConfig(
      tier: j['tier'] as String? ?? 'guest',
      smallModels:
          (j['small_models'] as List? ?? const []).map((e) => '$e').toList(),
      defaultModel: j['default_model'] as String? ?? '',
    );
  } catch (_) {
    return null;
  }
});

/// The active model. Defaulting rules, in order:
///   1. The host admin's pinned `default_model`, if it's actually available.
///   2. When we're a guest, the first model the host's allowlist permits — so
///      a phone never lands on a model it can't chat with (the silent-403 dead
///      end this fixes).
///   3. Otherwise the first available model.
/// Re-derived when the model list or host config changes (i.e. on a fresh
/// join); a manual pick via the sidebar overrides until then.
final selectedModelProvider = StateProvider<String?>((ref) {
  final models = ref.watch(modelsProvider).valueOrNull;
  if (models == null || models.isEmpty) return null;
  final names = models.map((m) => m.name).toList();
  final cfg = ref.watch(hostConfigProvider).valueOrNull;

  if (cfg != null) {
    // 1. Honour the admin's pin when the model is present on the host.
    if (cfg.defaultModel.isNotEmpty && names.contains(cfg.defaultModel)) {
      return cfg.defaultModel;
    }
    // 2. Guests: pick the first model they're actually allowed to use.
    if (cfg.tier == 'guest') {
      final allowed = names.where(cfg.guestAllows);
      if (allowed.isNotEmpty) return allowed.first;
    }
  }
  // 3. Fall back to the first model.
  return names.first;
});

/// Sampling knobs + system prompt, edited in the parameter lab. Read at send
/// time, so changing them mid-conversation affects only the next request.
final chatParamsProvider = StateProvider<ChatParams>((ref) => const ChatParams());

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
  String? _conversationId; // null until the first exchange is saved

  ChatController(this.ref) : super(const ChatState());

  Future<void> send(String text) async {
    final pending = ref.read(attachmentsProvider);
    if (state.isStreaming || (text.trim().isEmpty && pending.isEmpty)) return;
    ref.read(attachmentsProvider.notifier).clear();
    await _run([
      ...state.messages,
      ChatMessage(
        role: Role.user,
        content: text.trim(),
        images: pending.images,
        docName: pending.docName,
        docText: pending.docText,
      ),
    ]);
  }

  /// Drop the trailing assistant reply (if any) and answer again — same
  /// history, current params, so it doubles as "retry with new settings".
  Future<void> regenerate() async {
    if (state.isStreaming || state.messages.isEmpty) return;
    final history = [...state.messages];
    if (history.last.role == Role.assistant) history.removeLast();
    if (history.isEmpty) return;
    await _run(history);
  }

  /// Rewrite the user message at [index]; everything after it is discarded
  /// and the conversation continues from the edited text.
  Future<void> editAndResend(int index, String newText) async {
    if (state.isStreaming || newText.trim().isEmpty) return;
    if (index < 0 || index >= state.messages.length) return;
    if (state.messages[index].role != Role.user) return;
    await _run([
      ...state.messages.sublist(0, index),
      ChatMessage(role: Role.user, content: newText.trim()),
    ]);
  }

  /// Start over from a prefix of the transcript: keep everything up to and
  /// including [index], forget the rest. The kept history seeds what is
  /// effectively a new conversation.
  void forkFrom(int index) {
    if (index < 0 || index >= state.messages.length) return;
    stop();
    // A fork is a new conversation — the original stays intact in history.
    _conversationId = null;
    ref.read(activeConversationIdProvider.notifier).state = null;
    state = ChatState(messages: state.messages.sublist(0, index + 1));
  }

  Future<void> _run(List<ChatMessage> history) async {
    final model = ref.read(selectedModelProvider);
    if (model == null) return;

    final engine = ref.read(engineProvider);
    final params = ref.read(chatParamsProvider);
    // The system prompt lives outside the visible transcript — prepended per
    // request, so editing it later re-steers the whole conversation.
    final wire = [
      if (params.systemPrompt.trim().isNotEmpty)
        ChatMessage(role: Role.system, content: params.systemPrompt.trim()),
      ...history,
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
    final chat = engine.chat(
      model: model,
      messages: wire,
      temperature: params.temperature,
      topP: params.topP == ChatParams.defaultTopP ? null : params.topP,
      maxTokens: params.maxTokens,
    );
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
      await _snapshot();
    }
  }

  /// Persist the transcript to history. Runs after every exchange (success,
  /// error, or stop), so the sidebar list is always current.
  Future<void> _snapshot() async {
    final msgs = state.messages;
    if (msgs.isEmpty) return;
    final id = _conversationId ??=
        'conv-${DateTime.now().millisecondsSinceEpoch}';
    ref.read(activeConversationIdProvider.notifier).state = id;
    await ref.read(historyRepoProvider).upsert(Conversation(
          id: id,
          title: Conversation.titleFrom(msgs),
          messages: msgs,
          updatedAt: DateTime.now(),
        ));
  }

  /// Load a saved conversation into the chat tab; new messages keep
  /// appending to the same history entry.
  void open(Conversation c) {
    stop();
    _conversationId = c.id;
    ref.read(activeConversationIdProvider.notifier).state = c.id;
    state = ChatState(messages: c.messages);
  }

  /// Start fresh. The previous conversation stays in history untouched.
  void newConversation() {
    stop();
    _conversationId = null;
    ref.read(activeConversationIdProvider.notifier).state = null;
    state = const ChatState();
  }

  void stop() => _active?.cancel();

  void clear() => newConversation();
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
