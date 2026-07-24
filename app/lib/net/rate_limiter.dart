/// A tiny in-memory fixed-window rate limiter.
///
/// Each key (guest = client IP, student = JWT `sub`) gets a counter that resets
/// at the end of its current window. Simpler and cheaper than a sliding window,
/// and good enough for "soft" per-tier throttling on a single-process host proxy.
/// State is per-isolate and non-persistent — a restart clears all counters,
/// which is fine for our scale.
class RateLimiter {
  final _windows = <String, _Window>{};

  /// Returns true if the request is allowed (and records it), false if the key
  /// has exceeded `limit` within the current `window`.
  bool allow(String key, int limit, Duration window) {
    final now = DateTime.now();
    final w = _windows[key];
    if (w == null || now.isAfter(w.resetAt)) {
      _windows[key] = _Window(count: 1, resetAt: now.add(window));
      return true;
    }
    if (w.count >= limit) return false;
    w.count++;
    return true;
  }

  /// Whole seconds until the key's current window resets (>= 0). Used for the
  /// `Retry-After` header on a 429. Returns 0 if the key is unknown.
  int retryAfterSeconds(String key) {
    final w = _windows[key];
    if (w == null) return 0;
    final secs = w.resetAt.difference(DateTime.now()).inSeconds;
    return secs < 0 ? 0 : secs;
  }
}

class _Window {
  int count;
  final DateTime resetAt;
  _Window({required this.count, required this.resetAt});
}
