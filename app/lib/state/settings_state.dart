/// App-level settings — currently just the theme. `settings.json` via
/// local_store, loaded in main() before the first frame so the app never
/// flashes the wrong palette.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import 'local_store.dart';

/// Mirrors Sym.isDark so widgets can watch the toggle; the source of truth
/// for colors stays the static palette in theme.dart.
final darkModeProvider = StateProvider<bool>((_) => Sym.isDark);

/// Called once from main(), before runApp.
Future<void> loadSettings() async {
  try {
    final raw = await readData('settings.json');
    if (raw == null) return;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    Sym.setDark(j['dark'] as bool? ?? true);
  } catch (_) {
    // Corrupt settings → default dark, same as first run.
  }
}

Future<void> setDarkMode(WidgetRef ref, bool dark) async {
  Sym.setDark(dark);
  ref.read(darkModeProvider.notifier).state = dark;
  await writeData('settings.json', jsonEncode({'dark': dark}));
}
