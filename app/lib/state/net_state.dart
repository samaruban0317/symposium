import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/ollama_engine.dart';
import '../net/discovery.dart';
import '../net/host_limits.dart';
import '../net/host_server.dart';
import '../net/protocol.dart';

final _rng = Random.secure();

String _randomId() =>
    List.generate(16, (_) => '0123456789abcdef'[_rng.nextInt(16)]).join();

String _randomCode() => (100000 + _rng.nextInt(900000)).toString();

/// This app instance's identity on the network — only used so the scanner can
/// ignore its own host beacon.
final selfIdProvider = Provider<String>((_) => _randomId());

// ---------------------------------------------------------------------------
// Hosting: share this PC's local engine with the network
// ---------------------------------------------------------------------------

class HostState {
  final bool running;
  final String code;
  final int port;
  final String? error;

  /// This machine's LAN IPv4s — shown so a peer whose discovery is blocked
  /// (firewall, AP isolation) can still join by typing the address.
  final List<String> addresses;

  const HostState({
    required this.running,
    this.code = '',
    this.port = kProxyPort,
    this.error,
    this.addresses = const [],
  });
}

class HostController extends StateNotifier<HostState?> {
  final Ref ref;
  HostServer? _server;
  DiscoveryResponder? _responder;

  HostController(this.ref) : super(null);

  Future<void> enable() async {
    if (state?.running == true) return;
    const upstream = 'http://127.0.0.1:11434'; // always share the LOCAL engine
    final code = _randomCode();
    try {
      // Snapshot the local model list for the beacon, so peers see what's on
      // offer before they connect.
      var models = const <String>[];
      try {
        models = (await OllamaEngine(upstream).listModels()).map((m) => m.name).toList();
      } catch (_) {}

      final server = HostServer(
        upstream: upstream,
        pairingCode: code,
        limits: ref.read(hostLimitsProvider),
      );
      await server.start(kProxyPort);
      final responder = DiscoveryResponder(
        info: () => {
          'symposium': 'host',
          'v': 1,
          'id': ref.read(selfIdProvider),
          'name': Platform.localHostname,
          'port': kProxyPort,
          'pairing': true,
          'models': models,
        },
      );
      await responder.start();
      _server = server;
      _responder = responder;
      state = HostState(running: true, code: code, addresses: await lanAddresses());
    } catch (e) {
      await _server?.stop();
      _responder?.stop();
      _server = null;
      _responder = null;
      state = HostState(running: false, error: '$e');
    }
  }

  Future<void> disable() async {
    await _server?.stop();
    _responder?.stop();
    _server = null;
    _responder = null;
    state = null;
  }

  /// Live-apply new admin limits: persist them in the provider (so the next
  /// `enable()` also picks them up) and, if a server is already running, push
  /// them onto its mutable `limits` field — no restart, no dropped connection.
  void updateLimits(HostLimits limits) {
    ref.read(hostLimitsProvider.notifier).state = limits;
    _server?.limits = limits;
  }

  /// Live usage snapshot for the admin UI, or null when not hosting.
  Map<String, dynamic>? stats() => _server?.statsSnapshot();
}

/// Admin-set host policy (the "router admin page"). Seeded from defaults;
/// [HostController.enable] reads it when building the in-process [HostServer],
/// and [HostController.updateLimits] writes it back on live edits.
final hostLimitsProvider =
    StateProvider<HostLimits>((_) => HostLimits.defaults);

final hostControllerProvider =
    StateNotifierProvider<HostController, HostState?>((ref) => HostController(ref));

// ---------------------------------------------------------------------------
// Scanning: who else is out there?
// ---------------------------------------------------------------------------

final discoveredHostsProvider = StreamProvider<List<DiscoveredHost>>((ref) {
  final scanner = DiscoveryScanner(selfId: ref.watch(selfIdProvider));
  scanner.start();
  ref.onDispose(scanner.stop);
  return scanner.hosts;
});
