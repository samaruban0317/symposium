import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'chat_view.dart';
import 'sidebar.dart';
import 'widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider);
    final online = ref.watch(serverOnlineProvider).valueOrNull ?? false;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    final header = Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Sym.hairline)),
      ),
      child: Row(
        children: [
          if (!wide)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, size: 18, color: Sym.inkDim),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          Text('Symposium',
              style: Sym.display(size: 21, weight: FontWeight.w600, color: Sym.ink)),
          const SizedBox(width: 10),
          Text('a gathering of minds', style: Sym.mono(size: 10, color: Sym.inkFaint, spacing: 1)),
          const Spacer(),
          if (chat.tokPerSec > 0)
            Readout(
              label: 'TOK/S',
              value: chat.tokPerSec.toStringAsFixed(1),
              valueColor: chat.isStreaming ? Sym.teal : Sym.inkDim,
            ),
          const SizedBox(width: 18),
          IconButton(
            tooltip: 'New conversation',
            onPressed: () => ref.read(chatControllerProvider.notifier).clear(),
            icon: const Icon(Icons.restart_alt, size: 17, color: Sym.inkDim),
          ),
          const SizedBox(width: 4),
          StatusDot(online: online),
        ],
      ),
    );

    return Scaffold(
      drawer: wide ? null : const Drawer(backgroundColor: Sym.surface, child: Sidebar()),
      body: Row(
        children: [
          if (wide) const Sidebar(),
          Expanded(
            child: Column(
              children: [
                header,
                const Expanded(child: Center(child: ChatView())),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
