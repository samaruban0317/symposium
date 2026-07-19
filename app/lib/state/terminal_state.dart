/// The built-in terminal — VS Code's panel idea, sized for this app's needs.
///
/// Not a full PTY (no vim, no colors): each submitted line runs as its own
/// `powershell -Command` / `sh -c` process with stdout+stderr streamed into a
/// scrollback buffer. That covers what a model-tinkerer actually types here —
/// `ollama list`, `ollama ps`, `ipconfig`, `ping` — with zero native
/// dependencies. `cd` is interpreted by us so the working directory sticks
/// between commands; `clear`/`cls` wipe the buffer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the terminal drawer is visible.
final terminalOpenProvider = StateProvider<bool>((_) => false);

/// Panel height — user-draggable, like VS Code's panel splitter.
final terminalHeightProvider = StateProvider<double>((_) => 240);

enum LineKind { input, out, err, info }

class TermLine {
  final String text;
  final LineKind kind;
  const TermLine(this.text, this.kind);
}

class TerminalState {
  final List<TermLine> lines;
  final bool busy; // a command is currently running
  final String cwd;

  const TerminalState({this.lines = const [], this.busy = false, required this.cwd});

  TerminalState copyWith({List<TermLine>? lines, bool? busy, String? cwd}) =>
      TerminalState(
        lines: lines ?? this.lines,
        busy: busy ?? this.busy,
        cwd: cwd ?? this.cwd,
      );
}

class TerminalController extends StateNotifier<TerminalState> {
  static const _maxLines = 2000;

  Process? _proc;

  /// Submitted commands, oldest first — the ↑/↓ recall buffer.
  final List<String> history = [];

  TerminalController()
      : super(TerminalState(
          cwd: Platform.environment['USERPROFILE'] ??
              Platform.environment['HOME'] ??
              Directory.current.path,
          lines: const [
            TermLine('Symposium terminal — try `ollama list`', LineKind.info),
          ],
        ));

  void _add(String text, LineKind kind) {
    var lines = [...state.lines, TermLine(text, kind)];
    if (lines.length > _maxLines) {
      lines = lines.sublist(lines.length - _maxLines);
    }
    state = state.copyWith(lines: lines);
  }

  Future<void> run(String command) async {
    final cmd = command.trim();
    if (cmd.isEmpty || state.busy) return;
    if (history.isEmpty || history.last != cmd) history.add(cmd);
    _add('❯ $cmd', LineKind.input);

    if (cmd == 'clear' || cmd == 'cls') {
      state = state.copyWith(lines: const []);
      return;
    }
    if (cmd == 'cd' || cmd.startsWith('cd ')) {
      _chdir(cmd == 'cd' ? '' : cmd.substring(3).trim());
      return;
    }

    state = state.copyWith(busy: true);
    try {
      final proc = Platform.isWindows
          ? await Process.start(
              'powershell', ['-NoLogo', '-NonInteractive', '-Command', cmd],
              workingDirectory: state.cwd)
          : await Process.start('sh', ['-c', cmd], workingDirectory: state.cwd);
      _proc = proc;
      proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((l) => _add(l, LineKind.out));
      proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((l) => _add(l, LineKind.err));
      final code = await proc.exitCode;
      if (code != 0) _add('exit $code', LineKind.info);
    } catch (e) {
      _add('$e', LineKind.err);
    } finally {
      _proc = null;
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  void _chdir(String target) {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        state.cwd;
    final path = target.isEmpty || target == '~' ? home : target;
    final dir = Directory(
        path.contains(':') || path.startsWith('/') || path.startsWith('\\')
            ? path
            : '${state.cwd}${Platform.pathSeparator}$path');
    if (dir.existsSync()) {
      state = state.copyWith(cwd: dir.resolveSymbolicLinksSync());
    } else {
      _add('no such directory: $path', LineKind.err);
    }
  }

  /// Stop the running command (the panel's ✕ while busy).
  void kill() => _proc?.kill();

  @override
  void dispose() {
    _proc?.kill();
    super.dispose();
  }
}

final terminalProvider = StateNotifierProvider<TerminalController, TerminalState>(
    (_) => TerminalController());
