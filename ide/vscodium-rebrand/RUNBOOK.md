# RUNBOOK — building **Symposium IDE** from VSCodium (Windows)

> End-to-end procedure the founder runs on his own Windows machine to produce a
> branded `SymposiumSetup-x64-<version>.exe` (and optional `.msi` / portable `.zip`).
> Nothing here builds on this dev machine — VSCodium is a multi-GB, ~1–3 hour build.
>
> **All flow facts below were verified against the live VSCodium repo (`master`) on
> 2026-07-25**, not from memory. Sources are cited inline. VSCodium's build system
> changes over time — if a path drifts, re-read `docs/howto-build.md`, `build.sh`,
> `prepare_vscode.sh`, and `prepare_assets.sh` before trusting this doc.

## 0. How VSCodium branding actually works (verified)

VSCodium builds real VS Code from Microsoft's source, then **de-brands and re-brands
it** with patches + a `product.json` merge. Two mechanisms matter to us:

1. **`prepare_vscode.sh`** copies `src/stable/*` into the freshly-fetched `vscode/`
   dir, then runs:
   ```bash
   jq -s '.[0] * .[1]' product.json ../product.json   # (inside vscode/)
   ```
   i.e. it merges the **repo-root `product.json`** OVER `vscode/product.json`, root
   winning. → **Our overrides go in the repo-root `product.json`.** `apply-branding.ps1`
   deep-merges `product.overrides.json` into that file.
   (Source: `VSCodium/vscodium/prepare_vscode.sh`.)
2. The **OpenVSX marketplace** is wired by the same script via
   `setpath_json "product" "extensionsGallery" '{"serviceUrl":"https://open-vsx.org/vscode/gallery", ...}'`.
   → **Do NOT set `extensionsGallery` in our overrides** or we'd clobber it. The built
   IDE's Extensions view uses Open VSX (Eclipse), not Microsoft Marketplace (whose ToS
   forbids non-VS-Code clients). (Source: `prepare_vscode.sh`.)
3. **Icons/resources** live under `src/stable/resources/{win32,darwin,linux}/` and are
   copied into `vscode/` during prepare. → We replace those files (see `assets/README-assets.md`).
   (Source: repo tree `src/stable/resources/win32`, `.../darwin`, `.../linux`.)

## 1. Prerequisites (verified against `docs/howto-build.md` + `.nvmrc`)

| Tool | Version / note |
|---|---|
| **Node.js** | **24.15.0** (exact — from VSCodium `.nvmrc`). Use `nvm-windows`: `nvm install 24.15.0 && nvm use 24.15.0`. |
| **Python** | **3.11** (node-gyp / native modules). |
| **Rustup** | required (VS Code CLI + native bits). |
| **jq** | JSON processor — the product.json merge depends on it. |
| **7-Zip** | `7z.exe` on PATH — used to make the portable `.zip`. |
| **Git + Git Bash** | run the `*.sh` build scripts from **Git Bash**, not PowerShell/cmd. |
| **VS Build Tools 2022** | "Desktop development with C++" workload (MSVC + Windows SDK) for native modules. |
| **WiX Toolset v3** | OPTIONAL — only if you want the `.msi`. `.exe` installers don't need it. |
| **Disk** | ~40–60 GB free (source + node_modules + build artifacts). |
| **Time** | first build ~1–3 h (cold `npm install` + full compile); rebuilds faster. |

> Node is version-locked — a wrong Node version is the #1 cause of VSCodium build
> failures. Confirm with `node -v` → `v24.15.0`.

## 2. Clone VSCodium

```powershell
mkdir C:\src ; cd C:\src
git clone https://github.com/VSCodium/vscodium.git
cd vscodium
```
(You do NOT clone microsoft/vscode — `get_repo.sh` fetches the exact upstream commit
for you.)

## 3. Build the Symposium ML extension `.vsix` (once)

The `symposium-ml` extension lives in `..\extension\` (owned by another agent). Build
its installable package:
```powershell
cd C:\Users\Samaruban V\OneDrive\Desktop\symposium\ide\extension
npm install
npx @vscode/vsce package    # -> symposium-ml-<version>.vsix
```
Note the produced `.vsix` path for step 4.

## 4. Apply Symposium branding

From this kit folder (`ide\vscodium-rebrand\`), in **PowerShell**:
```powershell
cd C:\Users\Samaruban V\OneDrive\Desktop\symposium\ide\vscodium-rebrand

# 4a. generate icons (needs ImageMagick: winget install ImageMagick.Q16)
.\assets\make-icons.ps1
#   optional cleaner small icons:
#   .\assets\make-icons.ps1 -SmallMark ..\..\brand\symposium-glyph-1024.png

# 4b. stamp branding + icons + stage the extension into the clone
.\apply-branding.ps1 -Vscodium C:\src\vscodium `
  -Vsix C:\Users\Samaruban V\OneDrive\Desktop\symposium\ide\extension\symposium-ml-0.1.0.vsix
```
This deep-merges `product.overrides.json` into `C:\src\vscodium\product.json`, copies
icons into `src\stable\resources\*`, and stages the `.vsix` under
`C:\src\vscodium\symposium-builtins\`. Originals are backed up to `*.orig-symposium`
(idempotent — safe to re-run).

## 5. Build the Windows installer (verified command sequence)

Open **Git Bash**, `cd /c/src/vscodium`, then:
```bash
export OS_NAME="windows"
export VSCODE_ARCH="x64"          # x64 | arm64
export VSCODE_QUALITY="stable"
export SHOULD_BUILD="yes"
export CI_BUILD="no"              # local packaging path (skips CI split-job logic)
export SHOULD_BUILD_REH="no"     # no remote-extension-host server
export SHOULD_BUILD_REH_WEB="no"
export SHOULD_BUILD_EXE_SYS="yes"   # system-wide setup .exe
export SHOULD_BUILD_EXE_USR="yes"   # per-user setup .exe
export SHOULD_BUILD_ZIP="yes"       # portable .zip
export SHOULD_BUILD_MSI="no"        # set "yes" only if WiX v3 installed

. ./get_repo.sh        # fetch upstream vscode at the pinned commit
. ./build.sh           # prepare_vscode.sh (branding+OpenVSX merge) -> compile -> min-packing
. ./prepare_assets.sh  # runs build/windows/prepare_assets.sh -> gulp *-system-setup / *-user-setup
```
(Sources: `docs/howto-build.md` for env vars & `. get_repo.sh` / `. build.sh`;
`build.sh` for the `prepare_vscode.sh`→`gulp vscode-win32-${VSCODE_ARCH}-min-packing`
flow; `build/windows/prepare_assets.sh` for the installer gulp targets:
`vscode-win32-x64-inno-updater`, `-system-setup`, `-user-setup`, and the 7-Zip step.)

### Output location (verified in `build/windows/prepare_assets.sh`)
Installers are moved into **`C:\src\vscodium\assets\`**, named from `APP_NAME`
(= `nameShort` = **Symposium**):
- `SymposiumSetup-x64-<ver>.exe`     (system-wide installer)
- `SymposiumUserSetup-x64-<ver>.exe` (per-user installer)
- `Symposium-win32-x64-<ver>.zip`    (portable)
- `Symposium-x64-<ver>.msi`          (only if `SHOULD_BUILD_MSI=yes`)

The unpacked app tree is `C:\src\vscodium\VSCode-win32-x64\` (contains `symposium.exe`).

## 6. Bundling the Symposium ML extension into the shipped app

Two options — pick one:

**A. Pre-install into the packaged tree (simple, reliable).** After step 5, before
you distribute, install the staged `.vsix` into the packaged app's bundled extensions:
```bash
# from git bash, in /c/src/vscodium
./VSCode-win32-x64/bin/symposium.cmd --install-extension \
  symposium-builtins/symposium-ml-0.1.0.vsix
```
Then re-zip / re-run the setup gulp target so the extension is inside the installer.
(This ships it as a normal user extension baked into the image.)

**B. True built-in (advanced).** Add the extension to VS Code's `builtInExtensions`
in `product.json` and place its source under `vscode/extensions/`. Heavier; only do
this if you want it non-uninstallable. For our needs, **A is recommended.**

## 7. Faster iteration (skip the installer while tuning branding)

You don't need a full installer build to see branding. After `apply-branding.ps1`
and one `. ./get_repo.sh`, run VSCodium from source:
```bash
# in /c/src/vscodium, Git Bash
powershell -ExecutionPolicy ByPass -File ./dev/build.ps1
```
This launches the branded editor (name, icons, About, OpenVSX) in minutes without
producing `.exe`/`.msi`. Iterate on `product.overrides.json` / icons, re-run
`apply-branding.ps1`, relaunch. Do the full step-5 build only for a distributable.
(Source: `docs/howto-build.md` dev-build section — `dev/build.ps1` / `dev/build.sh`.)

## 8. Licensing / trademark note

- **VSCodium is MIT** and ships **no** Microsoft telemetry or "Visual Studio Code"
  marks — that de-branding is the whole point of VSCodium and is exactly what lets us
  re-brand to Symposium legally. Our wrapper (this kit) is MIT too.
- We must **not** reintroduce Microsoft's "Visual Studio Code" name, logo, or the MS
  Marketplace. Replacing every brand string/icon with Symposium (which we do) keeps us
  clear. The `product.overrides.json` `licenseName`/`licenseUrl` point at the public
  Symposium repo's MIT license.
- Extensions come from **Open VSX** (Eclipse Foundation), which is licensed for third-
  party VS Code-compatible editors — unlike the MS Marketplace.
- Not legal advice; if Symposium is distributed at scale, have a real IP review, and
  make sure the brand PNG / any bundled fonts are cleared for redistribution.

## Quick sanity checklist
- [ ] `node -v` → `v24.15.0`; `python --version` → 3.11.x; `jq --version`, `7z`, `magick` on PATH
- [ ] `assets\out\win32\code.ico` exists (ran make-icons)
- [ ] `C:\src\vscodium\product.json` shows `"nameShort": "Symposium"` after apply-branding
- [ ] `extensionsGallery` in that file still points at `open-vsx.org` (we did NOT override it)
- [ ] build produced `assets\SymposiumSetup-x64-*.exe`
