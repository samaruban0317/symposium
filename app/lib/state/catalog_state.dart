/// Fetches the full Ollama library so the install browser shows everything
/// that exists, not a hand-picked five.
///
/// ollama.com has no JSON API for its library, so this parses the HTML of
/// /library — three stable markers (the /library/NAME links, the description
/// paragraph, the blue size chips) carry everything we need. Scraping is
/// brittle by nature, so any failure — offline, blocked, redesigned page —
/// falls back to the bundled snapshot and the UI says so.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/catalog.dart';

class Catalog {
  final List<CatalogEntry> entries;
  final bool live; // true = fresh from ollama.com, false = bundled snapshot
  const Catalog(this.entries, {required this.live});
}

final catalogProvider = FutureProvider<Catalog>((ref) async {
  try {
    final res = await http
        .get(Uri.parse('https://ollama.com/library'))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('http ${res.statusCode}');
    final entries = parseLibraryHtml(res.body);
    if (entries.length < 10) throw Exception('parse came up short');
    return Catalog(entries, live: true);
  } catch (_) {
    return const Catalog(kFallbackCatalog, live: false);
  }
});

/// Pulls (name, description, sizes, pull-count) out of the library page.
/// Kept as a pure function so a test can feed it saved HTML.
List<CatalogEntry> parseLibraryHtml(String html) {
  final entries = <CatalogEntry>[];
  final seen = <String>{};
  // Each model card starts with its link; the next card's link ends it.
  final chunks = html.split('href="/library/').skip(1);
  for (final chunk in chunks) {
    final name = chunk.substring(0, chunk.indexOf('"'));
    if (name.isEmpty || name.contains('/') || !seen.add(name)) continue;

    String? description;
    final desc = RegExp(r'<p class="max-w-lg[^"]*">([^<]*)</p>').firstMatch(chunk);
    if (desc != null) description = _unescape(desc.group(1)!.trim());

    final sizes = [
      for (final m in RegExp(r'text-blue-600[^>]*>([^<]+)</span>').allMatches(chunk))
        m.group(1)!.trim(),
    ];

    // The indigo chips: "vision", "tools", "thinking", "embedding"…
    final capabilities = [
      for (final m
          in RegExp(r'text-indigo-600[^>]*>([^<]+)</span>').allMatches(chunk))
        m.group(1)!.trim().toLowerCase(),
    ];

    String? pulls;
    final p = RegExp(r'<span\s*>([\d.]+[KMB]?)</span>\s*<span[^>]*>&nbsp;Pulls')
        .firstMatch(chunk);
    if (p != null) pulls = p.group(1);

    entries.add(CatalogEntry(
      name: name,
      description: description ?? '',
      sizes: sizes,
      pulls: pulls,
      capabilities: capabilities,
    ));
  }
  return entries;
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"');
