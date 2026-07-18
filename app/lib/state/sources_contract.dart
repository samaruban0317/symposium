/// Frozen contract between the sources layer and everything that consumes
/// sources (persona studio, arena picker). The sources layer loads, persists,
/// and mutates this list; consumers only watch it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/source.dart';

/// Every source the user has saved. Always contains [kLocalSource] first.
/// Populated from disk by the sources layer at startup.
final savedSourcesProvider =
    StateProvider<List<ModelSource>>((ref) => const [kLocalSource]);
