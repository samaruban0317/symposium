// Symposium headless host — runs the pairing/admin reverse proxy on a server
// (a display-less GPU box) without the Flutter GUI.
//
// It reuses the SAME `HostServer` the desktop app uses, so the auth rules are
// identical: every request needs the 6-digit pairing code, and Ollama's
// management endpoints (pull/delete/create/…) additionally need the admin
// token. Friends are viewer-only; only the admin can download models.
//
// Pure Dart on purpose (no Flutter imports) so `dart run bin/symposium_host.dart`
// works on a headless Linux server. Invoked by deploy/systemd/symposium-host.service.
//
// Config comes from the environment (see deploy/symposium-host.env.example):
//   SYMPOSIUM_PAIRING_CODE   required — the 6-digit code friends type
//   SYMPOSIUM_ADMIN_TOKEN    optional — bearer may pull/delete; empty = nobody can
//   OLLAMA_HOST              default 127.0.0.1:11434 — the local engine
//   SYMPOSIUM_PORT          default 47475 — the public proxy port (behind Caddy)

import 'dart:async';
import 'dart:io';

import 'package:symposium/net/host_server.dart';
import 'package:symposium/net/protocol.dart';

Future<void> main(List<String> args) async {
  final env = Platform.environment;

  final pairingCode = (env['SYMPOSIUM_PAIRING_CODE'] ?? '').trim();
  final adminToken = (env['SYMPOSIUM_ADMIN_TOKEN'] ?? '').trim();
  final upstream = _resolveUpstream(env['OLLAMA_HOST']);
  final port = int.tryParse(env['SYMPOSIUM_PORT'] ?? '') ?? kProxyPort;

  if (pairingCode.isEmpty) {
    _log('FATAL: SYMPOSIUM_PAIRING_CODE is empty. Refusing to run an '
        'unauthenticated public proxy. Set it in /etc/symposium-host.env.');
    exit(2);
  }
  if (adminToken.isEmpty) {
    _log('WARN: SYMPOSIUM_ADMIN_TOKEN is empty — management endpoints '
        '(pull/delete/create) are DISABLED for everyone. Nobody can download '
        'models remotely until you set an admin token.');
  }

  // Best-effort reachability check. Don't crash if the engine is still coming
  // up — systemd orders us After=ollama, and the proxy simply 502s until it's
  // ready. This is just a clearer startup log.
  final engineOk = await _pingOllama(upstream);
  _log(engineOk
      ? 'Ollama reachable at $upstream'
      : 'WARN: Ollama not reachable at $upstream yet — proxy will 502 until it is.');

  final server = HostServer(
    upstream: upstream,
    pairingCode: pairingCode,
    adminToken: adminToken,
  );

  try {
    await server.start(port);
  } catch (e) {
    _log('FATAL: could not bind port $port: $e');
    exit(1);
  }

  _log('Symposium host proxy listening on 0.0.0.0:$port → $upstream '
      '(admin: ${adminToken.isEmpty ? "off" : "on"}). '
      'Expose it publicly only behind Caddy/HTTPS.');

  // Graceful shutdown so systemd stop/restart is clean.
  Future<void> shutdown(ProcessSignal sig) async {
    _log('Received $sig — stopping proxy (served ${server.requestsServed} requests).');
    await server.stop();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  // SIGTERM isn't deliverable on Windows; guard so local `dart run` still works.
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen(shutdown);
  }

  // Keep the isolate alive forever; the HttpServer runs on its own.
  await Completer<void>().future;
}

/// Turn an `OLLAMA_HOST` value (`host:port`, or a full URL) into an http URL.
String _resolveUpstream(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return 'http://127.0.0.1:11434';
  if (v.startsWith('http://') || v.startsWith('https://')) return v;
  return 'http://$v';
}

Future<bool> _pingOllama(String upstream) async {
  final client = HttpClient();
  try {
    final req = await client
        .getUrl(Uri.parse('$upstream/api/tags'))
        .timeout(const Duration(seconds: 3));
    final res = await req.close().timeout(const Duration(seconds: 3));
    await res.drain<void>();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

void _log(String msg) {
  final ts = DateTime.now().toIso8601String();
  stdout.writeln('[$ts] symposium-host: $msg');
}
