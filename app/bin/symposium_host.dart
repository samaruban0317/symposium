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
//   SUPABASE_JWT_SECRET      optional — verifies student JWTs; empty = student
//                            tier off (JWT holders fall back to guest)
//   OLLAMA_HOST              default 127.0.0.1:11434 — the local engine
//   SYMPOSIUM_PORT          default 47475 — the public proxy port (behind Caddy)
//
// Host limits (the "router admin page" — see deploy/symposium-host.env.example
// and deploy/host-limits.example.json). All numeric caps use 0 = unlimited.
// Resolved in this precedence order (later wins):
//   1. HostLimits.defaults (baked-in "lending a friend some PC" values)
//   2. SYMPOSIUM_LIMITS_FILE — a JSON file (partial is fine) if readable
//   3. Individual env overrides (only when set + valid int):
//        SYMPOSIUM_MAX_CONNECTIONS, SYMPOSIUM_MAX_USERS_PER_DAY,
//        SYMPOSIUM_DAILY_TOTAL_CAP, SYMPOSIUM_GUEST_PER_HOUR,
//        SYMPOSIUM_STUDENT_PER_DAY

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:symposium/net/host_limits.dart';
import 'package:symposium/net/host_server.dart';
import 'package:symposium/net/protocol.dart';

Future<void> main(List<String> args) async {
  final env = Platform.environment;

  final pairingCode = (env['SYMPOSIUM_PAIRING_CODE'] ?? '').trim();
  final adminToken = (env['SYMPOSIUM_ADMIN_TOKEN'] ?? '').trim();
  final jwtSecret = (env['SUPABASE_JWT_SECRET'] ?? '').trim();
  final limits = _resolveLimits(env);
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
  if (jwtSecret.isEmpty) {
    _log('WARN: SUPABASE_JWT_SECRET is empty — student tier is OFF. Bearer-JWT '
        'holders are treated as guests (small models only, '
        '${_cap(limits.guestPerHour)}/hr).');
  }

  // Show the effective policy at startup (no secrets here — pure config).
  _log('Effective host limits: '
      'max_connections=${_cap(limits.maxConnections)}, '
      'max_users_per_day=${_cap(limits.maxUsersPerDay)}, '
      'daily_total_cap=${_cap(limits.dailyTotalCap)}, '
      'guest_per_hour=${_cap(limits.guestPerHour)}, '
      'student_per_day=${_cap(limits.studentPerDay)}, '
      'guest_models=${limits.guestModels.join(",")}.');

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
    jwtSecret: jwtSecret,
    limits: limits,
  );

  try {
    await server.start(port);
  } catch (e) {
    _log('FATAL: could not bind port $port: $e');
    exit(1);
  }

  _log('Symposium host proxy listening on 0.0.0.0:$port → $upstream '
      '(admin: ${adminToken.isEmpty ? "off" : "on"}, '
      'student tier: ${jwtSecret.isEmpty ? "off" : "on"}; '
      'guest ${_cap(limits.guestPerHour)}/hr, '
      'student ${_cap(limits.studentPerDay)}/day). '
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

/// Build the effective [HostLimits] from environment config.
///
/// Precedence (later overrides earlier):
///   1. [HostLimits.defaults].
///   2. `SYMPOSIUM_LIMITS_FILE` — a JSON file merged via `HostLimits.fromJson`
///      (partial files are fine; unnamed fields keep the current value).
///   3. Individual `SYMPOSIUM_*` int env vars, each applied only when set to a
///      valid integer.
HostLimits _resolveLimits(Map<String, String> env) {
  var limits = HostLimits.defaults;

  // 2. Optional JSON file. Unreadable/invalid file is a warning, not fatal —
  //    we fall back to whatever we have so far.
  final filePath = (env['SYMPOSIUM_LIMITS_FILE'] ?? '').trim();
  if (filePath.isNotEmpty) {
    try {
      final raw = File(filePath).readAsStringSync();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        limits = HostLimits.fromJson(decoded, base: limits);
        _log('Loaded host limits from SYMPOSIUM_LIMITS_FILE=$filePath.');
      } else {
        _log('WARN: SYMPOSIUM_LIMITS_FILE=$filePath is not a JSON object — ignored.');
      }
    } catch (e) {
      _log('WARN: could not read SYMPOSIUM_LIMITS_FILE=$filePath ($e) — ignored.');
    }
  }

  // 3. Individual env overrides — only when set to a valid int.
  int? envInt(String key) => int.tryParse((env[key] ?? '').trim());
  limits = limits.copyWith(
    maxConnections: envInt('SYMPOSIUM_MAX_CONNECTIONS'),
    maxUsersPerDay: envInt('SYMPOSIUM_MAX_USERS_PER_DAY'),
    dailyTotalCap: envInt('SYMPOSIUM_DAILY_TOTAL_CAP'),
    guestPerHour: envInt('SYMPOSIUM_GUEST_PER_HOUR'),
    studentPerDay: envInt('SYMPOSIUM_STUDENT_PER_DAY'),
  );

  return limits;
}

/// Render a numeric cap for logs — `0` means unlimited by convention.
String _cap(int v) => v == 0 ? 'unlimited' : '$v';

void _log(String msg) {
  final ts = DateTime.now().toIso8601String();
  stdout.writeln('[$ts] symposium-host: $msg');
}
