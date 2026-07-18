/// Persona studio state: the saved roster (persisted as personas.json) and
/// the studio itself — a draft of the selected persona's instructions plus a
/// live test chat, so the tune-and-retest loop is one click instead of
/// edit-somewhere / retype-question / squint.
///
/// The test chat deliberately mirrors the arena's PaneController discipline
/// (own engine per send, epoch guard, cancellable stream): it is just one
/// more consumer of "a model is a URL + a name".
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_factory.dart';
import '../engine/ollama_engine.dart';
import '../models/chat.dart';
import '../models/persona.dart';
import '../models/source.dart';
import 'local_store.dart';
import 'sources_contract.dart';

const _storeFile = 'personas.json';

/// Glyphs handed to new personas in rotation — a starting sigil, not a limit.
const _glyphRotation = ['✶', '❖', '☙', '✦', '◆', '❋'];

// ---------------------------------------------------------------------------
// Roster: CRUD + persistence
// ---------------------------------------------------------------------------

class PersonaListController extends StateNotifier<List<Persona>> {
  PersonaListController() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await readData(_storeFile);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final list = (j['personas'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Persona.fromJson)
          .toList();
      if (mounted) state = list;
    } catch (_) {
      // A corrupt file shouldn't brick the studio; start empty and the next
      // save rewrites it whole.
    }
  }

  Future<void> _save() => writeData(
        _storeFile,
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'personas': [for (final p in state) p.toJson()],
        }),
      );

  String _freshId() =>
      'p${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  Persona create() {
    final now = DateTime.now();
    final p = Persona(
      id: _freshId(),
      name: 'New persona',
      glyph: _glyphRotation[state.length % _glyphRotation.length],
      accentIndex: state.length % 5,
      instructions: '',
      createdAt: now,
      updatedAt: now,
    );
    state = [...state, p];
    _save();
    return p;
  }

  Persona duplicate(Persona src) {
    final now = DateTime.now();
    final copy = Persona(
      id: _freshId(),
      name: '${src.name} copy',
      glyph: src.glyph,
      accentIndex: src.accentIndex,
      instructions: src.instructions,
      temperature: src.temperature,
      topP: src.topP,
      maxTokens: src.maxTokens,
      pinnedSourceId: src.pinnedSourceId,
      pinnedModel: src.pinnedModel,
      createdAt: now,
      updatedAt: now,
    );
    state = [...state, copy];
    _save();
    return copy;
  }

  /// Adds an imported persona. A colliding id gets a fresh one — importing
  /// should never silently overwrite something you tuned.
  Persona import(Persona p) {
    final collides = state.any((e) => e.id == p.id);
    final added = collides
        ? Persona(
            id: _freshId(),
            name: p.name,
            glyph: p.glyph,
            accentIndex: p.accentIndex,
            instructions: p.instructions,
            temperature: p.temperature,
            topP: p.topP,
            maxTokens: p.maxTokens,
            pinnedModel: p.pinnedModel,
            instructionsRevision: p.instructionsRevision,
            createdAt: p.createdAt,
            updatedAt: DateTime.now(),
          )
        : p;
    state = [...state, added];
    _save();
    return added;
  }

  void upsert(Persona p) {
    state = [for (final e in state) e.id == p.id ? p : e];
    _save();
  }

  void delete(String id) {
    state = state.where((e) => e.id != id).toList();
    _save();
  }

  Persona? byId(String? id) {
    if (id == null) return null;
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }
}

final personasProvider =
    StateNotifierProvider<PersonaListController, List<Persona>>(
        (ref) => PersonaListController());

/// Which persona the studio has open.
final studioPersonaIdProvider = StateProvider<String?>((ref) => null);

/// Persona applied to the MAIN chat (via the composer chip), by id.
final activeChatPersonaProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// The studio: instruction draft + live test chat
// ---------------------------------------------------------------------------

/// An assistant answer remembers which instructions revision produced it —
/// that little `r3` chip is what makes iterating legible.
class StampedMessage {
  final ChatMessage msg;
  final int? revision;
  const StampedMessage(this.msg, [this.revision]);

  StampedMessage withContent(String content) =>
      StampedMessage(msg.copyWith(content: content), revision);
}

const _unset = Object();

class StudioState {
  final String sourceId; // test-chat source; id into savedSourcesProvider
  final bool online;
  final bool checking;
  final List<ModelInfo> models;
  final String? model;
  final List<StampedMessage> messages;
  final bool isStreaming;
  final double tokPerSec;
  final String? error;

  /// The editor's working copy of the instructions. Committed (and revision
  /// bumped) by APPLY — never per keystroke, or `rN` would be meaningless.
  final String draft;
  final bool draftDirty;

  /// Last question asked in the test chat, kept for one-click re-ask.
  final String? lastQuestion;

  const StudioState({
    this.sourceId = 'local',
    this.online = false,
    this.checking = false,
    this.models = const [],
    this.model,
    this.messages = const [],
    this.isStreaming = false,
    this.tokPerSec = 0,
    this.error,
    this.draft = '',
    this.draftDirty = false,
    this.lastQuestion,
  });

  bool get ready => online && model != null && !isStreaming;

  StudioState copyWith({
    String? sourceId,
    bool? online,
    bool? checking,
    List<ModelInfo>? models,
    Object? model = _unset,
    List<StampedMessage>? messages,
    bool? isStreaming,
    double? tokPerSec,
    Object? error = _unset,
    String? draft,
    bool? draftDirty,
    Object? lastQuestion = _unset,
  }) =>
      StudioState(
        sourceId: sourceId ?? this.sourceId,
        online: online ?? this.online,
        checking: checking ?? this.checking,
        models: models ?? this.models,
        model: identical(model, _unset) ? this.model : model as String?,
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        tokPerSec: tokPerSec ?? this.tokPerSec,
        error: identical(error, _unset) ? this.error : error as String?,
        draft: draft ?? this.draft,
        draftDirty: draftDirty ?? this.draftDirty,
        lastQuestion:
            identical(lastQuestion, _unset) ? this.lastQuestion : lastQuestion as String?,
      );
}

class StudioController extends StateNotifier<StudioState> {
  final Ref ref;
  ChatStream? _active;

  /// Source switches invalidate in-flight pings/streams (arena's epoch trick).
  int _epoch = 0;

  StudioController(this.ref) : super(const StudioState()) {
    // Reload the draft (and preferred source) whenever the studio opens a
    // different persona; the conversation resets — it belonged to the old one.
    ref.listen<String?>(studioPersonaIdProvider, (prev, next) {
      if (prev != next) _bindPersona(next);
    });
    _bindPersona(ref.read(studioPersonaIdProvider));
  }

  Persona? get _persona =>
      ref.read(personasProvider.notifier).byId(ref.read(studioPersonaIdProvider));

  ModelSource get _source {
    final sources = ref.read(savedSourcesProvider);
    return sources.firstWhere((s) => s.id == state.sourceId,
        orElse: () => kLocalSource);
  }

  void _bindPersona(String? id) {
    stop();
    _epoch++;
    final p = ref.read(personasProvider.notifier).byId(id);
    final sources = ref.read(savedSourcesProvider);
    final pinnedOk =
        p?.pinnedSourceId != null && sources.any((s) => s.id == p!.pinnedSourceId);
    state = StudioState(
      sourceId: pinnedOk ? p!.pinnedSourceId! : state.sourceId,
      draft: p?.instructions ?? '',
      model: state.model, // may be corrected by refresh() below
      models: state.models,
      online: state.online,
    );
    refresh().then((_) {
      // Prefer the pinned model when it exists on the bound source.
      final pm = p?.pinnedModel;
      if (pm != null && state.models.any((m) => m.name == pm)) {
        state = state.copyWith(model: pm);
      }
    });
  }

  // -- draft ----------------------------------------------------------------

  void editDraft(String text) {
    final applied = _persona?.instructions ?? '';
    state = state.copyWith(draft: text, draftDirty: text != applied);
  }

  /// Commit the draft to the persona and bump the revision counter. Returns
  /// the new revision (or the current one when nothing changed).
  int applyDraft() {
    final p = _persona;
    if (p == null) return 1;
    if (!state.draftDirty) return p.instructionsRevision;
    final updated = p.copyWith(
      instructions: state.draft,
      instructionsRevision: p.instructionsRevision + 1,
    );
    ref.read(personasProvider.notifier).upsert(updated);
    state = state.copyWith(draftDirty: false);
    return updated.instructionsRevision;
  }

  // -- source / model -------------------------------------------------------

  Future<void> setSource(String sourceId) {
    stop();
    _epoch++;
    state = state.copyWith(
        sourceId: sourceId, online: false, models: const [], model: null, error: null);
    return refresh();
  }

  Future<void> refresh() async {
    final epoch = _epoch;
    final engine = engineForSource(_source);
    state = state.copyWith(checking: true, error: null);
    final online = await engine.ping();
    if (epoch != _epoch || !mounted) return;
    if (!online) {
      state = state.copyWith(online: false, checking: false, models: const [], model: null);
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
        model: keep ? state.model : (models.isEmpty ? null : models.first.name),
      );
    } catch (e) {
      if (epoch != _epoch || !mounted) return;
      state = state.copyWith(online: true, checking: false, error: '$e');
    }
  }

  void selectModel(String name) {
    stop();
    state = state.copyWith(model: name);
  }

  /// Remember the current source + model on the persona itself.
  void pinCurrent() {
    final p = _persona;
    if (p == null) return;
    ref.read(personasProvider.notifier).upsert(
        p.copyWith(pinnedSourceId: state.sourceId, pinnedModel: state.model));
  }

  void unpin() {
    final p = _persona;
    if (p == null) return;
    ref
        .read(personasProvider.notifier)
        .upsert(p.copyWith(pinnedSourceId: null, pinnedModel: null));
  }

  // -- the loop -------------------------------------------------------------

  /// Ask a question under the persona's *applied* instructions.
  Future<void> send(String text) async {
    final p = _persona;
    final model = state.model;
    if (p == null || model == null || state.isStreaming || text.trim().isEmpty) {
      return;
    }

    final epoch = _epoch;
    final question = text.trim();
    final history = [
      ...state.messages,
      StampedMessage(ChatMessage(role: Role.user, content: question)),
    ];
    state = state.copyWith(
      messages: [
        ...history,
        StampedMessage(
          ChatMessage(role: Role.assistant, content: '', modelName: model),
          p.instructionsRevision,
        ),
      ],
      isStreaming: true,
      tokPerSec: 0,
      error: null,
      lastQuestion: question,
    );

    // Instructions ride outside the visible transcript, same as the main chat.
    final wire = [
      if (p.instructions.trim().isNotEmpty)
        ChatMessage(role: Role.system, content: p.instructions.trim()),
      for (final m in history) m.msg,
    ];

    final stopwatch = Stopwatch()..start();
    var chunks = 0;
    final chat = engineForSource(_source).chat(
      model: model,
      messages: wire,
      temperature: p.temperature,
      topP: p.topP,
      maxTokens: p.maxTokens,
    );
    _active = chat;

    try {
      await for (final delta in chat.deltas) {
        if (epoch != _epoch) return;
        chunks++;
        final msgs = [...state.messages];
        final last = msgs.last;
        msgs[msgs.length - 1] = last.withContent(last.msg.content + delta);
        final secs = stopwatch.elapsedMilliseconds / 1000;
        state = state.copyWith(
          messages: msgs,
          tokPerSec: secs > 0.2 ? chunks / secs : 0,
        );
      }
    } catch (e) {
      if (epoch == _epoch && mounted) state = state.copyWith(error: '$e');
    } finally {
      _active = null;
      if (epoch == _epoch && mounted) {
        final msgs = [...state.messages];
        if (msgs.isNotEmpty &&
            msgs.last.msg.role == Role.assistant &&
            msgs.last.msg.content.isEmpty) {
          msgs.removeLast();
        }
        state = state.copyWith(messages: msgs, isStreaming: false);
      }
    }
  }

  /// THE loop: commit the edited instructions, then put the last question
  /// again — the new answer lands in the same transcript stamped with the new
  /// revision, right under the old one, so r3 vs r4 is a glance, not a diff.
  Future<void> applyAndReAsk() async {
    final q = state.lastQuestion;
    applyDraft();
    if (q != null && !state.isStreaming) await send(q);
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

final studioProvider = StateNotifierProvider<StudioController, StudioState>(
    (ref) => StudioController(ref));
