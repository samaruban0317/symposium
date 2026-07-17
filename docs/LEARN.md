# LEARN.md — The Symposium Companion Book

This file teaches you everything happening in this project, from scratch, in the order
it was built. No prior knowledge assumed beyond "I have programmed a little." One
chapter per phase; each chapter ends with *"go read this code"* pointers.

---

## Chapter 0 — What we are building and why the architecture is shaped this way

Symposium is one app, compiled for Windows (`.exe`) and Android (`.apk`), that can:

1. run open-source language models on your own PC with one click,
2. discover models being served by other PCs on your network and use them from your phone,
3. show two models side by side and compare them,
4. eventually train a small model of your own, with the UI making the process visible.

### The one idea that makes all of this simple

A language model server is just a web server. When ChatGPT streams an answer to your
browser, an HTTP request went to a server, and the reply streamed back in small chunks.
Local model tools (Ollama, llama.cpp) copied OpenAI's HTTP interface, so today there is
a de-facto standard: the **OpenAI-compatible API**. You POST JSON to
`/v1/chat/completions` with a list of messages, and tokens stream back.

Symposium leans on this completely. To the app, *every* model is just:

> a URL + a model name.

- Model on your own PC → `http://localhost:11434` (Ollama's port)
- Model on your friend's PC → `http://192.168.1.42:11434`
- Your own half-trained model in phase 6 → `http://localhost:8199`

Chat pane code never knows or cares which one it's talking to. That single decision is
what makes "friend's PC," "split screen," and "chat with your own checkpoint" all cheap
to build instead of three separate features.

### Words you need

- **LLM (large language model)** — a neural network trained to predict the next token
  of text. Everything it does — answering, coding, roleplaying — emerges from
  next-token prediction plus fine-tuning to behave like an assistant.
- **Token** — models don't read letters or words; text is chopped into ~¾-word pieces
  ("chatting" → `chat` + `ting`). Generation happens one token at a time, which is why
  answers *stream*.
- **Parameters / weights** — the learned numbers inside the network. "A 7B model" =
  7 billion parameters. More parameters ≈ smarter but slower and more memory-hungry.
- **Quantization** — storing weights in fewer bits (e.g. 4 instead of 16) so big models
  fit in ordinary RAM/VRAM at a small quality cost. Why a "7B Q4" model needs ~4.5 GB
  instead of ~14 GB.
- **GGUF** — the file format llama.cpp-family engines use for quantized models. When
  the app "installs a model," it is downloading a GGUF file (or Ollama's wrapped
  version of one).
- **Inference engine** — the program that loads the weights and does the math.
  We use **Ollama** first (it's a friendly manager wrapped around **llama.cpp**, the
  open-source C++ engine nearly everything local is built on). Phase 5 embeds
  llama.cpp directly so Symposium is self-contained.
- **Context window** — how much conversation the model can "see" at once, measured in
  tokens. Fill it and the oldest messages fall off. The app shows this as a gauge.

### Why Flutter?

We need *one* codebase producing a real Windows `.exe` and a real Android `.apk`, with
enough graphical firepower for streaming heatmaps, radar animations, and live charts.
Flutter (Google's UI toolkit, using the Dart language) is the one mainstream framework
where both targets are first-class. Dart will feel familiar if you know JavaScript or
Java: classes, `async/await`, arrow functions.

### The map

```
symposium/
  app/               the Flutter app — everything the user sees
    lib/
      engine/        talking to model servers (the ONLY place that knows about Ollama)
      models/        plain data classes (chat message, endpoint, model info)
      state/         Riverpod state: current chat, model list, download progress
      ui/            screens and widgets
  trainer/           Python training service (phase 6)
  docs/LEARN.md      this book
```

---

## Chapter 1 — Setting up the machine (what was installed and why)

Everything here happened on a Windows 11 laptop with an RTX 4050 (4 GB VRAM) — enough
GPU to run ~7B quantized models decently and, later, to train tiny models.

1. **Ollama** (was already installed) — runs as a background service on port `11434`.
   Two APIs matter:
   - its native REST API (`/api/tags` list models, `/api/pull` download a model with
     streaming progress, `/api/chat`),
   - plus the OpenAI-compatible `/v1/chat/completions`.
   The app uses the native API for *management* (pull progress!) and the OpenAI API
   for *chat*, because chat-over-OpenAI-API is the part that must work identically
   for non-Ollama servers later.
2. **Flutter SDK** → `C:\dev\flutter` (deliberately a path without spaces — build
   tools are historically fragile with `C:\Users\Samaruban V\...`-style paths).
3. **Visual Studio 2022 Build Tools + C++ workload** (was already installed) —
   Flutter's Windows target compiles a real native C++ host program, so it needs MSVC.
4. **Android Studio / Android SDK** — *deferred to phase 2.* The Dart code we write is
   already mobile-ready; the Android toolchain is only needed to produce the `.apk`.

### How streaming actually works (SSE)

When you send a chat request with `"stream": true`, the server keeps the HTTP response
open and writes **Server-Sent Events**: lines like

```
data: {"choices":[{"delta":{"content":"Hel"}}]}
data: {"choices":[{"delta":{"content":"lo"}}]}
data: [DONE]
```

The app reads the response as a byte stream, splits on lines, JSON-decodes each
`data:` payload, and appends the `delta.content` piece to the message bubble on
screen. That is *all* "streaming" is. Tokens/sec is just counting those chunks
against a stopwatch.

---

## Chapter 2 — The phase-1 app, file by file

Phase 1 delivers: streaming chat with any local model, one-click model install with
live progress, an editable engine address (which already lets you point at a friend's
PC by IP — mDNS in phase 2 just automates finding that IP), and a live tokens/sec
readout. Nine Dart files, each with one job.

### Dart in ninety seconds (if you know JS/Python)

```dart
final name = 'Samaruban';          // `final` = const-after-assignment (like JS const)
String? maybe;                     // `?` = this can be null; Dart forces you to handle it
Future<int> f() async => 42;       // async/await, exactly like JS
Stream<String> words() async* {    // a Stream is an async sequence — like a Python
  yield 'hello';                   // generator you can `await for` over
}
class A extends B { ... }          // classes, like Java/JS
```

The one unfamiliar thing is **widgets**: in Flutter *everything on screen is a widget*,
and UI is built by composing them in code (no HTML). A widget's `build()` method
returns the widget tree below it — think "a React component's render, in Dart."

### The dependency choices (`app/pubspec.yaml`)

- `flutter_riverpod` — state management. The app's "truths" (current endpoint, model
  list, chat history, download progress) live in *providers*; widgets `watch` a
  provider and rebuild automatically when it changes. This is the same job React's
  hooks/Redux do.
- `http` — plain HTTP client. Deliberately boring; SSE streaming needs nothing fancier.
- `google_fonts` — loads Spectral (serif) and IBM Plex Mono at runtime.

### `lib/engine/ollama_engine.dart` — the only file that knows about servers

Read this file first; it is the heart of the architecture.

- `listModels()` → GET `/api/tags` (Ollama-native, since OpenAI's API has no
  "what's installed" endpoint that includes sizes/quantization).
- `pull(model)` → POST `/api/pull`, then reads the response **as a stream of
  newline-delimited JSON**: Ollama keeps the connection open and writes one progress
  object per line (`{"status":"pulling…","total":…,"completed":…}`). The Dart chain
  `res.stream.transform(utf8.decoder).transform(const LineSplitter())` turns raw bytes
  → text → individual lines; each becomes a `PullEvent` the UI can render as a
  progress bar. **This is the whole "install a model by clicking" feature** — a
  download with progress reporting, nothing more magical.
- `chat(...)` → POST `/v1/chat/completions` with `"stream": true` — the
  OpenAI-compatible endpoint, so this exact code works against llama.cpp, vLLM,
  LM Studio, or a friend's machine. It parses SSE `data:` lines (chapter 1) and emits
  each `delta.content` piece into a `StreamController`. Cancellation = closing the
  HTTP client mid-response; the server notices the dropped connection and stops
  generating (that's all a "Stop" button ever does, even in ChatGPT).

### `lib/state/app_state.dart` — the app's nervous system

A chain of Riverpod providers, each derived from the previous:

```
endpointProvider ("http://127.0.0.1:11434")
  └─ engineProvider (an OllamaEngine for that URL)
       ├─ serverOnlineProvider (ping)
       ├─ modelsProvider (the list)      ─ selectedModelProvider (first by default)
       ├─ chatControllerProvider
       └─ pullControllerProvider
```

Because everything derives from `endpointProvider`, **changing the URL in the UI
tears down and rebuilds the whole chain automatically** — new server, new model list,
same code. That's the Riverpod payoff.

`ChatController.send()` is worth reading closely: it appends your message plus an
*empty* assistant message, then `await for`-loops over the delta stream, replacing the
last message with `content + delta` on every chunk. Each replacement triggers a widget
rebuild → you see tokens appear. Tokens/sec is just `chunks / stopwatch` (Ollama sends
roughly one token per chunk).

### The UI (`lib/ui/`)

- `home_screen.dart` — responsive shell. One `wide = width >= 720` check decides:
  desktop gets a permanent sidebar, phone gets the same sidebar inside a drawer.
  This is why the code is "already mobile-ready."
- `sidebar.dart` — engine address tile (tap to edit — type a friend's
  `192.168.x.x:11434` today!), model list with size/quantization details, download
  progress banner, INSTALL MODEL button.
- `chat_view.dart` — message list + composer. Messages aren't bubbles but
  left-bordered blocks: amber border = you, teal = the model, with the model's name
  as a small mono label (matters once split-screen arrives and *which model said
  this* becomes important).
- `pull_dialog.dart` — free-text model name plus a curated "good first models" list.
- `widgets.dart` — the blinking `▌` streaming cursor, instrument readouts, status dot.
- `theme.dart` — every color and text style in one place ("lamplight academy":
  warm blacks, amber for the human side, phosphor teal for the machine side,
  serif display over instrument mono).

### Run it

```
cd app
flutter pub get        # fetch dependencies (reads pubspec.yaml)
flutter run -d windows # debug build, hot-reload enabled
flutter build windows  # release .exe → build/windows/x64/runner/Release/
```

### Try this (exercises)

1. Change `temperature` in `ollama_engine.dart` to `0.0`, hot-reload, and ask the same
   question twice. Why are the answers now identical?
2. Point the engine address at a friend's PC running `ollama serve` (they must set
   `OLLAMA_HOST=0.0.0.0` so it listens beyond localhost — this is exactly what
   phase 2's "host mode" toggle will automate).
3. Add a fourth suggestion to `pull_dialog.dart` and hot-reload.

*(Chapter 3 — host mode & discovery — arrives with phase 2.)*
