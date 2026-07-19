# Contributing to Symposium

Thanks for even reading this file. Symposium is a young [Visionary Sparks](https://visionarysparks.in/symposium)
project built in public by people learning as they go — contributions of every size
are welcome, including "this doc confused me" issues.

## Ways to help

- **Try it and report** — install, break it, open an issue with what happened.
- **Docs** — `docs/LEARN.md` aims to teach everything from scratch. Unclear passages
  are bugs; fix or report them.
- **Code** — pick an open issue or a roadmap item from the README table. Comment on
  the issue first for anything larger than a small fix so we don't duplicate work.

## Project layout

- `app/` — Flutter app (Windows + Android). State management is Riverpod; every model
  source is an "endpoint" behind the engine adapter in `app/lib/engine/`.
- `trainer/` — Python training service (arrives in phase 6).
- `docs/LEARN.md` — the companion book; new features should get a section here.

## Ground rules

- Keep the "no terminal required" promise: user-facing features must be operable
  entirely from the UI.
- Every model source speaks the OpenAI-compatible HTTP API. Don't special-case
  engines in UI code — extend the engine adapter instead.
- Never commit model weights (`.gguf`, `.safetensors`, …) — they're gitignored.
- Run `dart format` and `flutter analyze` before opening a PR.

## Commit / PR style

- Small, focused PRs beat big ones.
- Conventional-ish commit messages: `feat: …`, `fix: …`, `docs: …`.

## License

By contributing you agree your contributions are licensed under Apache-2.0.
