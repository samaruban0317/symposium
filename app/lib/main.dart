import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: SymposiumApp()));
}

class SymposiumApp extends StatelessWidget {
  const SymposiumApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Symposium',
        debugShowCheckedModeBanner: false,
        theme: Sym.theme(),
        home: const HomeScreen(),
      );
}
