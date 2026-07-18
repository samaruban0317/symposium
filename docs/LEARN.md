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
- Fonts (Spectral serif, IBM Plex Mono) are **bundled in `assets/fonts/`** rather than
  fetched at runtime: a local-LLM app must work offline, and staying plugin-free means
  Windows builds don't require Developer Mode. (Phase 2's mDNS package *is* a plugin,
  so enable Developer Mode — Settings → System → For developers — before then.)

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

---

## Chapter 3 — Host mode & discovery (how your friend's PC appears in your sidebar)

Phase 2 adds two abilities: **hosting** (one toggle shares this PC's models with the
network, guarded by a 6-digit code) and **discovery** (other Symposiums on the same
Wi-Fi appear under PEERS automatically). Three new files, all pure Dart
(`lib/net/protocol.dart`, `discovery.dart`, `host_server.dart`) plus their state
(`lib/state/net_state.dart`).

### The two problems to solve

1. *"What's my friend's IP?"* Nobody wants to type `192.168.1.47`. → **discovery**
2. *"Ollama only answers its own PC."* Ollama binds to `localhost` on purpose —
   security — so a friend literally cannot reach it. → **the host proxy**

### Discovery: shouting into the room

A LAN supports **UDP broadcast**: send one packet to the special address
`255.255.255.255` and every device on the network receives it. Symposium's scanner
broadcasts a tiny JSON question every 3 seconds:

```json
{"symposium": "discover", "v": 1}
```

Any Symposium in host mode is listening on UDP port 47474 and answers straight back
(a normal unicast reply) with its name, port, model list, and whether it requires
pairing. Hosts that stop replying for 10 s fall off your PEERS list. That's the whole
protocol — ~120 lines in `discovery.dart`.

*Why not mDNS/Bonjour (what Chromecast uses)?* mDNS matters when you must interoperate
with other people's software. Both ends here run our code, so a hand-rolled scheme is
simpler, needs no native plugin (Windows builds stay Developer-Mode-free), and is
easier to debug — you can literally watch the packets in Wireshark.

### Host mode: a reverse proxy with a doorman

When you flip HOST ON NETWORK, Symposium starts an HTTP server on port 47475 that
does only one thing: **forward every request to your local engine** at
`127.0.0.1:11434`, streaming bytes in both directions (so SSE token streams pass
through untouched). This is called a *reverse proxy* — same idea nginx uses in front
of web apps.

The doorman part: every request must carry the header `x-symposium-code: 123456`
matching the code shown on the host's screen, or it gets `401 Unauthorized`. So your
GPU is shared with friends who have the code, not with everyone on the coffee-shop
Wi-Fi. The client sends the code automatically once you've entered it in the JOIN
dialog (see `pairingCodeProvider` → `engineProvider` in `app_state.dart` — the
elegant bit is that *nothing else changed*: the engine adapter just gained an extra
header, and chat/models/pull all work over the proxy identically).

First time you host, **Windows Firewall will ask** whether to allow Symposium on
private networks — say yes; that's the OS-level permission for ports 47474/47475.

### Trying it with two machines

1. PC with models: flip HOST ON NETWORK, note the 6-digit code.
2. Other device on the same Wi-Fi: the host appears under PEERS in seconds.
   Tap → enter code → its models fill your sidebar. Chat away — tokens are generated
   on the host's GPU and streamed to you.

### Verifying without a second machine

`app/tool/netcheck.dart` is a headless self-test that plays both roles at once:
starts a real host, discovers it over real UDP, checks that missing/wrong codes are
rejected, and streams a real completion through the proxy:

```
cd app
dart run tool/netcheck.dart
```

### Android notes (first .apk)

Two manifest lines matter (`android/app/src/main/AndroidManifest.xml`):
`INTERNET` permission (obvious) and `usesCleartextTraffic="true"` — Android blocks
plain `http://` by default, but LAN engines have no TLS certificates, so we opt in.
Traffic never leaves your network.

---

## Chapter 4 — Split screen & arena (two minds at once)

Chapter 0 promised that "a model is just a URL + a model name" would make split screen
cheap. This chapter is where the promise gets cashed.

### The design problem

Phase 1's chat has exactly one of everything: one `endpointProvider`, one engine, one
conversation. Split screen needs **two of everything, independently** — the left pane
might be your own PC running `qwen2.5:0.5b` while the right pane is your friend's PC
(through the pairing-code proxy) running `llama3.2:3b`. And they must stream *at the
same time* without stepping on each other.

The wrong fix is doubling the globals (`endpoint2Provider`, `engine2Provider`…).
The right fix is a **parameterized provider**: Riverpod's `.family` lets one
definition produce N independent copies keyed by a value. Ours is keyed by which
side of the screen it is:

```dart
enum ArenaSide { left, right }

final paneProvider = StateNotifierProvider.family<PaneController, PaneState, ArenaSide>(
  (ref, side) => PaneController(ref, side),
);
```

`ref.watch(paneProvider(ArenaSide.left))` and `...(ArenaSide.right))` are now two
fully separate state machines — separate endpoint, pairing code, model list, selected
model, conversation, tok/s. Each constructs its own `OllamaEngine` on demand. The
phase-1 chat is untouched; the arena lives beside it (`lib/state/arena_state.dart`,
`lib/ui/arena/`), and the header grew CHAT | ARENA tabs.

### The race-condition you always hit (and the epoch trick)

Switch a pane from PC A to PC B while PC A's model list is still loading. The stale
response arrives *late* and overwrites PC B's list. Async UIs hit this constantly.
The classic fix is an **epoch counter**: every source switch increments an integer;
every async result carries the epoch it started under; results from an old epoch are
thrown away. Two lines of discipline, whole class of bugs gone.

### Duel mode

DUEL sends one prompt to both panes at once — two independent SSE streams, two live
tok/s readouts, a laurel for whoever finishes first, then vote buttons (left / tie /
right) feeding an in-memory scoreboard. One subtlety worth stealing: the scoreboard
key (`"modelA ⇄ modelB"`) is captured when the round *starts*, not when you vote —
otherwise switching a model mid-round would credit the wrong pairing.

### Try this

1. Phone + two PCs on one Wi-Fi: bind left to one PC, right to the other. Your phone
   is now a judge between two machines' GPUs.
2. Bind both panes to the *same* model and duel it against itself. Different answers?
   That's sampling temperature at work (chapter 5).
3. Read `arena_state.dart` and find the epoch check. Delete it, switch sources
   quickly, and watch the stale-response bug appear. Put it back.

---

## Chapter 5 — Interactivity: the parameter lab & message surgery

If phase 1 was "make it work," this phase is "make it *tactile*." Three features, each
teaching one idea about how chat models actually behave.

### The parameter lab (what the knobs really do)

A "tune" icon by the composer opens a panel (`lib/ui/parameter_lab.dart`) with the
sampling controls every server accepts but most UIs hide:

- **temperature** — generation picks the next token from a probability distribution.
  Temperature reshapes it: 0 ≈ always take the top token (deterministic, dull),
  higher values flatten the curve (creative, eventually unhinged). Try 0.0 vs 1.5 on
  the same question.
- **top_p (nucleus sampling)** — instead of considering every token, keep only the
  smallest set whose probabilities sum to *p*. A quality floor under high temperature.
- **max_tokens** — a hard stop on answer length. Blank = let the model decide.
- **system prompt** — a hidden first message that steers everything ("answer only in
  rhyme"). It is deliberately kept *out* of the visible transcript and prepended at
  request time — so editing it re-steers the *next* turn of an existing conversation.

Non-default values appear as chips beside the composer, because invisible state you
forgot about is how you end up thinking a model is broken when it's just set to
temperature 1.8.

### Message surgery (the transcript is just a list)

The server is **stateless** — every request re-sends the whole message list, and the
"conversation" exists only in the app's memory. Once you see that, three "advanced"
features become list operations (all in `ChatController`, all via hover / long-press
on a message):

- **regenerate** — drop the last assistant message, re-send. (With different lab
  settings, this doubles as "retry, but more creative".)
- **edit-and-resend** — truncate the list after an earlier user message, replace it
  with your edit, re-send. Time travel.
- **fork from here** — copy the list up to a message into a fresh conversation and
  explore a different branch.

### Streaming markdown (why it flickers in naive UIs)

Models emit markdown, and it arrives *mid-syntax* — a half-open ``` fence is briefly
"broken markdown." Naive renderers re-parse and flicker. We added one package,
`gpt_markdown`, built for exactly this: partial input renders stably, and code blocks
get themed treatment with a copy button. Chosen also because it's pure Dart — no
native plugin, so the Windows and Android builds stay simple.

### Try this

1. System prompt "You are a pirate", ask something, then change it to "You are a
   lawyer" and hit regenerate on the same question.
2. temperature 0, ask twice — identical answers? Now 1.5.
3. Fork a conversation at its second message and take both branches somewhere
   different. You've just used conversations as a tree.

---

## Chapter 6 — The trainer, part 1: a tiny GPT you can watch learn

Everything so far *used* models. `trainer/` is where we start *making* one — a real
GPT, small enough to train on a laptop, wired so the app can watch it learn live.
(This chapter covers the Python service; the in-app Training Studio UI comes next.)

### Why tiny is enough

A "real" LLM is billions of parameters; ours are ~0.85M (`nano`) and ~2.75M
(`micro`). What makes that honest is that a GPT is the *same architecture* at every
scale — the identical code trains 1M or 1B parameters; only the config numbers and
the hardware change. Training `nano` on Shakespeare for a few minutes takes it from
emitting random bytes to emitting almost-English with character names — you can
literally watch grammar being learned. That arc is the entire point.

### The pieces (`trainer/`)

- **`common.py`** — the tokenizer and configs, deliberately torch-free. We use a
  **byte-level tokenizer**: vocab = the 256 possible byte values, so *any* text in
  any language tokenizes with zero unknown-character problems. The cost: sequences
  are ~4× longer than with a real subword vocabulary — fine at our scale.
- **`model.py`** — the decoder-only transformer itself, heavily commented. Read it
  top to bottom once; it is the shortest honest answer to "what *is* a GPT?"
- **`train.py`** — the loop: sample a batch of text windows, predict every next
  byte, measure cross-entropy loss, backpropagate, repeat. Also runnable standalone:
  `python -m trainer.train --preset nano --dataset tinyshakespeare`.
- **`server.py`** — FastAPI on port 8765 wrapping the loop in HTTP the app can use:
  start/stop runs, and a WebSocket at `/runs/{id}/metrics` streaming loss, tok/s and
  periodic generated samples. One design choice to notice: a client that connects
  *late* first receives the full event history, then live events — so the app can
  always draw the complete loss curve. And `/runs/{id}/generate` chats with the
  latest checkpoint, which closes Symposium's loop: a checkpoint is just one more
  model behind one more URL.

### One number to hold onto

Untrained, the model knows nothing, so every next byte is a 1-in-256 guess:
loss = ln(256) ≈ **5.55**. The first thing training does is collapse that toward
~2.5 (byte frequencies of English), then grind lower as it learns words and
structure. When the app draws its loss curve, 5.55 is the "knows nothing" line.

### Try this

1. `pip install -r trainer/requirements.txt` (torch is the big one), then run the
   standalone command above and watch loss fall from ≈5.55.
2. Compare the samples printed at step 200 vs step 2000. Describe *what kind* of
   structure appeared in between.
3. Change `nano`'s `n_layer` from 4 to 1 in `common.py` and retrain. Where does the
   loss plateau now? You've just run your first architecture ablation.
