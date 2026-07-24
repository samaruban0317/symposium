import 'host_server.dart' show Tier;

/// In-memory usage accounting for a single host, with automatic daily rollover.
///
/// The [HostServer] owns exactly one of these. It answers three questions the
/// admin caps care about: how many requests have run today (the "data cap"),
/// how many distinct people showed up today (the "max users/day" cap), and how
/// many requests are in flight right now (the "max connections" cap).
///
/// Everything is per-calendar-day: the first call on a new local day silently
/// resets today's totals + the unique-identity set before recording anything.
/// Admins are never counted here — the caps only apply to guests/students.
///
/// Pure Dart, no persistence: a host restart starts the day's tallies fresh,
/// which is fine for a "lend a friend my PC" tool.
class UsageTracker {
  // The calendar day (year-month-day) the current tallies belong to. When the
  // real day moves past this, [_rollIfNewDay] zeroes everything.
  DateTime _day = _today();

  int _todayTotal = 0;
  final Map<Tier, int> _todayByTier = {
    Tier.guest: 0,
    Tier.student: 0,
    Tier.admin: 0,
  };
  // Distinct non-admin identity keys seen today (guest IPs + student subs). Used
  // both for `uniqueUsersToday` and the max-users-per-day admissions check.
  final Set<String> _identitiesToday = <String>{};

  // Requests currently being proxied. Bumped just before forwarding and always
  // dropped in a `finally`, so a crash mid-request can't leak the count.
  int _inFlight = 0;

  /// Midnight of the local calendar day, used as the rollover key.
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Reset today's tallies if the calendar day has changed since we last looked.
  void _rollIfNewDay() {
    final now = _today();
    if (now != _day) {
      _day = now;
      _todayTotal = 0;
      _todayByTier[Tier.guest] = 0;
      _todayByTier[Tier.student] = 0;
      _todayByTier[Tier.admin] = 0;
      _identitiesToday.clear();
    }
  }

  /// True if [key] has already been counted as a user today (so it passes the
  /// max-users cap even when the cap is otherwise full).
  bool isKnownToday(String key) {
    _rollIfNewDay();
    return _identitiesToday.contains(key);
  }

  /// Distinct non-admin identities seen today.
  int get uniqueUsersToday {
    _rollIfNewDay();
    return _identitiesToday.length;
  }

  /// Total non-admin requests served today (the daily "data cap" counter).
  int get todayTotal {
    _rollIfNewDay();
    return _todayTotal;
  }

  /// Per-tier request counts for today.
  Map<Tier, int> get todayByTier {
    _rollIfNewDay();
    return _todayByTier;
  }

  /// Requests currently being proxied.
  int get inFlight => _inFlight;

  /// Record a request that has PASSED the caps and is about to be served: bump
  /// the day total + the tier count, and remember non-admin identities so the
  /// max-users cap sees them next time. Admin identities are never tracked.
  void record(Tier tier, String key) {
    _rollIfNewDay();
    _todayTotal++;
    _todayByTier[tier] = (_todayByTier[tier] ?? 0) + 1;
    if (tier != Tier.admin) _identitiesToday.add(key);
  }

  /// Bump the live in-flight counter around the actual proxying.
  void enter() => _inFlight++;

  /// Drop the in-flight counter — call from a `finally` so it can't leak.
  void leave() {
    if (_inFlight > 0) _inFlight--;
  }
}
