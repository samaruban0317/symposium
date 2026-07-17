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

*(Chapter 2 — the phase-1 app code walkthrough — is added below once the code exists.)*
