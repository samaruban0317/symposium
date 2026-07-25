#!/usr/bin/env bash
# make-icons.sh — Symposium IDE icon pipeline (macOS/Linux, mirror of make-icons.ps1)
# Requires ImageMagick v7 ("magick"). macOS .icns is best made with iconutil, but
# ImageMagick's ICNS coder also works. See README-assets.md for exact sizes.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$HERE/../../../app/assets/brand/visionarysparks-logo.png}"
SMALL_MARK="${SMALL_MARK:-}"     # optional glyph-only 1024 png for small sizes
OUT="${OUT:-$HERE/out}"
PADPCT="${PADPCT:-12}"
BG="#0d3b3b"                     # opaque installer background — tune to brand

[ -f "$SRC" ] || { echo "Source brand PNG not found: $SRC" >&2; exit 1; }
command -v magick >/dev/null || { echo "Install ImageMagick v7 (magick). Required sizes:"; \
  echo "  win32 ico: 16 24 32 48 64 128 256 | tiles 150 70 | inno bmp 164x314 & 55x58 @100-250%"; \
  echo "  darwin icns: 16 32 64 128 256 512 1024 | linux png: 512"; exit 1; }

mkdir -p "$OUT/win32" "$OUT/darwin" "$OUT/linux"

square() { # $1 in, $2 out — trim padding, resize into padded box, extent to 1024 square
  inner=$(( 1024 - 1024*2*PADPCT/100 ))
  magick "$1" -trim +repage -background none \
    -resize "${inner}x${inner}" -gravity center -extent 1024x1024 "$2"
}
MFULL="$OUT/_master_full.png"; square "$SRC" "$MFULL"
MSMALL="$MFULL"
if [ -n "$SMALL_MARK" ] && [ -f "$SMALL_MARK" ]; then MSMALL="$OUT/_master_small.png"; square "$SMALL_MARK" "$MSMALL"; fi

# Windows .ico
ICO=(); for s in 16 24 32 48 64 128 256; do
  m="$MFULL"; [ "$s" -le 48 ] && m="$MSMALL"
  p="$OUT/_ico_$s.png"; magick "$m" -resize "${s}x${s}" "$p"; ICO+=("$p")
done
magick "${ICO[@]}" "$OUT/win32/code.ico"; cp "$OUT/win32/code.ico" "$OUT/win32/default.ico"

# Windows tiles
for s in 150 70; do magick "$MFULL" -resize "${s}x${s}" "$OUT/win32/code_${s}x${s}.png"; done

# Inno Setup BMPs (opaque)
for sc in 100 125 150 175 200 225 250; do
  bw=$((164*sc/100)); bh=$((314*sc/100)); sw=$((55*sc/100)); sh=$((58*sc/100))
  magick -size "${bw}x${bh}" "xc:$BG" \( "$MFULL" -resize "$((bw*7/10))x" \) -gravity center -composite -flatten "BMP3:$OUT/win32/inno-big-$sc.bmp"
  magick -size "${sw}x${sh}" "xc:$BG" \( "$MSMALL" -resize "$((sh*8/10))x$((sh*8/10))" \) -gravity center -composite -flatten "BMP3:$OUT/win32/inno-small-$sc.bmp"
done

# macOS .icns
ICNS=(); for s in 16 32 64 128 256 512 1024; do
  m="$MFULL"; [ "$s" -le 48 ] && m="$MSMALL"
  p="$OUT/_icns_$s.png"; magick "$m" -resize "${s}x${s}" "$p"; ICNS+=("$p")
done
magick "${ICNS[@]}" "$OUT/darwin/code.icns"

# Linux
magick "$MFULL" -resize 512x512 "$OUT/linux/code.png"

rm -f "$OUT"/_*.png
echo "Icons written to $OUT (win32/ darwin/ linux/). Next: ../apply-branding.sh"
