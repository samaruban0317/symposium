import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../state/arena_state.dart';
import '../state/settings_state.dart';
import '../state/terminal_state.dart';
import '../theme.dart';
import 'about_dialog.dart';
import 'arena/arena_view.dart';
import 'chat_view.dart';
import 'persona/studio_view.dart';
import 'sidebar.dart';
import 'terminal_panel.dart';
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
    // A shell only makes sense where one exists.
    final hasShell = !Platform.isAndroid && !Platform.isIOS;
    final termOpen = hasShell && ref.watch(terminalOpenProvider);

    // On phones the tabs live in a bottom bar and the header stays minimal —
    // title + status only. Cramming three tabs plus instruments into a 360dp
    // header row is what caused the overflow stripes.
    final header = Container(
      height: 58,
      padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Sym.hairline)),
      ),
      child: Row(
        children: [
          if (!wide)
            Builder(
              builder: (ctx) => IconButton(
                icon: Icon(Icons.menu, size: 18, color: Sym.inkDim),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          Text('☙',
              style: Sym.display(size: wide ? 17 : 15, color: Sym.amberDim)),
          const SizedBox(width: 8),
          Flexible(
            child: Text('Symposium',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Sym.display(
                    size: wide ? 21 : 18,
                    weight: FontWeight.w600,
                    color: Sym.ink)),
          ),
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
            const SizedBox(width: 18),
            _HeaderTab(
              label: 'CHAT',
              active: onChat,
              onTap: () =>
                  ref.read(homeTabProvider.notifier).state = HomeTab.chat,
            ),
            const SizedBox(width: 2),
            _HeaderTab(
              label: 'ARENA',
              active: tab == HomeTab.arena,
              onTap: () =>
                  ref.read(homeTabProvider.notifier).state = HomeTab.arena,
            ),
            const SizedBox(width: 2),
            _HeaderTab(
              label: 'STUDIO',
              active: tab == HomeTab.studio,
              onTap: () =>
                  ref.read(homeTabProvider.notifier).state = HomeTab.studio,
            ),
          ],
          const Spacer(),
          // Chat-tab instruments; the arena carries its own telemetry per pane.
          if (wide && onChat && chat.tokPerSec > 0) ...[
            Readout(
              label: 'TOK/S',
              value: chat.tokPerSec.toStringAsFixed(1),
              valueColor: chat.isStreaming ? Sym.teal : Sym.inkDim,
            ),
            const SizedBox(width: 18),
          ],
          IconButton(
            tooltip: Sym.isDark ? 'Daylight theme' : 'Lamplight theme',
            onPressed: () => setDarkMode(ref, !Sym.isDark),
            icon: Icon(
                Sym.isDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                size: 17,
                color: Sym.inkDim),
          ),
          IconButton(
            tooltip: 'About Symposium — a Visionary Sparks product',
            onPressed: () => showSymAbout(context),
            icon: Icon(Icons.info_outline, size: 17, color: Sym.inkDim),
          ),
          if (hasShell)
            IconButton(
              tooltip: termOpen ? 'Hide terminal' : 'Terminal',
              onPressed: () =>
                  ref.read(terminalOpenProvider.notifier).state = !termOpen,
              icon: Icon(Icons.terminal,
                  size: 17, color: termOpen ? Sym.amber : Sym.inkDim),
            ),
          if (onChat)
            IconButton(
              tooltip: 'New conversation',
              onPressed: () =>
                  ref.read(chatControllerProvider.notifier).newConversation(),
              icon:
                  Icon(Icons.add_comment_outlined, size: 17, color: Sym.inkDim),
            ),
          const SizedBox(width: 4),
          StatusDot(online: online),
          if (!wide) const SizedBox(width: 8),
        ],
      ),
    );

    return Scaffold(
      drawer: wide
          ? null
          : Drawer(
              backgroundColor: Sym.surface, child: SafeArea(child: Sidebar())),
      // SafeArea keeps the header out from under the status bar and the
      // composer above the gesture bar on edge-to-edge Android builds.
      body: SafeArea(
        child: Row(
          children: [
            if (wide) const Sidebar(),
            Expanded(
              child: Column(
                children: [
                  header,
                  Expanded(
                    // A quiet cross-fade between tabs — instant-feeling but
                    // not jarring.
                    child: AnimatedSwitcher(
                      duration: Sym.med,
                      switchInCurve: Sym.ease,
                      switchOutCurve: Sym.ease,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                                  begin: const Offset(0, 0.015),
                                  end: Offset.zero)
                              .animate(anim),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(tab),
                        child: switch (tab) {
                          HomeTab.chat => const Center(child: ChatView()),
                          HomeTab.arena => const ArenaView(),
                          HomeTab.studio => const StudioView(),
                        },
                      ),
                    ),
                  ),
                  if (termOpen) const TerminalPanel(),
                  if (!wide) _BottomNav(tab: tab, ref: ref),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Phone navigation: the three destinations as an instrument-panel strip
/// pinned to the bottom, where thumbs actually are.
class _BottomNav extends StatelessWidget {
  final HomeTab tab;
  final WidgetRef ref;

  const _BottomNav({required this.tab, required this.ref});

  @override
  Widget build(BuildContext context) {
    Widget item(String label, IconData icon, HomeTab target) {
      final active = tab == target;
      return Expanded(
        child: InkWell(
          onTap: () => ref.read(homeTabProvider.notifier).state = target,
          child: AnimatedContainer(
            duration: Sym.fast,
            curve: Sym.ease,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? Sym.amber.withValues(alpha: 0.05)
                  : Colors.transparent,
              border: Border(
                top: BorderSide(
                  color: active ? Sym.amber : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: active ? 1.08 : 1,
                  duration: Sym.med,
                  curve: Sym.ease,
                  child: Icon(icon,
                      size: 18, color: active ? Sym.amber : Sym.inkDim),
                ),
                const SizedBox(height: 3),
                Text(label,
                    style: Sym.label(
                        color: active ? Sym.amber : Sym.inkDim, size: 8.5)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Sym.surface,
        border: Border(top: BorderSide(color: Sym.hairline)),
      ),
      child: Row(
        children: [
          item('CHAT', Icons.forum_outlined, HomeTab.chat),
          item('ARENA', Icons.compare_arrows, HomeTab.arena),
          item('STUDIO', Icons.theater_comedy_outlined, HomeTab.studio),
        ],
      ),
    );
  }
}

/// Header navigation tab: mono label with an amber underline when active —
/// same instrument-panel language as the rest of the chrome. The underline
/// and label color ease in, and the label brightens on hover.
class _HeaderTab extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _HeaderTab(
      {required this.label, required this.active, required this.onTap});

  @override
  State<_HeaderTab> createState() => _HeaderTabState();
}

class _HeaderTabState extends State<_HeaderTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? Sym.amber : (_hover ? Sym.ink : Sym.inkDim);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Sym.fast,
          curve: Sym.ease,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.active
                    ? Sym.amber
                    : (_hover ? Sym.hairline : Colors.transparent),
                width: 2,
              ),
            ),
          ),
          child: Text(widget.label, style: Sym.label(color: color, size: 9.5)),
        ),
      ),
    );
  }
}
