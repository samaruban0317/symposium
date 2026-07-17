// Headless self-check for the phase-2 networking stack. Run from app/:
//
//   dart run tool/netcheck.dart
//
// Spins up a real HostServer + DiscoveryResponder, then acts as the "phone":
// discovers the host via UDP broadcast, is rejected without the pairing code,
// and streams real model output through the proxy with it. Requires Ollama
// running locally with at least one model.
import 'dart:convert';
import 'dart:io';

import 'package:symposium/net/discovery.dart';
import 'package:symposium/net/host_server.dart';
import 'package:symposium/net/protocol.dart';

Future<void> main() async {
  var failed = false;
  void check(String name, bool ok, [String detail = '']) {
    stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $name${detail.isEmpty ? '' : '  ($detail)'}');
    if (!ok) failed = true;
  }

  const upstream = 'http://127.0.0.1:11434';
  const code = '424242';
  const port = 47999; // off the real port so a running app doesn't collide

  // --- host side ---
  final server = HostServer(upstream: upstream, pairingCode: code);
  await server.start(port);
  final responder = DiscoveryResponder(
    info: () => {
      'symposium': 'host',
      'v': 1,
      'id': 'netcheck-host',
      'name': 'netcheck',
      'port': port,
      'pairing': true,
      'models': ['test-model'],
    },
  );
  await responder.start();

  // --- client side: discovery ---
  final scanner = DiscoveryScanner(selfId: 'netcheck-client');
  await scanner.start();
  DiscoveredHost? found;
  try {
    found = (await scanner.hosts
            .firstWhere((l) => l.isNotEmpty)
            .timeout(const Duration(seconds: 8)))
        .first;
  } catch (_) {}
  check('discovery: probe finds host via UDP', found != null,
      found == null ? 'no reply in 8s' : '${found.name}@${found.address}:${found.port}');

  // --- client side: proxy auth ---
  final http = HttpClient();
  Future<(int, String)> get(String path, {String? withCode}) async {
    final req = await http.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    if (withCode != null) req.headers.set(kPairingHeader, withCode);
    final res = await req.close();
    return (res.statusCode, await res.transform(utf8.decoder).join());
  }

  final (noCodeStatus, _) = await get('/api/tags');
  check('proxy: rejects request without pairing code', noCodeStatus == 401);

  final (wrongStatus, _) = await get('/api/tags', withCode: '000000');
  check('proxy: rejects wrong pairing code', wrongStatus == 401);

  final (okStatus, okBody) = await get('/api/tags', withCode: code);
  check('proxy: forwards to local engine with code',
      okStatus == 200 && okBody.contains('models'),
      'status $okStatus');

  // --- streaming end-to-end through the proxy ---
  var streamed = 0;
  try {
    final models =
        (jsonDecode(okBody)['models'] as List).map((m) => m['name'] as String).toList();
    final req = await http.postUrl(Uri.parse('http://127.0.0.1:$port/v1/chat/completions'));
    req.headers.set(kPairingHeader, code);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({
      'model': models.first,
      'stream': true,
      'max_tokens': 30,
      'messages': [
        {'role': 'user', 'content': 'Count from 1 to 5.'}
      ],
    }));
    final res = await req.close();
    await for (final line in res
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 120))) {
      if (line.startsWith('data:') && !line.contains('[DONE]')) streamed++;
    }
  } catch (e) {
    stdout.writeln('       streaming error: $e');
  }
  check('proxy: streams SSE chat end-to-end', streamed > 3, '$streamed chunks');

  // --- teardown ---
  scanner.stop();
  responder.stop();
  await server.stop();
  http.close(force: true);
  stdout.writeln(failed ? '\nNETCHECK FAILED' : '\nNETCHECK OK');
  exit(failed ? 1 : 0);
}
