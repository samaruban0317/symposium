import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// IPv4 addresses this device holds on real network interfaces — what a peer
/// would type to reach us, and the subnets worth probing for hosts.
Future<List<String>> lanAddresses() async {
  try {
    final ifaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    return [
      for (final i in ifaces)
        for (final a in i.addresses)
          if (!a.isLoopback) a.address,
    ];
  } catch (_) {
    return const [];
  }
}

/// Host side: answers "who's out there?" probes with this machine's details.
class DiscoveryResponder {
  final Map<String, dynamic> Function() info;
  RawDatagramSocket? _sock;

  DiscoveryResponder({required this.info});

  Future<void> start() async {
    final sock = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kDiscoveryPort,
      reuseAddress: true,
    );
    _sock = sock;
    sock.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = sock.receive();
      if (dg == null) return;
      try {
        final j = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
        if (j['symposium'] == 'discover') {
          sock.send(utf8.encode(jsonEncode(info())), dg.address, dg.port);
        }
      } catch (_) {
        // Not our packet; someone else's UDP noise.
      }
    });
  }

  void stop() {
    _sock?.close();
    _sock = null;
  }
}

/// Client side: broadcasts probes every few seconds and collects replies.
/// Hosts that stop answering fall off the list after [staleAfter].
class DiscoveryScanner {
  final String selfId; // so you don't "discover" yourself
  final Duration probeEvery;
  final Duration staleAfter;

  final _hosts = <String, DiscoveredHost>{};
  final _controller = StreamController<List<DiscoveredHost>>.broadcast();
  RawDatagramSocket? _sock;
  Timer? _timer;

  DiscoveryScanner({
    required this.selfId,
    this.probeEvery = const Duration(seconds: 3),
    this.staleAfter = const Duration(seconds: 10),
  });

  Stream<List<DiscoveredHost>> get hosts => _controller.stream;

  Future<void> start() async {
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    sock.broadcastEnabled = true;
    _sock = sock;
    sock.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = sock.receive();
      if (dg == null) return;
      try {
        final j = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
        final host = DiscoveredHost.fromJson(j, dg.address.address);
        if (host != null && host.id != selfId) {
          _hosts[host.id] = host;
          _emit();
        }
      } catch (_) {}
    });
    _probe();
    _timer = Timer.periodic(probeEvery, (_) {
      _probe();
      _prune();
    });
  }

  Future<void> _probe() async {
    final data = utf8.encode(jsonEncode({'symposium': 'discover', 'v': 1}));
    try {
      _sock?.send(data, InternetAddress('255.255.255.255'), kDiscoveryPort);
      // Loopback too, so a host on this same machine is found even where
      // broadcast doesn't loop back.
      _sock?.send(data, InternetAddress.loopbackIPv4, kDiscoveryPort);
    } catch (_) {
      // e.g. network interface momentarily down; next tick retries.
    }
    // The limited broadcast above is dropped by many Android builds and some
    // routers. Subnet-directed broadcasts (x.y.z.255) survive far more often,
    // so probe every interface's /24 as well — phone↔laptop on home Wi-Fi is
    // exactly this case.
    try {
      for (final addr in await lanAddresses()) {
        final parts = addr.split('.')..removeLast();
        final directed = '${parts.join('.')}.255';
        try {
          _sock?.send(data, InternetAddress(directed), kDiscoveryPort);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(staleAfter);
    final before = _hosts.length;
    _hosts.removeWhere((_, h) => h.lastSeen.isBefore(cutoff));
    if (_hosts.length != before) _emit();
  }

  void _emit() {
    final list = _hosts.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    _controller.add(list);
  }

  void stop() {
    _timer?.cancel();
    _sock?.close();
    _sock = null;
  }
}
