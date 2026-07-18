/// Phase 3 — the arena. Two independent panes, each pointing at its own
/// endpoint (your engine, a friend's PC, anything OpenAI-compatible) with its
/// own model and its own conversation. Everything lives here, NOT in
/// app_state.dart, so the phase-1/2 files stay untouched: the arena is a
/// second consumer of the same engine layer, which is the whole architectural
/// bet — "every model source is just a URL".
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ollama_engine.dart';
import '../models/chat.dart';
import '../net/protocol.dart';

/// Which surface the home screen shows. Lives here rather than app_state so
/// phase 3 stays purely additive.
enum HomeTab { chat, arena, studio }

final homeTabProvider = StateProvider<HomeTab>((_) => HomeTab.chat);

enum ArenaSide { left, right }

enum ArenaMode {
  /// One shared composer; the prompt races on both panes at once.
  duel,

  /// Each pane is its own little chat with its own composer.
  independent,
}

// ---------------------------------------------------------------------------
// One pane = endpoint + model + conversation
// ---------------------------------------------------------------------------

/// Sentinel so copyWith can distinguish "leave unchanged" from "set to null".
const _unset = Object();

class PaneState {
  final String endpoint;
  final String? pairingCode; // non-null when talking through a host proxy
  final String sourceName; // human label: "this device" or the peer's hostname
  final bool online;
  final bool checking; // ping / model-list refresh in flight
  final List<ModelInfo> models;
  final String? model;
  final List<ChatMessage> messages;
  final bool isStreaming;
  final double tokPerSec;
  final String? error;

  const PaneState({
    required this.endpoint,
    required this.sourceName,
    this.pairingCode,
    this.online = false,
    this.checking = false,
    this.models = const [],
    this.model,
    this.messages = const [],
    this.isStreaming = false,
    this.tokPerSec = 0,
    this.error,
  });

  /// Can this pane accept a prompt right now?
  bool get ready => online && model != null && !isStreaming;

  PaneState copyWith({
    bool? online,
    bool? checking,
    List<ModelInfo>? models,
    Object? model = _unset,
    List<ChatMessage>? messages,
    bool? isStreaming,
    double? tokPerSec,
    Object? error = _unset,
  }) =>
      PaneState(
        endpoint: endpoint,
        sourceName: sourceName,
        pairingCode: pairingCode,
        online: online ?? this.online,
        checking: checking ?? this.checking,
        models: models ?? this.models,
        model: identical(model, _unset) ? this.model : model as String?,
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        tokPerSec: tokPerSec ?? this.tokPerSec,
        error: identical(error, _unset) ? this.error : error as String?,
      );
}

class PaneController extends StateNotifier<PaneState> {
  ChatStream? _active;

  /// Bumped every time the source changes so an in-flight refresh or stream
  /// for the OLD endpoint can't clobber state for the new one.
  int _epoch = 0;

  PaneController()
      : super(const PaneState(
          endpoint: 'http://127.0.0.1:11434',
          sourceName: 'this device',
        )) {
    refresh();
  }

  OllamaEngine get _engine => OllamaEngine(
        state.endpoint,
        headers: state.pairingCode == null
            ? const {}
            : {kPairingHeader: state.pairingCode!},
      );

  /// Point the pane somewhere else. The conversation is kept — each reply is
  /// stamped with the model that produced it, so mixing speakers stays honest.
  Future<void> setSource({
    required String endpoint,
    String? pairingCode,
    required String sourceName,
  }) {
    stop();
    _epoch++;
    var url = endpoint.trim();
    if (!url.startsWith('http')) url = 'http://$url';
    state = PaneState(
      endpoint: url.replaceAll(RegExp(r'/+$'), ''),
      pairingCode: pairingCode,
      sourceName: sourceName,
      messages: state.messages,
    );
    return refresh();
  }

  /// Ping + refresh the model list; auto-select a model if none survives.
  Future<void> refresh() async {
    final epoch = _epoch;
    final engine = _engine;
    state = state.copyWith(checking: true, error: null);
    final online = await engine.ping();
    if (epoch != _epoch || !mounted) return;
    if (!online) {
      state = state.copyWith(
          online: false, checking: false, models: const [], model: null);
      return;
    }
    try {
      final models = await engine.listModels();
      if (epoch != _epoch || !mounted) return;
      final keep = models.any((m) => m.name == state.model);
      state = state.copyWith(
        online: true,
        checking: false,
        models: models,
        model: keep
            ? state.model
            : (models.isEmpty ? null : models.first.name),
      );
    } catch (e) {
      if (epoch != _epoch || !mounted) return;
      state = state.copyWith(online: true, checking: false, error: '$e');
    }
  }

  void selectModel(String name) {
    stop(); // switching speaker mid-sentence cuts the old one off
    state = state.copyWith(model: name);
  }

  /// Send a prompt and stream the reply. Completes when the stream ends, so
  /// the arena can race two panes with Future.wait and see who finishes first.
  Future<void> send(String text) async {
    final model = state.model;
    if (model == null || state.isStreaming || text.trim().isEmpty) return;

    final engine = _engine;
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
      error: null,
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
      if (mounted) state = state.copyWith(error: '$e');
    } finally {
      _active = null;
      if (mounted) {
        // Drop an assistant bubble that never received any content.
        final msgs = [...state.messages];
        if (msgs.isNotEmpty &&
            msgs.last.role == Role.assistant &&
            msgs.last.content.isEmpty) {
          msgs.removeLast();
        }
        state = state.copyWith(messages: msgs, isStreaming: false);
      }
    }
  }

  void stop() => _active?.cancel();

  void clearConversation() {
    stop();
    state = state.copyWith(messages: const [], tokPerSec: 0, error: null);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// family: one controller per side, both alive for the whole session so a
/// conversation survives switching between the Chat and Arena tabs.
final paneProvider =
    StateNotifierProvider.family<PaneController, PaneState, ArenaSide>(
        (ref, side) => PaneController());

// ---------------------------------------------------------------------------
// The arena itself: mode, the current duel round, and the scoreboard
// ---------------------------------------------------------------------------

class Tally {
  final int left;
  final int right;
  final int ties;
  const Tally({this.left = 0, this.right = 0, this.ties = 0});
}

class ArenaState {
  final ArenaMode mode;

  /// Which pane's stream ended first in the round in flight (subtle bragging
  /// rights — it measures wall-clock finish, not answer length fairness).
  final ArenaSide? firstFinisher;

  /// Both panes have finished the current duel prompt.
  final bool roundComplete;

  /// A vote has been cast for the current round.
  final bool voted;

  /// "left-model ⇄ right-model", captured when the round starts, so votes are
  /// tallied against the models that actually answered — not whatever is
  /// selected by the time the user clicks.
  final String? roundPairing;

  /// Scoreboard, keyed by pairing. In-memory only; resets with the app.
  final Map<String, Tally> scores;

  const ArenaState({
    this.mode = ArenaMode.duel,
    this.firstFinisher,
    this.roundComplete = false,
    this.voted = false,
    this.roundPairing,
    this.scores = const {},
  });

  ArenaState copyWith({
    ArenaMode? mode,
    Object? firstFinisher = _unset,
    bool? roundComplete,
    bool? voted,
    Object? roundPairing = _unset,
    Map<String, Tally>? scores,
  }) =>
      ArenaState(
        mode: mode ?? this.mode,
        firstFinisher: identical(firstFinisher, _unset)
            ? this.firstFinisher
            : firstFinisher as ArenaSide?,
        roundComplete: roundComplete ?? this.roundComplete,
        voted: voted ?? this.voted,
        roundPairing: identical(roundPairing, _unset)
            ? this.roundPairing
            : roundPairing as String?,
        scores: scores ?? this.scores,
      );
}

class ArenaController extends StateNotifier<ArenaState> {
  final Ref ref;

  /// Guards against a stale round's completions mutating a newer round.
  int _round = 0;

  ArenaController(this.ref) : super(const ArenaState());

  void setMode(ArenaMode mode) => state = state.copyWith(mode: mode);

  bool get bothReady =>
      ref.read(paneProvider(ArenaSide.left)).ready &&
      ref.read(paneProvider(ArenaSide.right)).ready;

  /// Duel: fire the same prompt at both panes and race the streams.
  Future<void> sendDuel(String text) async {
    if (text.trim().isEmpty) return;
    final l = ref.read(paneProvider(ArenaSide.left));
    final r = ref.read(paneProvider(ArenaSide.right));
    if (!l.ready || !r.ready) return;

    final round = ++_round;
    state = state.copyWith(
      firstFinisher: null,
      roundComplete: false,
      voted: false,
      roundPairing: '${l.model} ⇄ ${r.model}',
    );

    Future<void> run(ArenaSide side) async {
      await ref.read(paneProvider(side).notifier).send(text);
      // First future to resolve claims the laurel; the second sees it taken.
      if (_round == round && state.firstFinisher == null) {
        state = state.copyWith(firstFinisher: side);
      }
    }

    await Future.wait([run(ArenaSide.left), run(ArenaSide.right)]);
    if (_round == round && mounted) {
      state = state.copyWith(roundComplete: true);
    }
  }

  void stopBoth() {
    ref.read(paneProvider(ArenaSide.left).notifier).stop();
    ref.read(paneProvider(ArenaSide.right).notifier).stop();
  }

  /// Vote for the round that just finished. [winner] null means a tie.
  void vote(ArenaSide? winner) {
    final key = state.roundPairing;
    if (key == null || state.voted || !state.roundComplete) return;
    final t = state.scores[key] ?? const Tally();
    final updated = switch (winner) {
      ArenaSide.left => Tally(left: t.left + 1, right: t.right, ties: t.ties),
      ArenaSide.right => Tally(left: t.left, right: t.right + 1, ties: t.ties),
      null => Tally(left: t.left, right: t.right, ties: t.ties + 1),
    };
    state = state.copyWith(scores: {...state.scores, key: updated}, voted: true);
  }

  /// Wipe both conversations and the round state (scoreboard survives).
  void clearAll() {
    stopBoth();
    ref.read(paneProvider(ArenaSide.left).notifier).clearConversation();
    ref.read(paneProvider(ArenaSide.right).notifier).clearConversation();
    state = state.copyWith(
        firstFinisher: null, roundComplete: false, voted: false, roundPairing: null);
  }
}

final arenaProvider = StateNotifierProvider<ArenaController, ArenaState>(
    (ref) => ArenaController(ref));
