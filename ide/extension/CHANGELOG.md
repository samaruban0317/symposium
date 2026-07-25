# Changelog

All notable changes to the **Symposium ML** extension.

## [0.1.0] — 2026-07-25

Initial release.

- **Engine Tracker** webview view in a dedicated **Symposium** activity-bar container.
  Live loss curve (inline SVG), epoch/step counters, VRAM bar, GPU temp, tokens/sec.
  Streams from `symposium.rig.metricsWs`, auto-reconnects with backoff, and shows a
  `disconnected / connecting / live` status. Strict CSP + nonce; the extension host
  owns the socket and posts messages to the webview.
- Command **Symposium: Train Active File on Rig** (`Ctrl+Shift+T` / `Cmd+Shift+T`,
  scoped to `symposium.active && editorTextFocus`) — POSTs the active file to
  `symposium.rig.trainUrl` with an optional bearer token, with progress + error toasts.
- **Symposium Rig** output channel tailing `symposium.rig.logsWs`, with
  `Connect` / `Disconnect` commands, auto-reconnect, and optional auto-connect on activation.
