/// App-facing auth state: who's signed in, and the JWT the engine attaches to
/// host requests. Login is OPTIONAL — everything works signed-out (guest tier);
/// signing in just unlocks the host's higher "student" tier.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import 'local_store.dart';

const _kSessionFile = 'auth_session.json';

final _authServiceProvider = Provider<AuthService>((_) => AuthService());

/// Holds the current [AuthSession] (or null when signed out). Restores a
/// persisted session on first build and refreshes it if it has expired.
class AuthController extends StateNotifier<AuthSession?> {
  final Ref ref;
  bool _busy = false;

  AuthController(this.ref) : super(null) {
    _restore();
  }

  bool get isBusy => _busy;

  AuthService get _svc => ref.read(_authServiceProvider);

  Future<void> _restore() async {
    final raw = await readData(_kSessionFile);
    if (raw == null) return;
    try {
      var session = AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (session.isExpired) {
        final refreshed = await _svc.refresh(session.refreshToken);
        if (refreshed == null) {
          await _clear();
          return;
        }
        session = refreshed;
        await _persist(session);
      }
      state = session;
    } catch (_) {
      await _clear(); // corrupt file — start signed-out
    }
  }

  /// Kicks off the browser sign-in. Rethrows [AuthException] for the UI.
  Future<void> signIn() async {
    if (_busy) return;
    _busy = true;
    try {
      final session = await _svc.signInWithGoogle();
      await _persist(session);
      state = session;
    } finally {
      _busy = false;
    }
  }

  Future<void> signOut() async {
    final token = state?.accessToken;
    state = null;
    await _clear();
    if (token != null) await _svc.signOut(token);
  }

  /// Returns a non-expired access token, refreshing on the fly if needed.
  Future<String?> validAccessToken() async {
    final s = state;
    if (s == null) return null;
    if (!s.isExpired) return s.accessToken;
    final refreshed = await _svc.refresh(s.refreshToken);
    if (refreshed == null) {
      await signOut();
      return null;
    }
    await _persist(refreshed);
    state = refreshed;
    return refreshed.accessToken;
  }

  Future<void> _persist(AuthSession s) => writeData(_kSessionFile, jsonEncode(s.toJson()));
  Future<void> _clear() => writeData(_kSessionFile, '');
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthSession?>((ref) => AuthController(ref));

/// The JWT to send to hosts as `Authorization: Bearer`, or null when signed
/// out. Watched by the engine so requests upgrade to the student tier the
/// moment a user signs in. (Refresh-on-expiry is handled lazily elsewhere; a
/// slightly-stale token still verifies within the host's own clock skew.)
final studentJwtProvider = Provider<String?>((ref) {
  final session = ref.watch(authControllerProvider);
  return session?.accessToken;
});
