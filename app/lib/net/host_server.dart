import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'jwt.dart';
import 'protocol.dart';
import 'rate_limiter.dart';

/// The three trust tiers a request can resolve to. All non-preflight requests
/// still need the pairing code first; the tier layers on top of that.
enum Tier { guest, student, admin }

/// Default small-model allowlist guests may chat with (case-insensitive prefix
/// match on the requested model name). Keeps friends off the host's big models.
const List<String> kDefaultGuestModels = [
  'llama3.2:1b',
  'gemma3:1b',
  'gemma3:4b',
  'qwen2.5:0.5b',
  'qwen2.5:1.5b',
];

/// The heart of "host mode": a tiny reverse proxy.
///
/// Ollama only listens on localhost — sensible security, but it means a friend
/// can't reach it. Instead of asking anyone to reconfigure Ollama (breaking the
/// "no terminal" promise), Symposium listens on all interfaces itself and
/// forwards each request to the local engine, first checking the 6-digit
/// pairing code. Streaming (SSE / NDJSON) passes straight through because both
/// directions are piped as byte streams, never buffered whole.
///
/// On top of the pairing gate it resolves a [Tier] per request:
///   • Admin   — valid `x-symposium-admin`; bypasses all limits, all endpoints.
///   • Student — valid unexpired `Authorization: Bearer <jwt>` (HS256 vs
///               [jwtSecret]); [studentPerDay] req/day; management still denied.
///   • Guest   — pairing code only; [guestPerHour] req/hour; management denied
///               and chat restricted to the small-model allowlist.
class HostServer {
  final String upstream; // the host's local engine, e.g. http://127.0.0.1:11434
  final String pairingCode;
  // Admin token for management endpoints. Empty = no admin → management denied
  // for everyone (friends are viewer-only: chat/read yes, pull/delete no).
  final String adminToken;
  // Shared secret for verifying student JWTs (Supabase). Empty = student tier
  // disabled → JWT holders are treated as guests.
  final String jwtSecret;
  // Per-tier rate limits (admins are unlimited).
  final int guestPerHour;
  final int studentPerDay;
  // Small models guests may chat with (case-insensitive prefix match).
  final List<String> guestModels;

  HttpServer? _server;
  final _client = HttpClient();
  final _limiter = RateLimiter();
  int requestsServed = 0;

  HostServer({
    required this.upstream,
    required this.pairingCode,
    this.adminToken = '',
    this.jwtSecret = '',
    this.guestPerHour = 15,
    this.studentPerDay = 150,
    List<String>? guestModels,
  }) : guestModels = guestModels ?? kDefaultGuestModels;

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

  /// Chat/generate endpoints whose body carries a `model` — the ones the guest
  /// allowlist must inspect (so we buffer the full body for these paths only).
  bool _isChatGenerate(String method, String path) {
    if (method.toUpperCase() != 'POST') return false;
    var p = path.toLowerCase();
    if (!p.startsWith('/')) p = '/$p';
    return p == '/api/chat' ||
        p == '/api/generate' ||
        p == '/v1/chat/completions';
  }

  /// True if `model` is on the guest allowlist (case-insensitive prefix match).
  bool _guestModelAllowed(String? model) {
    if (model == null || model.isEmpty) return false;
    final m = model.toLowerCase();
    for (final allowed in guestModels) {
      if (m.startsWith(allowed.toLowerCase())) return true;
    }
    return false;
  }

  Future<void> start(int port) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  /// Resolve the caller's tier AFTER the pairing check has passed. Order matters:
  /// admin token wins, then a valid student JWT, else guest. Returns the tier and
  /// the rate-limit key (JWT `sub` for students, client IP for guests; admins
  /// aren't limited so their key is unused).
  ({Tier tier, String key}) _resolveTier(HttpRequest req) {
    // Admin: header present and equal to a non-empty admin token.
    if (adminToken.isNotEmpty &&
        req.headers.value(kAdminHeader) == adminToken) {
      return (tier: Tier.admin, key: 'admin');
    }
    // Student: a Bearer JWT that verifies and is unexpired (secret configured).
    final auth = req.headers.value(HttpHeaders.authorizationHeader);
    if (jwtSecret.isNotEmpty && auth != null && auth.startsWith('Bearer ')) {
      final claims = verifyJwtHs256(auth.substring(7).trim(), jwtSecret);
      if (claims != null) {
        final sub = (claims['sub'] as String?) ?? 'unknown';
        return (tier: Tier.student, key: 'student:$sub');
      }
    }
    // Guest: keyed by client IP (first X-Forwarded-For hop behind Caddy).
    return (tier: Tier.guest, key: 'guest:${_clientIp(req)}');
  }

  /// Client IP for guest rate-limiting: prefer the first hop of X-Forwarded-For
  /// (we sit behind Caddy), else the raw connection address.
  String _clientIp(HttpRequest req) {
    final xff = req.headers.value('x-forwarded-for');
    if (xff != null && xff.trim().isNotEmpty) {
      return xff.split(',').first.trim();
    }
    return req.connectionInfo?.remoteAddress.address ?? 'unknown';
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
        ..set('Access-Control-Allow-Headers',
            'content-type, authorization, $kPairingHeader, $kAdminHeader')
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
            'error':
                'pairing code missing or wrong — ask the host for the 6-digit code'
          }));
        await req.response.close();
        return;
      }

      final resolved = _resolveTier(req);
      final tier = resolved.tier;

      // Our own route: mobile config. Answered by the proxy, not forwarded.
      if (req.method == 'GET' && req.uri.path.toLowerCase() == '/v1/mobile/config') {
        await _serveMobileConfig(req, tier);
        return;
      }

      // Viewer/admin policy: management endpoints need the admin tier.
      if (_isManagement(req.method, req.uri.path) && tier != Tier.admin) {
        req.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'error': 'admin token required — this host is viewer-only for you'
          }));
        await req.response.close();
        return;
      }

      // Rate limiting: admins bypass; students/guests use fixed-window counters.
      if (tier != Tier.admin) {
        final limit = tier == Tier.student ? studentPerDay : guestPerHour;
        final window =
            tier == Tier.student ? const Duration(days: 1) : const Duration(hours: 1);
        final windowLabel = tier == Tier.student ? 'day' : 'hour';
        if (!_limiter.allow(resolved.key, limit, window)) {
          final retry = _limiter.retryAfterSeconds(resolved.key);
          req.response
            ..statusCode = HttpStatus.tooManyRequests
            ..headers.contentType = ContentType.json
            ..headers.set('Retry-After', '$retry')
            ..write(jsonEncode({
              'error':
                  'rate limit reached — tier ${tier.name}, limit $limit/$windowLabel'
            }));
          await req.response.close();
          return;
        }
      }

      // Guest small-model allowlist: for chat/generate we must read the body to
      // learn the model. Buffer the FULL body, parse JSON, enforce, then forward
      // the buffered bytes. Non-chat paths keep straight-through piping.
      List<int>? bufferedBody;
      if (_isChatGenerate(req.method, req.uri.path)) {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in req) {
          builder.add(chunk);
        }
        bufferedBody = builder.takeBytes();
        if (tier == Tier.guest) {
          String? model;
          try {
            final decoded = jsonDecode(utf8.decode(bufferedBody));
            if (decoded is Map) model = decoded['model'] as String?;
          } catch (_) {
            // Fail OPEN on non-JSON / unparseable bodies — don't break requests.
            model = null;
          }
          // Only enforce when we actually parsed a model. A missing/unparseable
          // model falls through (fail-open) rather than blocking.
          if (model != null && !_guestModelAllowed(model)) {
            req.response
              ..statusCode = HttpStatus.forbidden
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'error':
                    'guest tier is limited to small models — "$model" is not allowed. '
                        'Log in as a student, or pick one of: ${guestModels.join(", ")}',
                'small_models': guestModels,
              }));
            await req.response.close();
            return;
          }
        }
      }

      final target = Uri.parse(upstream).replace(
        path: req.uri.path,
        query: req.uri.hasQuery ? req.uri.query : null,
      );
      final proxReq = await _client.openUrl(req.method, target);
      req.headers.forEach((name, values) {
        final n = name.toLowerCase();
        // Strip hop-by-hop + our own auth headers so they never reach Ollama.
        if (n == 'host' ||
            n == 'connection' ||
            n == 'authorization' ||
            n == kPairingHeader ||
            n == kAdminHeader) {
          return;
        }
        // If we buffered the body, drop the original content-length; we set our
        // own from the buffered bytes below.
        if (bufferedBody != null && n == 'content-length') return;
        for (final v in values) {
          proxReq.headers.add(name, v);
        }
      });
      if (bufferedBody != null) {
        proxReq.headers.contentLength = bufferedBody.length;
        proxReq.add(bufferedBody);
        await proxReq.flush();
      } else {
        await proxReq.addStream(req);
      }
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

  /// GET /v1/mobile/config — answered by the proxy itself (never forwarded).
  /// Tells a mobile/web client its resolved tier, the guest small-model
  /// allowlist, the per-tier limits, and a `recommend` hint. The client decides
  /// (based on device RAM) whether to honour the WebLLM hint and run models
  /// on-device, or fall back to this cloud host.
  Future<void> _serveMobileConfig(HttpRequest req, Tier tier) async {
    // Capable clients can run small models client-side (WebLLM); low-RAM
    // devices should use this cloud host. Static hint — the client decides.
    final recommend = tier == Tier.guest ? 'webllm' : 'cloud';
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'tier': tier.name,
        'small_models': guestModels,
        'limits': {
          'guest_per_hour': guestPerHour,
          'student_per_day': studentPerDay,
          'admin': 'unlimited',
        },
        'recommend': recommend,
      }));
    await req.response.close();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
