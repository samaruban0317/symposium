import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

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

  void _probe() {
    final data = utf8.encode(jsonEncode({'symposium': 'discover', 'v': 1}));
    try {
      _sock?.send(data, InternetAddress('255.255.255.255'), kDiscoveryPort);
      // Loopback too, so a host on this same machine is found even where
      // broadcast doesn't loop back.
      _sock?.send(data, InternetAddress.loopbackIPv4, kDiscoveryPort);
    } catch (_) {
      // e.g. network interface momentarily down; next tick retries.
    }
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
