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

---

## Chapter 7 — Cloud keys & the persona studio (tuned minds you can share)

Two features land together in this chapter because they solve the same user
story from two ends: *"I want an assistant tuned exactly my way, running on
whatever brain I can afford — and I want to hand it to a friend."*

### First, the app finally remembers things

Until now everything lived in memory. This phase adds `lib/state/local_store.dart` —
the ONE file that knows where Symposium keeps data on disk (via `path_provider`,
which resolves the right per-user folder on Windows and Android). Saved cloud
sources are `sources.json`, personas are `personas.json`. Keys are stored as plain
local files readable by your OS user — the same trade-off git credentials make.
If that ever needs upgrading to OS keychains, it's a one-file change, because
every caller goes through `dataFile()`.

### Cloud providers: chapter 0's rule pays out again

OpenAI, Google (Gemini), and Anthropic all expose **OpenAI-compatible endpoints**.
So "add an API key" is not three integrations — it is a URL, a header, and two
small differences per provider:

| Provider  | Base URL (includes version segment)                          | Auth |
|-----------|--------------------------------------------------------------|------|
| OpenAI    | `https://api.openai.com/v1`                                  | `Authorization: Bearer KEY` |
| Gemini    | `https://generativelanguage.googleapis.com/v1beta/openai`    | `Authorization: Bearer KEY` |
| Anthropic | `https://api.anthropic.com/v1`                               | `x-api-key: KEY` + `anthropic-version` (native endpoints), Bearer also accepted for chat |

Quirks worth knowing (all handled in `ollama_engine.dart` / `sources_state.dart`):
model *listing* is `GET /models` in the OpenAI shape `{data:[{id:…}]}` (Anthropic's
native list happens to match — one parser covers everyone); Anthropic rejects a
chat request with no `max_tokens`, so we default one in; newer Claude models
reject `temperature`, so cloud requests only send it when you moved the slider;
a 401/403 still means "online" (the *server* answered — it's the key that's
wrong), which is why the status dot and the error message are separate ideas.

### The trick: auth rides on the URL

The elegant bit is `OllamaEngine.cloudAuth` — a registry mapping
`baseUrl → headers`. The sources layer registers each saved provider once;
after that, *any* engine built from that bare URL — the main chat, an arena
pane — inherits the key and the cloud dialect automatically. The endpoint
string stays the app's whole contract, which is why "duel your local qwen
against Gemini" required a 20-line change to the arena picker, not a redesign.

### Personas: the system prompt as a portable artifact

Chapter 5 taught that a system prompt steers everything. A **persona**
(`lib/models/persona.dart`) promotes that from a setting to a *thing*: name,
glyph, instructions, sampling knobs, optionally a preferred source+model, plus
an `instructionsRevision` counter. The STUDIO tab is a workshop around it:
editor on one side, a live test chat on the other, and an **apply & re-ask**
button that re-runs your last test question under the freshly edited
instructions. Every answer is stamped with the revision that produced it
(`r3`), because the whole pain of prompt-tuning is forgetting which wording
caused which behavior.

Tuning loop in practice: ask a representative question → read the answer →
edit instructions → apply & re-ask → compare `r2` against `r3` → repeat. This
is the same evaluation discipline real prompt engineers use, minus the
spreadsheet.

### Sharing a mind

Export wraps the persona as
`{"type": "symposium_persona", "version": 1, "persona": {…}}` — copied to the
clipboard and written to a file whose path the app shows you. Two deliberate
choices: the machine-local `pinnedSourceId` is **dropped** (your friend's
source ids differ; the model *name* survives as a hint), and import refuses
files with a `version` from the future instead of mis-reading them. Your friend
pastes the JSON into their import dialog and gets your tuned assistant —
running on *their* key or *their* PC. Nothing ever passes through a server of
ours; sharing a persona is sharing text.

### Try this

1. Add a Gemini key (aistudio.google.com gives free-tier ones), then duel
   `gemini-2.0-flash` against your local model in the arena.
2. Build a persona in the studio with an unusual constraint ("answer in exactly
   three sentences"). Watch which revision finally makes it stick.
3. Export it, send the JSON to a friend running Symposium, and have them import
   it against a completely different model. What survives the model swap —
   and what was really the model all along?

## Chapter 8 — Memory, phones, and why LAN discovery fails in the real world

### Conversations that survive a restart

Until now a chat lived only in a `StateNotifier` — close the app, lose the
thread. The fix is deliberately small: a `Conversation` model
(`lib/models/conversation.dart`) and a `HistoryRepo`
(`lib/state/history_state.dart`) that follow the exact pattern sources
already used — one JSON file (`conversations.json`) through `local_store`,
one hydration provider, one plain list provider the sidebar watches.

The interesting decision is *when* to save. There is no save button: the
`ChatController` snapshots the transcript in its `finally` block, after every
exchange — success, error, or a mid-stream stop all land in history. The
first user message becomes the title (a rename survives later snapshots,
because the repo keeps an existing title on upsert). *Fork from here* starts
a new id so the original stays intact; *edit & resend* keeps the id, because
rewriting a question is still the same conversation.

### The 255.255.255.255 lie

Phase-2's discovery broadcast worked laptop↔laptop and then quietly failed
laptop↔phone. Two real-world reasons:

1. **The limited broadcast address is second-class.** Many Android builds
   (and some routers) drop packets sent to `255.255.255.255`. The
   *subnet-directed* broadcast — `192.168.1.255` for a `/24` — is far more
   reliable, so the scanner now also probes every interface's `x.y.z.255`.
2. **Windows Firewall eats inbound probes.** The host binds UDP 47474 just
   fine; the phone's probe simply never arrives unless Symposium was allowed
   through the firewall for private networks.

Both failures are invisible, which is the real lesson: **every discovery
mechanism needs a manual fallback.** The host panel now shows this PC's
LAN address, and the peers panel gained *JOIN BY IP* — type the address and
the 6-digit code and you connect over plain HTTP, no UDP involved. Automatic
when it works, typeable when it doesn't.

### Phones are not small desktops

Three classes of mobile bug, all found in this phase:

- **Edge-to-edge.** Modern Android draws apps under the status bar and the
  gesture bar. Without a `SafeArea`, the header sat beneath the clock. One
  widget fixes it everywhere.
- **Fixed widths.** Dialogs asked for 380–400px of content. An AlertDialog
  on a 360dp phone offers ~280px — instant yellow-and-black overflow
  stripes. `dialogWidth(context)` clamps to what the screen actually has.
- **A header is not a nav bar.** Three tabs, a title, and instruments do not
  fit in 360dp. Below 720px the tabs move to a bottom strip — where thumbs
  are — and the header keeps only title, new-chat, and the status dot.

### Try this

1. Chat, kill the app, reopen — the conversation is in the sidebar. Rename
   it, keep chatting, and note the rename sticks.
2. Turn on hosting, then on your phone use JOIN BY IP with the address the
   host panel shows. If discovery was silently failing before, this works
   anyway — and tells you the problem was UDP, not HTTP.
3. Fork an old conversation from its middle and watch a second entry appear
   in history while the original stays frozen.

## Chapter 9 — The whole library, a terminal, and daylight

### From five suggestions to the full catalog

The install dialog used to offer five hand-picked models — fine for a first
run, wrong as a permanent ceiling. The library browser
(`lib/state/catalog_state.dart`) now fetches ollama.com/library itself.
There is no JSON API for that page, so this is honest HTML scraping: three
stable markers (the `/library/NAME` links, the description paragraph, the
blue size chips) carry everything the browser needs. Scraping is brittle by
design, so the rule is *fallback, never failure*: any problem — offline,
firewalled, page redesigned — silently swaps in a bundled snapshot of the
most-pulled models, and the dialog labels which one you're looking at
("214 models · live" vs "offline catalog"). The parser is a pure function
with its own test, because the day ollama.com changes its markup, a red test
explains the bug faster than a user report.

Search doubles as an escape hatch: anything typed that matches nothing is
still installable verbatim, so `somebody/weird-finetune:q4` never needs the
catalog's permission.

### A terminal, on purpose

Chapter 2 promised "no terminal required" — that promise stands. But
*required* and *available* are different things: sometimes you just want
`ollama ps` or a `ping` without leaving the app. The panel
(`lib/state/terminal_state.dart`) is deliberately **not** a PTY: each line
runs as its own `powershell -Command` / `sh -c` process with stdout and
stderr streamed into a scrollback. No vim, no colors — and in exchange, no
native dependency and nothing to break on any platform. `cd` is interpreted
by the app so the working directory persists between commands; `clear`
wipes the buffer; a stop button kills a runaway process. On Android the
button simply doesn't exist — a shell you can't use is UI noise.

The same idea, one notch friendlier: when the local engine is offline, the
sidebar now offers START OLLAMA — one click instead of "open a terminal and
type `ollama serve`".

### Daylight: theming an app that thought it was one color

The palette was a set of `const` colors, and `const` is a promise to the
compiler — over eighty widgets had baked that promise into `const
BoxDecoration(...)` expressions. Making the theme switchable meant:

1. Two `SymPalette` instances (lamplight / daylight) behind static *getters*
   with the same names, so no call site changes spelling.
2. Un-`const`ing every expression that contained a palette color. This was
   mechanical, so a throwaway script did it: run the analyzer with
   `--format=machine`, and for each invalid-constant error, delete the
   nearest enclosing `const`. Eighty-three errors, one pass, zero hand
   edits — when a refactor is pure bookkeeping, make the tooling do it.
3. One trick in main.dart: the home subtree is re-keyed on toggle
   (`KeyedSubtree(key: ValueKey(dark))`), which remounts everything, so even
   `const` widgets rebuild and read the new palette.

The daylight palette keeps the identity: same amber-for-human,
teal-for-machine language, darkened until it reads as ink on warm paper
instead of light in a dark room. The choice persists in `settings.json` and
loads before the first frame, so the app never flashes the wrong theme.

### Try this

1. Open the install browser and search "vision" — models the old dialog
   never mentioned appear, each with its size chips. Disconnect from Wi-Fi
   and reopen it: the offline catalog takes over, labeled as such.
2. Open the terminal and run `ollama ps` while a model is answering in the
   chat tab — you can watch the memory usage of the conversation you're
   having.
3. Toggle daylight, restart the app, and note it comes back in daylight.
   Then look at which colors changed meaning: the amber that was lamplight
   is now ink. Same role, different physics.

## Chapter 10 — Requirements are personal, transcripts are portable

### "Will it run on MY machine?"

A model page saying "needs 9 GB of RAM" makes every reader do the same
arithmetic against their own hardware. So the install browser now does it
for them: at startup Symposium asks the OS for total RAM (a WMI query on
Windows, `/proc/meminfo` on Android/Linux — `lib/state/device_state.dart`),
and every size chip is colored by verdict — teal fits, amber is tight,
red won't fit, with the honest tooltip that a too-big model "will run very
slowly if at all" (it spills to disk; it doesn't crash).

The estimates themselves (`ModelReqs` in `lib/models/catalog.dart`) come
from one fact worth knowing: library tags ship ~4-bit quantized, which
means roughly **0.65 GB of weights per billion parameters**, plus a couple
of GB of headroom for the KV cache and the OS. A "7b" chip therefore reads
`7b · 8 GB`. Mixture-of-experts sizes like `8x7b` multiply out fully —
only some experts *compute* per token, but all of them sit in memory.

The capability chips (VISION, TOOLS, THINKING, EMBEDDING) ride the same
scrape — they're the indigo badges on the library page — and become filter
buttons, because "which of these can see images?" was previously
unanswerable without leaving the app.

### What local models can and can't do (mid-2026 edition)

Worth stating plainly, since the catalog now advertises capabilities:
- **Seeing images** — yes. llava, moondream, gemma3, qwen2.5vl,
  llama3.2-vision all *understand* images (photos, charts, screenshots).
- **Reading PDFs** — indirectly: a PDF is text + images, so apps extract
  those and feed them in. The model never "opens" the file.
- **Generating images** — not an Ollama-family skill. That's diffusion
  model territory (Stable Diffusion / Flux via ComfyUI and friends), a
  different architecture entirely.
- **Generating video** — effectively no, not locally on consumer hardware
  in any usable way. The open video models that exist need workstation
  GPUs and minutes per clip.

### Leaving the app gracefully

Two escape hatches this phase. A conversation now exports as Markdown —
clipboard always, plus a file in Downloads where that folder exists — with
each turn labeled by who spoke it, including *which model*, because a
transcript where "the AI said" is unattributed loses the whole point of an
arena app. And the Windows build gets a real desktop shortcut to the
release exe, because "run flutter from a terminal" was this project's
founding anti-goal.

### Try this

1. Open the install browser on your phone and on your PC — the same 7b
   chip can be red on one and teal on the other. That difference *is* the
   requirements feature.
2. Filter by VISION, install the smallest (moondream), and ask it what's
   in a screenshot.
3. Export a duel conversation and read the Markdown: two models' answers
   to the same question, attributed, in one shareable file.

## Chapter 11 — Multimodal chat, and what "professional" actually means

### Sending an image to a model

The chat pipeline spoke plain text: `content` was a string, end of story.
The OpenAI dialect has a second form — a *parts array* mixing
`{type: "text"}` and `{type: "image_url"}` entries, with images embedded as
base64 data URIs — and Ollama's compatible endpoint accepts it for vision
models. The whole feature hangs on one method: `ChatMessage.toOpenAi()` now
emits the parts array *only when images are attached*, so text-only engines
never see anything new. Same principle as the sampling knobs in chapter 5:
absent means unchanged.

Documents took a different path on purpose. A model doesn't "open" a PDF —
apps extract the text and smuggle it into the prompt. So attaching a
document runs a pure-Dart PDF text extractor (or reads the file as UTF-8),
truncates to a sane budget, and stores it as `docText` — sent to the model
under an `[Attached document: name]` header, but shown in the transcript as
just a small file chip. The visible conversation stays readable; the model
sees everything.

The honest limits, worth knowing: vision models *understand* images, they
don't produce them (that's diffusion territory — Stable Diffusion, not
Ollama); scanned PDFs have no text layer to extract; and pasting a 500-page
book into a 4k-context model mostly wastes the middle.

### A terminal you'd actually keep open

The first terminal ran commands; this one behaves like a tool: ↑/↓ recalls
history (a `Focus` widget intercepting arrow keys before the TextField),
the header is a drag-splitter (`GestureDetector` adjusting a height
provider, clamped 140–560), quick chips run the three commands everyone
types anyway, and the scrollback sits on the darker `bg` so output reads as
a distinct surface from the chrome.

### Polish is mostly restraint

The "make it professional" pass was five small mechanical things, not a
redesign: a cross-fade between tabs (160ms — perceptible, not decorative);
autoscroll that *stops fighting you* when you scroll up mid-stream, with a
return-to-bottom pill; starter-prompt chips on the empty state so a blank
screen suggests its own first move; a focus ring on the composer; and the
brand glyph in the header. None of these add capability. All of them add
the feeling that someone finished the room.

### Postscript to chapter 10: VRAM is the real ceiling

Field report from this very machine: gemma3:12b (7.6 GB of weights) on an
RTX with 6 GB of VRAM produced 3.6 tok/s with the CPU pinned at 96% and
the GPU loafing at 20%. Nothing was broken — Ollama fit what it could into
VRAM and streamed the rest through the CPU, and the CPU set the pace.
Meanwhile a 1.5b model on the same machine flies, because it fits entirely
on the GPU.

So the requirements feature learned the distinction: the app now also asks
nvidia-smi for dedicated GPU memory, and a size chip is teal only when the
model fits *in VRAM* (fully-on-GPU fast). Fits-in-RAM-but-not-VRAM is
amber — it will run, slowly, exactly like the 12b did. System RAM tells
you whether a model *can* run; VRAM tells you whether you'll *enjoy* it.
