/// Recent models: the last handful of models the user picked, kept for a
/// one-tap switch-back.
///
/// Follows the sources_state / history_state pattern exactly — one repo that
/// owns `recent_models.json` via local_store, a hydration FutureProvider
/// kicked off by the first sidebar build, and a plain StateProvider the UI
/// watches. The sidebar records a pick here every time a model tile is tapped.
///
/// We remember the model NAME only (the same string [selectedModelProvider]
/// holds). That keeps the record engine-agnostic: switch-back re-selects the
/// name, and if the model isn't present at the current endpoint the sidebar
/// simply doesn't surface that chip.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_store.dart';

/// Most-recent-first list of model names the user has selected. Capped at
/// [RecentModelsRepo.max]; the UI reads this straight.
final recentModelsProvider =
    StateProvider<List<String>>((_) => const []);

final recentModelsRepoProvider =
    Provider<RecentModelsRepo>((ref) => RecentModelsRepo(ref));

final recentModelsLoadProvider =
    FutureProvider<void>((ref) => ref.read(recentModelsRepoProvider).load());

class RecentModelsRepo {
  /// The founder wants exactly the last 2 for a quick switch-back.
  static const max = 2;

  final Ref ref;
  RecentModelsRepo(this.ref);

  Future<void> load() async {
    final raw = await readData('recent_models.json');
    if (raw == null) return;
    try {
      final list = [
        for (final v in jsonDecode(raw) as List) v as String,
      ];
      ref.read(recentModelsProvider.notifier).state =
          list.take(max).toList();
    } catch (_) {
      // A corrupt file must never brick the app — recents just start empty.
    }
  }

  /// Record that [name] was just picked: float it to the front, de-dupe, cap.
  /// A no-op-looking re-select still rewrites the file so ordering stays true.
  Future<void> record(String name) async {
    if (name.trim().isEmpty) return;
    final current = ref.read(recentModelsProvider);
    final next = [
      name,
      for (final m in current)
        if (m != name) m,
    ].take(max).toList();
    ref.read(recentModelsProvider.notifier).state = next;
    await writeData('recent_models.json', jsonEncode(next));
  }
}
