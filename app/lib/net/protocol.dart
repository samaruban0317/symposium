/// Symposium's LAN protocol. Pure Dart, no Flutter imports.
///
/// Discovery is a deliberately tiny UDP scheme rather than mDNS: both ends run
/// our code, so we don't need interop with Bonjour/Avahi — and a 30-line
/// broadcast protocol has no native-plugin dependency and fewer ways to fail
/// on consumer routers.
///
///   client ──(UDP broadcast :47474)──▶  {"symposium":"discover","v":1}
///   host   ──(UDP unicast reply)─────▶  {"symposium":"host","v":1,"id":…,
///                                        "name":…,"port":47475,"pairing":true,
///                                        "models":[…]}
///
/// Chat traffic then flows over plain HTTP to the host's reverse proxy
/// (port 47475), which forwards to the host's local engine and rejects
/// requests missing the 6-digit pairing code header.
library;

const int kDiscoveryPort = 47474;
const int kProxyPort = 47475;
const String kPairingHeader = 'x-symposium-code';

class DiscoveredHost {
  final String id; // random per-session id, used to hide your own beacon
  final String name;
  final String address;
  final int port;
  final bool pairing;
  final List<String> models;
  final DateTime lastSeen;

  const DiscoveredHost({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.pairing,
    required this.models,
    required this.lastSeen,
  });

  String get baseUrl => 'http://$address:$port';

  static DiscoveredHost? fromJson(Map<String, dynamic> j, String address) {
    if (j['symposium'] != 'host' || j['id'] is! String) return null;
    return DiscoveredHost(
      id: j['id'] as String,
      name: j['name'] as String? ?? 'unknown host',
      address: address,
      port: (j['port'] as num?)?.toInt() ?? kProxyPort,
      pairing: j['pairing'] as bool? ?? false,
      models: (j['models'] as List? ?? []).cast<String>(),
      lastSeen: DateTime.now(),
    );
  }
}
