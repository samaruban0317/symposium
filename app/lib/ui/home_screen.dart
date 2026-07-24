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
      height: 60,
      padding: EdgeInsets.only(left: wide ? Sym.space5 : Sym.space2, right: wide ? Sym.space4 : Sym.space2),
      decoration: BoxDecoration(
        color: Sym.surface.withValues(alpha: 0.35),
        border: Border(bottom: Sym.hairSide),
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
          const SizedBox(width: Sym.space2),
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
            const SizedBox(width: Sym.space3),
            Flexible(
              child: Text(
                'a gathering of minds',
                style: Sym.mono(size: 10, color: Sym.inkFaint, spacing: 1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Sym.space5),
            // A hairline divider keeps the wordmark and the nav visually distinct.
            Container(width: 1, height: 20, color: Sym.hairline),
            const SizedBox(width: Sym.space4),
            _HeaderTab(
              label: 'CHAT',
              active: onChat,
              onTap: () =>
                  ref.read(homeTabProvider.notifier).state = HomeTab.chat,
            ),
            const SizedBox(width: Sym.space1),
            _HeaderTab(
              label: 'ARENA',
              active: tab == HomeTab.arena,
              onTap: () =>
                  ref.read(homeTabProvider.notifier).state = HomeTab.arena,
            ),
            const SizedBox(width: Sym.space1),
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
            AnimatedSwitcher(
              duration: Sym.motionBase,
              child: Readout(
                key: ValueKey(chat.isStreaming),
                label: 'TOK/S',
                value: chat.tokPerSec.toStringAsFixed(1),
                valueColor: chat.isStreaming ? Sym.teal : Sym.inkDim,
              ),
            ),
            const SizedBox(width: Sym.space4),
          ],
          _HeaderIconButton(
            tooltip: Sym.isDark ? 'Daylight theme' : 'Lamplight theme',
            icon: Sym.isDark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            onPressed: () => setDarkMode(ref, !Sym.isDark),
          ),
          _HeaderIconButton(
            tooltip: 'About Symposium — a Visionary Sparks product',
            icon: Icons.info_outline,
            onPressed: () => showSymAbout(context),
          ),
          if (hasShell)
            _HeaderIconButton(
              tooltip: termOpen ? 'Hide terminal' : 'Terminal',
              icon: Icons.terminal,
              active: termOpen,
              onPressed: () =>
                  ref.read(terminalOpenProvider.notifier).state = !termOpen,
            ),
          if (onChat)
            _HeaderIconButton(
              tooltip: 'New conversation',
              icon: Icons.add_comment_outlined,
              onPressed: () =>
                  ref.read(chatControllerProvider.notifier).newConversation(),
            ),
          const SizedBox(width: Sym.space3),
          StatusDot(online: online),
          if (!wide) const SizedBox(width: Sym.space2),
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
                      duration: const Duration(milliseconds: 160),
                      switchInCurve: Curves.easeOutCubic,
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
            duration: Sym.motionBase,
            curve: Sym.ease,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              gradient: active ? Sym.accentWash(Sym.amber, top: 0.10) : null,
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
                Icon(icon, size: 18, color: active ? Sym.amber : Sym.inkDim),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: Sym.motionBase,
                  curve: Sym.ease,
                  style: Sym.label(
                      color: active ? Sym.amber : Sym.inkDim, size: 8.5),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Sym.surface,
        border: Border(top: Sym.hairSide),
        boxShadow: Sym.shadow(2),
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

/// A header action button with a soft, animated hover surface and an optional
/// "active" (amber) state — quieter and more consistent than a raw IconButton.
class _HeaderIconButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final color = active ? Sym.amber : (_hover ? Sym.ink : Sym.inkDim);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: Sym.motionFast,
            curve: Sym.ease,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: active
                  ? Sym.amber.withValues(alpha: 0.10)
                  : (_hover ? Sym.ink.withValues(alpha: 0.05) : Colors.transparent),
              borderRadius: const BorderRadius.all(Sym.rSm),
            ),
            child: Icon(widget.icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}

/// Header navigation tab: mono label that lifts into a soft amber pill when
/// active, with a hover tint when idle — same instrument-panel language as the
/// rest of the chrome, but with gentle state transitions.
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
    final active = widget.active;
    final color = active
        ? Sym.amber
        : (_hover ? Sym.ink : Sym.inkDim);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Sym.motionFast,
          curve: Sym.ease,
          padding:
              const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? Sym.amber.withValues(alpha: 0.12)
                : (_hover ? Sym.ink.withValues(alpha: 0.04) : Colors.transparent),
            borderRadius: const BorderRadius.all(Sym.rSm),
            border: Border.all(
              color: active ? Sym.amber.withValues(alpha: 0.32) : Colors.transparent,
              width: 1,
            ),
          ),
          child: AnimatedDefaultTextStyle(
            duration: Sym.motionFast,
            curve: Sym.ease,
            style: Sym.label(color: color, size: 9.5, spacing: 1.6),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}
