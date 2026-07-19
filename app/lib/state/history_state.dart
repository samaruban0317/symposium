/// Conversation history: persistence and the list the sidebar shows.
///
/// Follows the sources_state pattern exactly — one repo that owns
/// `conversations.json` via local_store, a hydration FutureProvider kicked
/// off by the first sidebar build, and a plain StateProvider the UI watches.
/// The ChatController snapshots into here after every completed exchange.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat.dart';
import '../models/conversation.dart';
import 'local_store.dart';

/// Newest-first list of saved conversations.
final conversationsProvider = StateProvider<List<Conversation>>((_) => const []);

/// Which saved conversation the chat tab is showing (null = a fresh, unsaved
/// one). Written by the ChatController, watched by the sidebar highlight.
final activeConversationIdProvider = StateProvider<String?>((_) => null);

final historyRepoProvider = Provider<HistoryRepo>((ref) => HistoryRepo(ref));

final historyLoadProvider =
    FutureProvider<void>((ref) => ref.read(historyRepoProvider).load());

class HistoryRepo {
  /// Plenty for a personal archive; keeps the JSON file from growing forever.
  static const _maxConversations = 200;

  final Ref ref;
  HistoryRepo(this.ref);

  Future<void> load() async {
    final raw = await readData('conversations.json');
    if (raw == null) return;
    try {
      final list = [
        for (final j in jsonDecode(raw) as List)
          Conversation.fromJson(j as Map<String, dynamic>),
      ].nonNulls.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      ref.read(conversationsProvider.notifier).state = list;
    } catch (_) {
      // A corrupt file must never brick the app — history just starts empty.
    }
  }

  /// Insert or refresh a conversation and float it to the top.
  /// A user-given title survives; only auto-titles get recomputed.
  Future<void> upsert(Conversation c) async {
    final current = ref.read(conversationsProvider);
    final existing = [for (final x in current) if (x.id == c.id) x];
    final keep = existing.isNotEmpty ? c.copyWith(title: existing.first.title) : c;
    await _persist([keep, for (final x in current) if (x.id != c.id) x]);
  }

  Future<void> rename(String id, String title) async => _persist([
        for (final c in ref.read(conversationsProvider))
          c.id == id ? c.copyWith(title: title) : c,
      ]);

  Future<void> remove(String id) async => _persist([
        for (final c in ref.read(conversationsProvider))
          if (c.id != id) c,
      ]);

  Future<void> _persist(List<Conversation> list) async {
    if (list.length > _maxConversations) {
      list = list.sublist(0, _maxConversations);
    }
    ref.read(conversationsProvider.notifier).state = list;
    await writeData(
      'conversations.json',
      jsonEncode([for (final c in list) c.toJson()]),
    );
  }
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

/// A conversation as shareable Markdown — the transcript exactly as spoken,
/// each turn labeled with who (or which model) said it.
String conversationMarkdown(Conversation c) {
  final b = StringBuffer()
    ..writeln('# ${c.title}')
    ..writeln()
    ..writeln('*Symposium conversation · '
        '${c.updatedAt.toLocal().toString().substring(0, 16)}*')
    ..writeln();
  for (final m in c.messages) {
    final speaker = switch (m.role) {
      Role.user => 'You',
      Role.assistant => m.modelName ?? 'Model',
      Role.system => 'System',
    };
    b
      ..writeln('---')
      ..writeln()
      ..writeln('**$speaker**')
      ..writeln()
      ..writeln(m.content.trim())
      ..writeln();
  }
  return b.toString();
}

/// Writes the Markdown next to the user's other files (Downloads) and
/// returns the path — or null where that folder doesn't exist (Android),
/// in which case the caller falls back to clipboard-only.
Future<String?> exportConversationFile(Conversation c) async {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null) return null;
  final downloads = Directory('$home${Platform.pathSeparator}Downloads');
  if (!downloads.existsSync()) return null;
  final slug = c.title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final name = 'symposium-${slug.isEmpty ? c.id : slug}.md';
  final file = File('${downloads.path}${Platform.pathSeparator}$name');
  await file.writeAsString(conversationMarkdown(c), flush: true);
  return file.path;
}
