# make-icons.ps1 — Symposium IDE icon pipeline (Windows / PowerShell)
# ---------------------------------------------------------------------------
# Turns the 1024x1024 brand PNG into every icon file VSCodium/VS Code needs.
# Output lands in .\out\  (win32/ darwin/ linux/) ready for apply-branding.ps1.
#
# REQUIRES ImageMagick v7 ("magick" on PATH). Install:  winget install ImageMagick.Q16
#   (macOS .icns also needs `png2icns` OR is emitted by ImageMagick's ICNS coder.)
# If ImageMagick is missing, this script prints the exact sizes to hand-produce.
#
# NOTE ON THE SOURCE ART:
#   ../../app/assets/brand/visionarysparks-logo.png is a 1024x1024 teal Sparks
#   logo WITH a wordmark and lots of transparent padding. Small icons (16/32px,
#   taskbar, tray) will look muddy if we just downscale the whole thing.
#   -> We trim transparent padding, re-pad to a clean square, and center it.
#   -> RECOMMENDED: also make a GLYPH-ONLY mark (sparks symbol, no wordmark) and
#      pass it via -SmallMark for the <=48px sizes. See README-assets.md.
# ---------------------------------------------------------------------------
param(
  [string]$Src       = "$PSScriptRoot\..\..\..\app\assets\brand\visionarysparks-logo.png",
  [string]$SmallMark = "",                       # optional glyph-only 1024 PNG for small sizes
  [string]$OutDir    = "$PSScriptRoot\out",
  [int]   $PadPct    = 12                          # % padding around trimmed art in the square
)

$ErrorActionPreference = "Stop"
$magick = (Get-Command magick -ErrorAction SilentlyContinue)

if (-not (Test-Path $Src)) { throw "Source brand PNG not found: $Src" }

# Required sizes/files, grouped by platform ----------------------------------
$winPng   = @(150, 70)                              # tile PNGs (code_150x150 / code_70x70)
$icoSizes = @(16, 24, 32, 48, 64, 128, 256)         # embedded in code.ico / default.ico
$icnsSizes= @(16, 32, 64, 128, 256, 512, 1024)      # code.icns
$linuxPng = 512                                     # code.png (Linux)
# Inno Setup installer bitmaps (BMP, NON-transparent, brand-colour background):
#   inno-big-*.bmp  ~164x314 @100%  (wizard left panel)
#   inno-small-*.bmp ~55x58  @100%  (top-right header)
# scaled for 100/125/150/175/200/225/250 %. We generate the base @100% and the
# founder can let Inno stretch, OR generate all scales (loop below).
$innoScales = @(100,125,150,175,200,225,250)
$bgColor    = "#0d3b3b"   # deep teal backdrop for opaque installer BMPs — TUNE to brand

if (-not $magick) {
  Write-Host "ImageMagick not found. Install:  winget install ImageMagick.Q16" -ForegroundColor Yellow
  Write-Host "Then re-run. Required outputs (produce by hand if needed):" -ForegroundColor Yellow
  Write-Host "  win32/code.ico + default.ico : multi-size ICO $($icoSizes -join ',') px"
  Write-Host "  win32/code_150x150.png, code_70x70.png"
  Write-Host "  win32/inno-big-*.bmp (164x314 base, opaque $bgColor), inno-small-*.bmp (55x58) @ $($innoScales -join '/') %"
  Write-Host "  darwin/code.icns : $($icnsSizes -join ',') px"
  Write-Host "  linux/code.png   : ${linuxPng}x${linuxPng}"
  exit 1
}

New-Item -ItemType Directory -Force -Path "$OutDir\win32","$OutDir\darwin","$OutDir\linux" | Out-Null

# Build a clean, trimmed, padded square master (transparent) ------------------
function New-Square([string]$in, [string]$out) {
  # trim transparent border, resize into a padded box, then extent to 1024 square
  $inner = 1024 - [int][math]::Round(1024 * 2 * $PadPct / 100)
  & magick $in -trim +repage -background none `
    -resize "${inner}x${inner}" -gravity center -extent "1024x1024" $out
}
$masterFull = "$OutDir\_master_full.png"
New-Square $Src $masterFull
$masterSmall = $masterFull
if ($SmallMark -and (Test-Path $SmallMark)) {
  $masterSmall = "$OutDir\_master_small.png"
  New-Square $SmallMark $masterSmall
}

# Windows .ico (use small mark for <=48, full for the rest) -------------------
$icoTmp = @()
foreach ($s in $icoSizes) {
  $srcM = if ($s -le 48) { $masterSmall } else { $masterFull }
  $p = "$OutDir\_ico_$s.png"; & magick $srcM -resize "${s}x${s}" $p; $icoTmp += $p
}
& magick $icoTmp "$OutDir\win32\code.ico"
Copy-Item "$OutDir\win32\code.ico" "$OutDir\win32\default.ico" -Force

# Windows tile PNGs ----------------------------------------------------------
foreach ($s in $winPng) { & magick $masterFull -resize "${s}x${s}" "$OutDir\win32\code_${s}x${s}.png" }

# Inno Setup installer BMPs (opaque, flattened on brand bg) -------------------
# PowerShell can't do ImageMagick's inline "( ... )" parenthesized read; so we
# resize the art to a temp PNG first, then composite it onto an opaque canvas.
foreach ($sc in $innoScales) {
  $bw = [int][math]::Round(164 * $sc / 100); $bh = [int][math]::Round(314 * $sc / 100)
  $sw = [int][math]::Round(55  * $sc / 100); $sh = [int][math]::Round(58  * $sc / 100)

  $bigArt = "$OutDir\_inno_big_$sc.png"
  & magick $masterFull -resize "$([int][math]::Round($bw*0.7))x" $bigArt
  & magick -size "${bw}x${bh}" "xc:$bgColor" $bigArt -gravity center -composite -flatten "BMP3:$OutDir\win32\inno-big-$sc.bmp"

  $smArt = "$OutDir\_inno_small_$sc.png"
  $smDim = [int][math]::Round($sh * 0.8)
  & magick $masterSmall -resize "${smDim}x${smDim}" $smArt
  & magick -size "${sw}x${sh}" "xc:$bgColor" $smArt -gravity center -composite -flatten "BMP3:$OutDir\win32\inno-small-$sc.bmp"
}

# macOS .icns ----------------------------------------------------------------
$icnsTmp = @()
foreach ($s in $icnsSizes) {
  $srcM = if ($s -le 48) { $masterSmall } else { $masterFull }
  $p = "$OutDir\_icns_$s.png"; & magick $srcM -resize "${s}x${s}" $p; $icnsTmp += $p
}
& magick $icnsTmp "$OutDir\darwin\code.icns"

# Linux png ------------------------------------------------------------------
& magick $masterFull -resize "${linuxPng}x${linuxPng}" "$OutDir\linux\code.png"

Remove-Item "$OutDir\_*.png" -Force -ErrorAction SilentlyContinue
Write-Host "Icons written to $OutDir  (win32/ darwin/ linux/). Next: run ..\apply-branding.ps1" -ForegroundColor Green
