import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../state/arena_state.dart';
import '../theme.dart';
import 'arena/arena_view.dart';
import 'chat_view.dart';
import 'persona/studio_view.dart';
import 'sidebar.dart';
import 'widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider);
    final online = ref.watch(serverOnlineProvider).valueOrNull ?? false;
    final tab = ref.watch(homeTabProvider);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final onChat = tab == HomeTab.chat;

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
          if (wide) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'a gathering of minds',
                style: Sym.mono(size: 10, color: Sym.inkFaint, spacing: 1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(width: 18),
          _HeaderTab(
            label: 'CHAT',
            active: onChat,
            onTap: () => ref.read(homeTabProvider.notifier).state = HomeTab.chat,
          ),
          const SizedBox(width: 2),
          _HeaderTab(
            label: 'ARENA',
            active: tab == HomeTab.arena,
            onTap: () => ref.read(homeTabProvider.notifier).state = HomeTab.arena,
          ),
          const SizedBox(width: 2),
          _HeaderTab(
            label: 'STUDIO',
            active: tab == HomeTab.studio,
            onTap: () => ref.read(homeTabProvider.notifier).state = HomeTab.studio,
          ),
          const Spacer(),
          // Chat-tab instruments; the arena carries its own telemetry per pane.
          if (onChat && chat.tokPerSec > 0)
            Readout(
              label: 'TOK/S',
              value: chat.tokPerSec.toStringAsFixed(1),
              valueColor: chat.isStreaming ? Sym.teal : Sym.inkDim,
            ),
          const SizedBox(width: 18),
          if (onChat)
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
                Expanded(
                  child: switch (tab) {
                    HomeTab.chat => const Center(child: ChatView()),
                    HomeTab.arena => const ArenaView(),
                    HomeTab.studio => const StudioView(),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Header navigation tab: mono label with an amber underline when active —
/// same instrument-panel language as the rest of the chrome.
class _HeaderTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _HeaderTab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? Sym.amber : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: Sym.label(color: active ? Sym.amber : Sym.inkDim, size: 9.5),
          ),
        ),
      );
}
