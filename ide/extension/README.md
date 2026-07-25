# Symposium ML

Turn VS Code / VSCodium into a professional **remote ML monitoring + training** panel
for the [Symposium](https://visionarysparks.in) host rig.

Symposium lets you run local open-source LLMs and share a "host" PC's engine (usually a
gaming rig with a GPU) over the LAN/internet. This extension is a client for the
Symposium **training service** (`trainer/` — the FastAPI server in this repo), so a
low-spec laptop can watch training in real time and start runs on the rig. It speaks the
trainer's own API — no extra rig code to write.

---

## What it does

- **Engine Tracker** — a live dashboard in the **Symposium** activity-bar panel:
  - Loss curve (inline SVG line chart, no heavy charting deps)
  - Step counter
  - VRAM usage bar (turns red near capacity)
  - GPU temperature and tokens/sec
  - The run's lifecycle (running / finished / stopped / error) plus a clear
    **disconnected / connecting / live** connection status with auto-reconnect (capped
    exponential backoff)
- **Start Training Run on Rig** — one command / keybinding picks a model preset + step
  count and starts a run on the rig's trainer (`POST /runs`). It does **not** ship your
  editor's source for the rig to execute — that would be remote code execution.
- **Symposium Rig** output channel — tails the live run: metrics, "watch it learn to talk"
  samples, and status transitions.

The **extension host owns every socket**. The webview only renders; it receives metrics via
`postMessage` and never opens a connection itself. The webview runs under a strict
Content-Security-Policy with a per-load nonce and styles itself with VS Code theme
variables (brand accent teal `#2AB7B0`).

---

## Settings

| Setting | Default | Description |
|---|---|---|
| `symposium.rig.url` | `http://127.0.0.1:8765` | Base HTTP(S) URL of the Symposium trainer service. The extension derives `POST <url>/runs` and `ws(s)://…/runs/latest/metrics` from it. Point it at your rig's LAN address for remote monitoring. |
| `symposium.rig.token` | `""` | Optional bearer token for rig HTTP + WebSocket auth. Leave empty for an open LAN rig. |
| `symposium.rig.autoConnect` | `false` | Auto-connect the log channel on activation. |

---

## Commands

| Command | ID | Notes |
|---|---|---|
| Symposium: Start Training Run on Rig | `symposium.startRun` | Bound to `Ctrl+Shift+T` / `Cmd+Shift+T` (see caveat below). |
| Symposium: Connect Rig Logs | `symposium.connectLogs` | Opens + tails the **Symposium Rig** output channel. |
| Symposium: Disconnect Rig Logs | `symposium.disconnectLogs` | Stops the log stream. |

### Keybinding caveat — `Ctrl+Shift+T`

VS Code already binds **`Ctrl+Shift+T`** to *Reopen Closed Editor*. This extension binds it
to *Start Training Run* while Symposium is active:

```
symposium.active
```

`symposium.active` is a context key the extension sets while it is active (which, in the
dedicated Symposium IDE build, is the intended behaviour). If you find the two commands
conflict on your setup, rebind ours via **File ▸ Preferences ▸ Keyboard Shortcuts** (search
"Symposium: Start Training Run on Rig").

---

## Build & run

Requires Node 18+.

```bash
npm install
npm run compile      # bundle src/extension.ts -> dist/extension.js (esbuild)
npm run watch        # rebundle on change
npm run typecheck    # tsc --noEmit type check (no emit)
```

### Debug (Extension Development Host)

1. Open this folder (`ide/extension`) in VS Code / VSCodium.
2. Press **F5** (runs `Run Symposium ML Extension`, which compiles first).
3. A new Extension Development Host window opens with the **Symposium** icon in the Activity Bar.

### Package a `.vsix`

```bash
npm run package      # @vscode/vsce package -> symposium-ml-0.1.0.vsix
```

Install it with **Extensions ▸ … ▸ Install from VSIX…** or:

```bash
code --install-extension symposium-ml-0.1.0.vsix
```

---

## Rig API (already implemented by `trainer/`)

The extension speaks the API the Symposium trainer service already exposes — start it on
the rig with:

```bash
pip install -r trainer/requirements.txt
uvicorn trainer.server:app --host 0.0.0.0 --port 8765
```

Then set `symposium.rig.url` to that host (e.g. `http://192.168.1.20:8765`). The two
endpoints the extension uses:

### `POST <url>/runs` — start a run
Body (all optional): `{ "preset": "nano" | "micro", "steps": 2000, "dataset": "tinyshakespeare", "lr": 3e-4, "batch_size": 32 }`.
The **Start Training Run** command sends `{preset, steps}` from a quick-pick. Responds with
the run record including `{"id": "..."}`, shown in the success toast.

### `WS <ws-url>/runs/latest/metrics` — live event stream for the newest run
One JSON object per frame, tagged by `kind`. On connect the server **replays** the whole
history (so the loss curve redraws after a reconnect), then streams new events:

```json
{ "kind": "metric", "step": 123, "loss": 0.42, "tok_per_sec": 48, "vram_used_mb": 6800, "vram_total_mb": 8192, "gpu_temp_c": 71 }
{ "kind": "sample", "step": 100, "text": "…generation from the current weights…" }
{ "kind": "status", "step": 0, "status": "running" }
```

- `metric` events feed the Engine Tracker (loss curve, VRAM bar, temp, tok/s). GPU fields are
  present only when training on CUDA (VRAM via torch, temperature via `pynvml` if installed).
- `status` events drive the run lifecycle shown in the tracker.
- All three kinds are printed to the **Symposium Rig** log channel.

### Auth (optional)
If `symposium.rig.token` is set, requests carry `Authorization: Bearer <token>` — on the
HTTP `POST` and on the WebSocket handshake headers. (The trainer service itself is
unauthenticated today; the token is forwarded for when it sits behind the Symposium host
proxy, which does enforce tiers.)

---

## Notes / assumptions

- WebSockets in the extension host use the [`ws`](https://github.com/websockets/ws) package.
  The `Authorization` header is sent during the WS handshake; a browser-native `WebSocket`
  cannot do this, which is another reason the socket lives in the extension host.
- The Activity Bar icon (`media/icon.svg`) is a teal spark/line-graph placeholder. The real
  brand logo lives at `../../app/assets/brand/visionarysparks-logo.png` and can be swapped in.
  `media/icon.png` (the Marketplace icon) is currently a copy of that brand logo.

---

## License

MIT © Visionary Sparks
