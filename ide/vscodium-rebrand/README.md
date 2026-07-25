# VSCodium → Symposium IDE rebrand kit

Turns [VSCodium](https://github.com/VSCodium/vscodium) (MIT, telemetry-free VS Code)
into a branded standalone **Symposium IDE** for **Visionary Sparks**.

> **The actual build runs on the founder's Windows machine** — VSCodium is a
> multi-GB, ~1–3 hour compile. This kit is the complete, correct *recipe*: config
> overrides + icon pipeline + apply scripts + a step-by-step runbook. Nothing here
> compiles VSCodium on this dev box.

## Files

```
vscodium-rebrand/
├─ product.overrides.json     # branding fields merged into VSCodium's product.json
├─ apply-branding.ps1         # Windows: stamp branding+icons+extension onto a clone
├─ apply-branding.sh          # mirror for macOS/Linux/Git-Bash
├─ RUNBOOK.md                 # full end-to-end build procedure (VERIFIED flow + sources)
├─ README.md                  # this file
└─ assets/
   ├─ make-icons.ps1          # brand PNG -> .ico/.icns/.png + Inno installer BMPs
   ├─ make-icons.sh           # mirror
   ├─ README-assets.md        # exact icon files + sizes + which VSCodium paths they replace
   └─ out/                    # (generated) win32/ darwin/ linux/ icon sets
```

## How the pieces fit

1. **`assets/make-icons.ps1`** takes the 1024×1024 brand logo
   (`../../app/assets/brand/visionarysparks-logo.png`) → `assets/out/{win32,darwin,linux}/`.
2. **`apply-branding.ps1 -Vscodium <clone> -Vsix <symposium-ml.vsix>`**:
   - deep-merges `product.overrides.json` into the clone's **repo-root `product.json`**
     (the file VSCodium's `prepare_vscode.sh` merges over `vscode/product.json`),
   - copies the generated icons into `src/stable/resources/*`,
   - stages the pre-built `symposium-ml` extension for bundling,
   - backs up every original to `*.orig-symposium` and is safe to re-run.
3. **`RUNBOOK.md`** — prereqs (Node **24.15.0**, Python 3.11, jq, 7-Zip, Rustup, VS
   Build Tools), clone + build commands, installer output path, OpenVSX marketplace
   behavior, extension bundling, fast source-run iteration, and the MIT/trademark note.

## What the branding sets
Product name **Symposium** / **Symposium IDE**, CLI `symposium`, data dir `.symposium`,
URL scheme `symposium://`, all Win32 identity strings, macOS bundle id
`in.visionarysparks.symposium`, issue URL → Symposium repo, MIT license — and it
**keeps** VSCodium's Open VSX marketplace (does not touch `extensionsGallery`).

## Scope guardrails
This kit only writes under `ide/vscodium-rebrand/`. It does **not** modify the Flutter
app under `symposium/app/` or the extension under `symposium/ide/extension/`; it only
*reads* the brand PNG and *consumes* the extension's built `.vsix`.
