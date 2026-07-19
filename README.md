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
| 1 | Streaming chat with local models (Ollama engine), in-app model download, live tokens/sec | ✅ |
| 2 | **Host mode + peer discovery** — one toggle shares your PC's engine on the LAN (UDP discovery + pairing-code proxy); phones and other PCs find it and connect | ✅ |
| 3 | **Split screen & arena** — two panes, each bound to any PC + model on the network, duel mode (one prompt races both), voting scoreboard | ✅ |
| 4 | Deep interactivity — parameter lab (temperature/top-p/max-tokens/system prompt), regenerate, edit-and-resend, fork a conversation, streaming markdown | ✅ (first slice) |
| 4½ | **Cloud keys & personas** — paste an OpenAI/Gemini/Anthropic key and it becomes one more source (chat + arena); persona studio: tune instructions in a live edit-and-retest loop, share personas as small JSON files | ✅ |
| 4¾ | **Daily-driver release** — conversation history with Markdown export, full model-library browser (RAM-fit colored per device, vision/tools filters), image & PDF attachments for vision models, built-in resizable terminal, light/dark themes, join-by-IP pairing fallback, phone-first responsive UI | ✅ |
| 5 | Bundled llama.cpp engine — fully self-contained, no external installs | planned |
| 6 | **Training studio** — Python trainer service exists (tiny GPT, live-metrics WebSocket, chat with checkpoints); in-app UI next | ⏳ backend |
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
