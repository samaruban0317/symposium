/// Pure-Dart Google sign-in against the shared Supabase project — no
/// supabase_flutter SDK, no new native plugins (keeps Windows builds simple).
///
/// It runs the OAuth **PKCE** flow by hand:
///   1. mint a random `code_verifier` and its S256 `code_challenge`,
///   2. open the system browser at Supabase's `/auth/v1/authorize?provider=google`
///      with a `http://localhost:<port>/callback` redirect,
///   3. catch the redirect on a one-shot loopback HTTP server → grab `?code=`,
///   4. exchange the code (+ verifier) for a session at `/auth/v1/token`.
///
/// The returned access_token is a Supabase JWT — exactly what the Symposium
/// host's "student" tier verifies. Refresh is a second token call.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'supabase_config.dart';

/// A signed-in Supabase session. Persisted as JSON so a restart stays logged in.
class AuthSession {
  final String accessToken; // the JWT sent to hosts as `Authorization: Bearer`
  final String refreshToken;
  final DateTime expiresAt;
  final String? email;
  final String? userId;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.email,
    this.userId,
  });

  /// True within a 60s skew — refresh a little early rather than mid-request.
  bool get isExpired => DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 60)));

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
        'email': email,
        'user_id': userId,
      };

  static AuthSession fromJson(Map<String, dynamic> j) => AuthSession(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        email: j['email'] as String?,
        userId: j['user_id'] as String?,
      );

  /// Build from a Supabase `/token` response body.
  static AuthSession fromTokenResponse(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>?;
    final expiresIn = (j['expires_in'] as num?)?.toInt() ?? 3600;
    return AuthSession(
      accessToken: j['access_token'] as String,
      refreshToken: j['refresh_token'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      email: user?['email'] as String?,
      userId: user?['id'] as String?,
    );
  }
}

/// Thrown for any expected sign-in failure (cancelled, provider error, etc.)
/// so the UI can show a friendly message instead of a raw stack trace.
class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  final _rng = Random.secure();

  // ---- PKCE helpers -------------------------------------------------------

  String _randomVerifier() {
    // 64 chars from the unreserved set — well within PKCE's 43..128 range.
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(64, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  String _challenge(String verifier) =>
      base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

  // ---- Sign in ------------------------------------------------------------

  /// Runs the full browser flow and returns a live session. Binds the loopback
  /// server FIRST (so we never miss the redirect), then opens the browser.
  Future<AuthSession> signInWithGoogle() async {
    final verifier = _randomVerifier();
    final challenge = _challenge(verifier);

    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, kOAuthLoopbackPort);
    } on SocketException {
      throw AuthException(
          'Port $kOAuthLoopbackPort is busy — close whatever is using it and try again.');
    }

    try {
      final authorize = Uri.parse('$kSupabaseUrl/auth/v1/authorize').replace(queryParameters: {
        'provider': 'google',
        'redirect_to': kOAuthRedirect,
        'code_challenge': challenge,
        'code_challenge_method': 's256',
      });

      if (!await launchUrl(authorize, mode: LaunchMode.externalApplication)) {
        throw AuthException('Could not open the browser for Google sign-in.');
      }

      final code = await _awaitRedirectCode(server)
          .timeout(const Duration(minutes: 5), onTimeout: () {
        throw AuthException('Sign-in timed out — no response from the browser.');
      });

      return _exchangeCode(code, verifier);
    } finally {
      await server.close(force: true);
    }
  }

  /// Serve requests until the OAuth callback arrives; return its `code`. Any
  /// `error` param (e.g. the user declined) is surfaced as an [AuthException].
  Future<String> _awaitRedirectCode(HttpServer server) async {
    await for (final req in server) {
      final params = req.uri.queryParameters;
      final code = params['code'];
      final error = params['error_description'] ?? params['error'];

      req.response.headers.contentType = ContentType.html;
      req.response.write(_closeTabHtml(ok: code != null && error == null));
      await req.response.close();

      if (error != null) throw AuthException('Google sign-in failed: $error');
      if (code != null) return code;
      // Ignore favicon / stray hits and keep waiting.
    }
    throw AuthException('Sign-in was cancelled.');
  }

  Future<AuthSession> _exchangeCode(String code, String verifier) async {
    final res = await http.post(
      Uri.parse('$kSupabaseUrl/auth/v1/token?grant_type=pkce'),
      headers: {'apikey': kSupabaseAnonKey, 'Content-Type': 'application/json'},
      body: jsonEncode({'auth_code': code, 'code_verifier': verifier}),
    );
    if (res.statusCode != 200) {
      throw AuthException('Token exchange failed (${res.statusCode}). ${_errBody(res.body)}');
    }
    return AuthSession.fromTokenResponse(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ---- Refresh ------------------------------------------------------------

  /// Trade a refresh token for a fresh session. Returns null if the refresh
  /// token is no longer valid (caller should treat that as signed-out).
  Future<AuthSession?> refresh(String refreshToken) async {
    final res = await http.post(
      Uri.parse('$kSupabaseUrl/auth/v1/token?grant_type=refresh_token'),
      headers: {'apikey': kSupabaseAnonKey, 'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    if (res.statusCode != 200) return null;
    return AuthSession.fromTokenResponse(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ---- Sign out -----------------------------------------------------------

  /// Best-effort server-side revoke; local state is cleared by the caller.
  Future<void> signOut(String accessToken) async {
    try {
      await http.post(
        Uri.parse('$kSupabaseUrl/auth/v1/logout'),
        headers: {'apikey': kSupabaseAnonKey, 'Authorization': 'Bearer $accessToken'},
      );
    } catch (_) {
      // Network hiccup on logout shouldn't block signing out locally.
    }
  }

  String _errBody(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      return (j['error_description'] ?? j['msg'] ?? j['error'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  String _closeTabHtml({required bool ok}) => '''
<!doctype html><html><head><meta charset="utf-8"><title>Symposium</title>
<style>body{font-family:system-ui,sans-serif;background:#0E1516;color:#e6efee;
display:grid;place-items:center;height:100vh;margin:0}
.card{text-align:center}h1{color:#2AB7B0;font-weight:600}</style></head>
<body><div class="card"><h1>Symposium</h1>
<p>${ok ? 'Signed in — you can close this tab and return to the app.' : 'Sign-in failed. You can close this tab and try again.'}</p>
</div></body></html>''';
}
