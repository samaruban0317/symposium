# Symposium

**A gathering of minds.** Run local open-source LLMs, discover models running on other
devices on your network, compare two models side by side, and train your own small
model — all from one app that installs on Windows (`.exe`) and Android (`.apk`).

> *In Plato's Symposium, thinkers gathered to talk. Here, the thinkers are language
> models — yours, your friends', and eventually one you trained yourself.*

## Why

Local LLMs are amazing and mostly trapped behind terminals. Symposium's goal is that
**everything — installing a model, serving it to friends, comparing models, even
training one — happens by clicking inside the app.**

## Features (roadmap)

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Streaming chat with local models (Ollama engine), in-app model download, live tokens/sec | 🔨 in progress |
| 2 | **Host mode + network radar** — your PC advertises its models on the LAN (mDNS); phones and other PCs discover and connect | planned |
| 3 | **Split screen & arena** — two models side by side, race them on one prompt, vote | planned |
| 4 | Deep interactivity — token confidence heatmap, tap-to-see-alternatives, fork a conversation from any token, parameter lab | planned |
| 5 | Bundled llama.cpp engine — fully self-contained, no external installs | planned |
| 6 | **Training studio** — train a tiny GPT from scratch on your GPU, QLoRA fine-tuning, teacher/student split screen (synthetic data + LLM-as-judge) | planned |
| 7 | Packaged installers, signed APK, CI | planned |

## Architecture in one paragraph

Every model source — the engine on your own PC, a friend's PC in host mode, a training
checkpoint — is just an **OpenAI-compatible HTTP endpoint**. The Flutter app (one
codebase → `.exe` and `.apk`) is a universal client for those endpoints, plus a manager
that starts/stops engines locally and an mDNS layer that finds them on the network.
Training runs in a separate Python service (`trainer/`) that streams live metrics to
the app over WebSocket.

```
symposium/
  app/       Flutter app (Windows + Android)
  trainer/   Python training service (FastAPI + PyTorch)   [phase 6]
  docs/
    LEARN.md The full "teach me everything from scratch" companion book
```

## Getting started (Windows, phase 1)

1. Install [Ollama](https://ollama.com) (the app will manage models through it — no terminal needed).
2. Install [Flutter](https://docs.flutter.dev/get-started/install/windows) (only needed to build from source).
3. ```
   cd app
   flutter pub get
   flutter run -d windows
   ```

Pre-built installers arrive in phase 7.

## Learning as you go

This project doubles as a course. [`docs/LEARN.md`](docs/LEARN.md) explains everything
from scratch — what a token is, how streaming works, why mDNS finds your friend's PC,
what a loss curve means — one chapter per phase, written for someone learning alongside
the code.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache-2.0](LICENSE) © Samaruban and contributors.
