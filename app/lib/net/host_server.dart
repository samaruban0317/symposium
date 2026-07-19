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

  HttpServer? _server;
  final _client = HttpClient();
  int requestsServed = 0;

  HostServer({required this.upstream, required this.pairingCode});

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
        ..set('Access-Control-Allow-Headers', 'content-type, authorization, $kPairingHeader')
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

      final target = Uri.parse(upstream).replace(
        path: req.uri.path,
        query: req.uri.hasQuery ? req.uri.query : null,
      );
      final proxReq = await _client.openUrl(req.method, target);
      req.headers.forEach((name, values) {
        final n = name.toLowerCase();
        if (n == 'host' || n == 'connection' || n == kPairingHeader) return;
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
