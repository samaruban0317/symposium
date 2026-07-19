import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/settings_state.dart';
import 'theme.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSettings(); // palette must be right before the first frame
  runApp(const ProviderScope(child: SymposiumApp()));
}

class SymposiumApp extends ConsumerWidget {
  const SymposiumApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(darkModeProvider);
    return MaterialApp(
      title: 'Symposium — by Visionary Sparks',
      debugShowCheckedModeBanner: false,
      theme: Sym.theme(),
      // Re-keying on toggle remounts the tree, so even const widgets rebuild
      // and pick up the new palette from the Sym getters.
      home: KeyedSubtree(key: ValueKey(dark), child: const HomeScreen()),
    );
  }
}
