/// A saved conversation — the unit of the history list. Plain data,
/// no Flutter imports, same rule as chat.dart.
library;

import 'chat.dart';

class Conversation {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
  });

  Conversation copyWith({
    String? title,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
  }) =>
      Conversation(
        id: id,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': [for (final m in messages) m.toJson()],
      };

  static Conversation? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String) return null;
    return Conversation(
      id: id,
      title: j['title'] as String? ?? 'untitled',
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      messages: [
        for (final m in (j['messages'] as List? ?? []))
          ChatMessage.fromJson(m as Map<String, dynamic>),
      ],
    );
  }

  /// Auto-title: the opening user message, whitespace collapsed, clipped.
  static String titleFrom(List<ChatMessage> messages) {
    for (final m in messages) {
      if (m.role != Role.user) continue;
      final t = m.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isEmpty) continue;
      return t.length <= 48 ? t : '${t.substring(0, 47)}…';
    }
    return 'untitled';
  }
}
