# Symposium

**A gathering of minds.** Run local open-source LLMs, discover models running on other
devices on your network, compare two models side by side, and train your own small
model — all from one app that installs on Windows (`.exe`) and Android (`.apk`).

A **[Visionary Sparks](https://visionarysparks.in/symposium)** product — the hands-on
ML lab alongside [Classmate AI](https://visionarysparks.in). Free, open source, and
everything runs on your own hardware.

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
| 7 | Public downloads (Windows zip + Android APK via GitHub Releases) | ✅ |
| 8 | **Symposium Link** — join a friend's model across the internet with a short code (no port forwarding, no code); until then, join-by-IP works over the internet if the host forwards a port | planned |
| 9 | Packaged installers, signed APK, Play Store, CI | planned |

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

## Get it

**Download**: [Windows (.zip)](https://github.com/samaruban0317/symposium/releases/latest/download/Symposium-windows.zip) ·
[Android (.apk)](https://github.com/samaruban0317/symposium/releases/latest/download/Symposium-android.apk) ·
or visit [visionarysparks.in/symposium](https://visionarysparks.in/symposium).

Windows: extract the zip, install [Ollama](https://ollama.com) once (Symposium drives it — no terminal), run `symposium.exe`.
Android: install the APK; it auto-discovers any PC running Symposium in host mode on your Wi-Fi.

## Building from source

1. Install [Flutter](https://docs.flutter.dev/get-started/install/windows).
2. ```
   cd app
   flutter pub get
   flutter run -d windows
   ```

## Learning as you go

This project doubles as a course. [`docs/LEARN.md`](docs/LEARN.md) explains everything
from scratch — what a token is, how streaming works, why mDNS finds your friend's PC,
what a loss curve means — one chapter per phase, written for someone learning alongside
the code.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache-2.0](LICENSE) © Visionary Sparks (Samaruban) and contributors.
