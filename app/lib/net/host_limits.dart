/// Admin-set host policy — think of it as the "router admin page" for a
/// Symposium host. The person running the box decides how much of their
/// machine + bandwidth to lend out: how many people can connect at once, how
/// many can join per day, a daily request cap (the "data cap"), and per-tier
/// quotas. Nothing here is a secret — it's configuration, serialised to/from
/// JSON for the admin endpoints and the headless config file.
///
/// Convention: `0` means "unlimited" for every numeric cap, so an admin can
/// dial any single control off without special-casing.
///
/// Pure Dart (no Flutter) so the proxy, the headless entrypoint, and any
/// tooling can all share it.
library;

/// Small models a guest may chat with (case-insensitive prefix match on the
/// requested model name). Lives here so limits + allowlist travel together.
const List<String> kDefaultGuestModels = [
  'llama3.2:1b',
  'gemma3:1b',
  'gemma3:4b',
  'qwen2.5:0.5b',
  'qwen2.5:1.5b',
];

class HostLimits {
  /// Max concurrent in-flight requests across everyone (0 = unlimited).
  final int maxConnections;

  /// Max distinct non-admin identities (guest IPs + student subs) allowed per
  /// day. A new identity beyond this is turned away for the day (0 = unlimited).
  final int maxUsersPerDay;

  /// Max total non-admin requests per day across the whole host — the "data
  /// cap". Once hit, non-admins get 503 until the day rolls over (0 = unlimited).
  final int dailyTotalCap;

  /// Per guest IP: requests per hour (0 = unlimited).
  final int guestPerHour;

  /// Per student (JWT sub): requests per day (0 = unlimited).
  final int studentPerDay;

  /// Models a guest may chat with. Students/admins are unrestricted.
  final List<String> guestModels;

  /// The model the host recommends every joining client start on. Empty = no
  /// preference (clients fall back to their own first-model default). This is
  /// how the admin says "use THIS model" — surfaced to clients via
  /// `/v1/mobile/config`, so a phone that just paired lands on the right model
  /// instead of blindly picking the first (possibly non-allowlisted) one.
  final String defaultModel;

  const HostLimits({
    this.maxConnections = 8,
    this.maxUsersPerDay = 25,
    this.dailyTotalCap = 1000,
    this.guestPerHour = 15,
    this.studentPerDay = 150,
    this.guestModels = kDefaultGuestModels,
    this.defaultModel = '',
  });

  /// Sensible "lending a friend some of my PC" defaults.
  static const HostLimits defaults = HostLimits();

  HostLimits copyWith({
    int? maxConnections,
    int? maxUsersPerDay,
    int? dailyTotalCap,
    int? guestPerHour,
    int? studentPerDay,
    List<String>? guestModels,
    String? defaultModel,
  }) =>
      HostLimits(
        maxConnections: maxConnections ?? this.maxConnections,
        maxUsersPerDay: maxUsersPerDay ?? this.maxUsersPerDay,
        dailyTotalCap: dailyTotalCap ?? this.dailyTotalCap,
        guestPerHour: guestPerHour ?? this.guestPerHour,
        studentPerDay: studentPerDay ?? this.studentPerDay,
        guestModels: guestModels ?? this.guestModels,
        defaultModel: defaultModel ?? this.defaultModel,
      );

  Map<String, dynamic> toJson() => {
        'max_connections': maxConnections,
        'max_users_per_day': maxUsersPerDay,
        'daily_total_cap': dailyTotalCap,
        'guest_per_hour': guestPerHour,
        'student_per_day': studentPerDay,
        'guest_models': guestModels,
        'default_model': defaultModel,
      };

  /// Tolerant parser — any missing field keeps the current default, so a
  /// partial `POST /v1/host/limits` body only changes what it names.
  factory HostLimits.fromJson(Map<String, dynamic> j, {HostLimits base = HostLimits.defaults}) {
    int asInt(String k, int fallback) {
      final v = j[k];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    final models = j['guest_models'];
    final def = j['default_model'];
    return HostLimits(
      maxConnections: asInt('max_connections', base.maxConnections),
      maxUsersPerDay: asInt('max_users_per_day', base.maxUsersPerDay),
      dailyTotalCap: asInt('daily_total_cap', base.dailyTotalCap),
      guestPerHour: asInt('guest_per_hour', base.guestPerHour),
      studentPerDay: asInt('student_per_day', base.studentPerDay),
      guestModels: models is List && models.isNotEmpty
          ? models.map((e) => e.toString()).toList()
          : base.guestModels,
      defaultModel: def is String ? def : base.defaultModel,
    );
  }
}
