import 'dart:io';

/// The result of a local-engine health check: is Ollama answering, and if not,
/// a short, OS-specific nudge on how to get it running.
class OllamaStatus {
  final bool running;

  /// Platform-tailored guidance, non-empty only when [running] is false.
  /// A Linux user sees `systemctl` / `pacman`, a Mac user sees `brew`, a
  /// Windows user gets the installer link — instead of a blank empty state.
  final String hint;

  const OllamaStatus({required this.running, this.hint = ''});
}

/// OS-aware probe for a *local* Ollama engine. Kept deliberately tiny and
/// dependency-free (dart:io only) so it can run on any desktop target without
/// touching the main engine plumbing. Ports never change: Ollama is 11434 and
/// the Symposium proxy is 47475 — loopback binding is identical on every OS.
class OllamaProbe {
  /// Quick `GET http://<host>/api/version` with a short timeout. Returns
  /// `running: true` on any HTTP answer (even an error status still means a
  /// server is there); otherwise `running: false` plus a platform [hint].
  static Future<OllamaStatus> probe({String host = '127.0.0.1:11434'}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client
          .getUrl(Uri.parse('http://$host/api/version'))
          .timeout(const Duration(seconds: 2));
      final res = await req.close().timeout(const Duration(seconds: 2));
      await res.drain<void>();
      return const OllamaStatus(running: true);
    } catch (_) {
      return OllamaStatus(running: false, hint: guidance());
    } finally {
      client.close(force: true);
    }
  }

  /// The platform-specific "how to start Ollama" text. Pure and synchronous so
  /// it is trivial to unit-test and to reuse anywhere an offline hint is shown.
  static String guidance() {
    if (Platform.isLinux) {
      final where = _firstExisting(
            ['/usr/bin/ollama', '/usr/local/bin/ollama'],
          ) ??
          'not found on PATH';
      return 'Ollama not reachable on 127.0.0.1:11434.\n'
          'Binary: $where\n'
          'Start it:  systemctl status ollama\n'
          '           sudo systemctl start ollama   (or: ollama serve)\n'
          'Arch: install with  pacman -S ollama';
    }
    if (Platform.isMacOS) {
      final where = _firstExisting(
            ['/usr/local/bin/ollama', '/opt/homebrew/bin/ollama'],
          ) ??
          'not found on PATH';
      return 'Ollama not reachable on 127.0.0.1:11434.\n'
          'Binary: $where\n'
          'Install:  brew install ollama\n'
          'Start it: ollama serve';
    }
    if (Platform.isWindows) {
      return 'Ollama not reachable on 127.0.0.1:11434.\n'
          'Install it from https://ollama.com/download\n'
          'then run:  ollama serve';
    }
    return 'Ollama not reachable on 127.0.0.1:11434.\n'
        'Install Ollama from https://ollama.com and start it.';
  }

  static String? _firstExisting(List<String> paths) {
    for (final p in paths) {
      try {
        if (File(p).existsSync()) return p;
      } catch (_) {}
    }
    return null;
  }
}
