import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Minimal, dependency-light HS256 JWT verifier.
///
/// We only need to trust Supabase-issued student tokens, so a full JWT library
/// is overkill (and would drag in extra deps). This verifies the HMAC-SHA256
/// signature over `header.payload` with the shared `SUPABASE_JWT_SECRET`, then
/// checks `exp` / `nbf`. It returns the decoded claims map (use `sub` as the
/// per-user rate-limit key) or `null` on ANY failure — malformed token, bad
/// signature, or expired. Never throws.
///
/// Deliberately does NOT validate `iss`/`aud`; the pairing code is still the
/// base gate and this is "soft" auth (tier upgrade), not a security boundary.
Map<String, dynamic>? verifyJwtHs256(String token, String secret) {
  if (secret.isEmpty) return null;
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final signingInput = '${parts[0]}.${parts[1]}';
    // Recompute the signature and compare (base64url, no padding).
    final mac = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode(signingInput));
    final expected = base64Url.encode(mac.bytes).replaceAll('=', '');
    if (expected != parts[2]) return null;

    final claims = jsonDecode(utf8.decode(_b64urlDecode(parts[1])))
        as Map<String, dynamic>;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final exp = (claims['exp'] as num?)?.toInt();
    if (exp != null && now >= exp) return null; // expired
    final nbf = (claims['nbf'] as num?)?.toInt();
    if (nbf != null && now < nbf) return null; // not yet valid
    return claims;
  } catch (_) {
    return null;
  }
}

/// base64url-decode a JWT segment, tolerating the missing `=` padding.
List<int> _b64urlDecode(String s) {
  final pad = (4 - s.length % 4) % 4;
  return base64Url.decode(s + '=' * pad);
}
