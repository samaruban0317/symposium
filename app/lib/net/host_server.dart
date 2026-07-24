import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// The heart of "host mode": a tiny reverse proxy.
///
/// Ollama only listens on localhost — sensible security, but it means a friend
/// can't reach it. Instead of asking anyone to reconfigure Ollama (breaking the
/// "no terminal" promise), Symposium listens on all interfaces itself and
/// forwards each request to the local engine, first checking the 6-digit
/// pairing code. Streaming (SSE / NDJSON) passes straight through because both
/// directions are piped as byte streams, never buffered whole.
class HostServer {
  final String upstream; // the host's local engine, e.g. http://127.0.0.1:11434
  final String pairingCode;
  // Admin token for management endpoints. Empty = no admin → management denied
  // for everyone (friends are viewer-only: chat/read yes, pull/delete no).
  final String adminToken;

  HttpServer? _server;
  final _client = HttpClient();
  int requestsServed = 0;

  HostServer({required this.upstream, required this.pairingCode, this.adminToken = ''});

  /// Ollama's model-management surface: downloading, creating, deleting, pushing,
  /// copying models, and blob uploads. These mutate the host's engine, so only
  /// an admin may reach them — everything else (chat/generate/embed/tags/show/
  /// version/ps and all /v1 OpenAI-compat paths) is viewer-safe.
  bool _isManagement(String method, String path) {
    final m = method.toUpperCase();
    var p = path.toLowerCase();
    if (!p.startsWith('/')) p = '/$p';
    if (p.startsWith('/api/blobs')) return true; // blob uploads
    if (p == '/api/delete') return true; // Ollama accepts POST or DELETE here
    if (m == 'POST' &&
        (p == '/api/pull' ||
            p == '/api/push' ||
            p == '/api/create' ||
            p == '/api/copy')) {
      return true;
    }
    return false;
  }

  Future<void> start(int port) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      // CORS: lets browser apps (e.g. Classmate AI at visionarysparks.in) use
      // this engine from the same machine. Preflights carry no pairing header
      // by design, so they're answered before the code check — every real
      // request below still needs the 6-digit code, which stays the actual
      // auth. Allow-Private-Network satisfies Chrome's PNA preflight for
      // public-site → loopback requests.
      req.response.headers
        ..set('Access-Control-Allow-Origin', '*')
        ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        ..set('Access-Control-Allow-Headers', 'content-type, authorization, $kPairingHeader, $kAdminHeader')
        ..set('Access-Control-Allow-Private-Network', 'true');
      if (req.method == 'OPTIONS') {
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }
      if (req.headers.value(kPairingHeader) != pairingCode) {
        req.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'error': 'pairing code missing or wrong — ask the host for the 6-digit code'
          }));
        await req.response.close();
        return;
      }

      // Viewer/admin policy: management endpoints need a valid admin token.
      // Empty adminToken means no admin is configured, so management is denied
      // for everyone.
      if (_isManagement(req.method, req.uri.path)) {
        if (adminToken.isEmpty || req.headers.value(kAdminHeader) != adminToken) {
          req.response
            ..statusCode = HttpStatus.forbidden
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'error': 'admin token required — this host is viewer-only for you'
            }));
          await req.response.close();
          return;
        }
      }

      final target = Uri.parse(upstream).replace(
        path: req.uri.path,
        query: req.uri.hasQuery ? req.uri.query : null,
      );
      final proxReq = await _client.openUrl(req.method, target);
      req.headers.forEach((name, values) {
        final n = name.toLowerCase();
        if (n == 'host' || n == 'connection' || n == kPairingHeader || n == kAdminHeader) return;
        for (final v in values) {
          proxReq.headers.add(name, v);
        }
      });
      await proxReq.addStream(req);
      final proxRes = await proxReq.close();

      req.response.statusCode = proxRes.statusCode;
      proxRes.headers.forEach((name, values) {
        final n = name.toLowerCase();
        // Let dart:io manage framing of our own response.
        if (n == 'transfer-encoding' || n == 'content-length' || n == 'connection') {
          return;
        }
        for (final v in values) {
          req.response.headers.add(name, v);
        }
      });
      await req.response.addStream(proxRes);
      await req.response.close();
      requestsServed++;
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
