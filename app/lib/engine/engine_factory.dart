/// Turns a [ModelSource] into a ready engine. Call-signature is frozen
/// (consumers depend on it); the body belongs to the sources/engine layer.
library;

import '../models/source.dart';
import '../net/protocol.dart';
import '../state/sources_state.dart' show cloudHeadersFor;
import 'ollama_engine.dart';

OllamaEngine engineForSource(ModelSource s) => switch (s.kind) {
      SourceKind.cloud => OllamaEngine(
          s.baseUrl,
          headers: cloudHeadersFor(s),
          openAiCompat: true,
        ),
      _ => OllamaEngine(
          s.baseUrl,
          headers: {
            if (s.pairingCode != null) kPairingHeader: s.pairingCode!,
            if (s.adminToken != null) kAdminHeader: s.adminToken!,
          },
        ),
    };
