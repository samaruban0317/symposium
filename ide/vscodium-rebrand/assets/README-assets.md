# Icon assets — Symposium IDE

`make-icons.ps1` / `make-icons.sh` take the brand PNG and emit an `out/` tree
(`win32/`, `darwin/`, `linux/`) that `apply-branding.ps1` copies into a cloned
VSCodium repo. Source art:
`../../app/assets/brand/visionarysparks-logo.png` — **1024x1024, RGBA, teal Sparks
logo with a wordmark and heavy transparent padding** (verified).

## Exact files each script produces (and where they go in VSCodium)

VSCodium copies `src/stable/resources/<os>/*` into `vscode/` during the build, so
we replace the files under `src/stable/resources/`:

| Output file | Replaces in VSCodium repo | Sizes / notes |
|---|---|---|
| `win32/code.ico` | `src/stable/resources/win32/code.ico` | multi-res ICO: 16,24,32,48,64,128,256 |
| `win32/default.ico` | `src/stable/resources/win32/default.ico` | same as code.ico (generic file icon) |
| `win32/code_150x150.png` | `src/stable/resources/win32/code_150x150.png` | Start-menu / tile |
| `win32/code_70x70.png` | `src/stable/resources/win32/code_70x70.png` | small tile |
| `win32/inno-big-<scale>.bmp` | `src/stable/resources/win32/inno-big-*.bmp` | Inno installer left panel, **opaque** 164x314 @100%, scales 100–250% |
| `win32/inno-small-<scale>.bmp` | `src/stable/resources/win32/inno-small-*.bmp` | Inno header, **opaque** 55x58 @100% |
| `darwin/code.icns` | `src/stable/resources/darwin/code.icns` | 16→1024 (mac target only) |
| `linux/code.png` | `src/stable/resources/linux/code.png` | 512x512 |

Language/file-type icons (`java.ico`, `python.icns`, …) are **left as-is** — they
are file-association glyphs, not product branding.

> `apply-branding.ps1` also refreshes the letterpress/window icons the running app
> uses: `src/stable/src/vs/workbench/browser/parts/editor/media/letterpress-*.svg`
> stays generic (it's a "no editor open" watermark, optional to rebrand) and the
> media PNGs under `vscode/resources/` are regenerated from the copied `code.*` at
> build time — you do **not** hand-edit anything inside `vscode/`.

## Small-size guidance
The full logo (symbol + "Visionary Sparks" wordmark + padding) turns to mush below
~48px. Provide a **glyph-only** 1024px PNG (just the Sparks mark, no text) and pass
it so the 16/24/32/48 px slots and the Inno small BMP use the clean mark:

```powershell
.\make-icons.ps1 -SmallMark ..\..\brand\symposium-glyph-1024.png
```
```bash
SMALL_MARK=../../brand/symposium-glyph-1024.png ./make-icons.sh
```
Without `-SmallMark`, small sizes fall back to the trimmed full logo (acceptable,
not ideal). The scripts auto-`-trim` transparent padding and re-pad to a clean
centered square (`-PadPct 12` default).

## Requirements
ImageMagick v7 (`magick`): `winget install ImageMagick.Q16`. If it's absent the
scripts print every required size so the founder can produce them by hand (e.g. in
Canva / GIMP export presets). The `.bmp` installer images **must be opaque** — tune
the `$bgColor` / `$BG` deep-teal backdrop to the brand.
