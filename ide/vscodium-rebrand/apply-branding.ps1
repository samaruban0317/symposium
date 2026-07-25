# apply-branding.ps1 — stamp Symposium branding onto a cloned VSCodium repo (Windows-first)
# ---------------------------------------------------------------------------
# Usage:
#   .\apply-branding.ps1 -Vscodium C:\src\vscodium
#   .\apply-branding.ps1 -Vscodium C:\src\vscodium -Vsix ..\extension\symposium-ml-0.1.0.vsix
#
# What it does (idempotent, defensive, backs up originals to *.orig-symposium):
#   (a) deep-merges product.overrides.json into <vscodium>/product.json
#       (this is the file prepare_vscode.sh merges OVER vscode/product.json)
#   (b) copies generated icons from assets/out/ into src/stable/resources/{win32,darwin,linux}
#   (c) copies the pre-built symposium-ml .vsix so it ships bundled as a built-in extension
#   (d) prints the exact next build steps
# ---------------------------------------------------------------------------
param(
  [Parameter(Mandatory=$true)][string]$Vscodium,
  [string]$Vsix = "",                          # path to symposium-ml *.vsix (optional)
  [string]$Kit  = $PSScriptRoot
)
$ErrorActionPreference = "Stop"

function Backup($f) { if ((Test-Path $f) -and -not (Test-Path "$f.orig-symposium")) { Copy-Item $f "$f.orig-symposium" } }

# --- validate ---------------------------------------------------------------
if (-not (Test-Path $Vscodium)) { throw "VSCodium repo not found: $Vscodium" }
if (-not (Test-Path (Join-Path $Vscodium "prepare_vscode.sh"))) {
  throw "$Vscodium doesn't look like a VSCodium clone (no prepare_vscode.sh). Clone https://github.com/VSCodium/vscodium first."
}
$overrides = Join-Path $Kit "product.overrides.json"
if (-not (Test-Path $overrides)) { throw "Missing $overrides" }

# --- (a) deep-merge product.json -------------------------------------------
# Strip our "//"-comment keys, then recursively merge over the repo product.json.
function Merge($base, $over) {
  foreach ($k in $over.PSObject.Properties.Name) {
    if ($k -like "//*") { continue }                                   # skip comments
    $v = $over.$k
    if ($v -is [psobject] -and $base.PSObject.Properties.Name -contains $k -and $base.$k -is [psobject]) {
      Merge $base.$k $v
    } else {
      if ($base.PSObject.Properties.Name -contains $k) { $base.$k = $v }
      else { $base | Add-Member -NotePropertyName $k -NotePropertyValue $v }
    }
  }
}
$prod = Join-Path $Vscodium "product.json"
Backup $prod
$baseJson = if (Test-Path $prod) { Get-Content $prod -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
$overJson = Get-Content $overrides -Raw | ConvertFrom-Json
Merge $baseJson $overJson
($baseJson | ConvertTo-Json -Depth 40) | Set-Content $prod -Encoding UTF8
Write-Host "[a] merged product.overrides.json -> $prod" -ForegroundColor Green

# --- (b) copy icons ---------------------------------------------------------
$iconOut = Join-Path $Kit "assets\out"
if (-not (Test-Path $iconOut)) {
  Write-Host "[b] SKIP icons: $iconOut not found. Run assets\make-icons.ps1 first." -ForegroundColor Yellow
} else {
  foreach ($os in "win32","darwin","linux") {
    $dst = Join-Path $Vscodium "src\stable\resources\$os"
    $src = Join-Path $iconOut $os
    if ((Test-Path $src) -and (Test-Path $dst)) {
      Get-ChildItem $src -File | ForEach-Object {
        $target = Join-Path $dst $_.Name
        Backup $target
        Copy-Item $_.FullName $target -Force
      }
      Write-Host "[b] copied $os icons -> $dst" -ForegroundColor Green
    }
  }
}

# --- (c) bundle the symposium-ml extension ---------------------------------
# VSCodium ships extra builtin extensions listed in a JSON manifest; the simplest
# robust bundling is to drop the .vsix into VS Code's built-in extensions dir so
# it's packaged into the app. We place it under vscode/.build/... at build time is
# fragile, so instead we stage it in the kit's known location and let the RUNBOOK
# install it post-package OR add it to product.json builtInExtensions.
if ($Vsix -ne "") {
  if (-not (Test-Path $Vsix)) { Write-Host "[c] SKIP: vsix not found: $Vsix" -ForegroundColor Yellow }
  else {
    $extStage = Join-Path $Vscodium "symposium-builtins"
    New-Item -ItemType Directory -Force -Path $extStage | Out-Null
    Copy-Item $Vsix (Join-Path $extStage (Split-Path $Vsix -Leaf)) -Force
    Write-Host "[c] staged $(Split-Path $Vsix -Leaf) -> $extStage" -ForegroundColor Green
    Write-Host "    (RUNBOOK step 6 folds this into the packaged app.)" -ForegroundColor DarkGray
  }
} else {
  Write-Host "[c] no -Vsix given; skipping extension bundling (build it in ..\extension first)." -ForegroundColor Yellow
}

# --- (d) next steps ---------------------------------------------------------
Write-Host ""
Write-Host "DONE. Next (from Git Bash inside $Vscodium):" -ForegroundColor Cyan
Write-Host '  export OS_NAME="windows"; export VSCODE_ARCH="x64"; export VSCODE_QUALITY="stable"'
Write-Host '  export SHOULD_BUILD="yes"; export CI_BUILD="no"; export SHOULD_BUILD_REH="no"; export SHOULD_BUILD_REH_WEB="no"'
Write-Host '  . ./get_repo.sh && . ./build.sh && . ./prepare_assets.sh'
Write-Host "Installer output -> $Vscodium\assets\SymposiumSetup-x64-<ver>.exe  (see RUNBOOK.md)"
