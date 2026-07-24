<#
  Symposium — local release build (Windows host).
  Mirrors .github/workflows/release.yml, but for building on your own machine.

  Usage (from the repo root or anywhere):
      pwsh scripts/build_release.ps1

  Builds Windows (.zip) + Android (.apk) — the two platforms a Windows host can
  produce. (Linux .tar.gz can only be built on Linux; use build_release.sh there.)
  Version is read from app/pubspec.yaml. Output goes to dist/ with versioned names.
  Idempotent: safe to re-run; it overwrites its own dist/ outputs.
#>

$ErrorActionPreference = "Stop"

# --- Locate the repo + app, read version from pubspec.yaml -------------------
$repo    = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$appDir  = Join-Path $repo "app"
$distDir = Join-Path $repo "dist"

$pubspec = Get-Content (Join-Path $appDir "pubspec.yaml")
$verLine = $pubspec | Where-Object { $_ -match '^\s*version:\s*(.+)$' } | Select-Object -First 1
if (-not $verLine) { throw "Could not find a version: line in app/pubspec.yaml" }
# `version: 0.2.1` or `0.2.1+3` -> keep only the semver part before any '+'.
$version = ($verLine -replace '^\s*version:\s*', '').Trim().Split('+')[0]

Write-Host "== Symposium release build (Windows host) ==" -ForegroundColor Cyan
Write-Host "   repo:    $repo"
Write-Host "   version: $version"
Write-Host ""

New-Item -ItemType Directory -Force -Path $distDir | Out-Null
Push-Location $appDir
try {
    # --- Windows .zip --------------------------------------------------------
    Write-Host "-> Building Windows..." -ForegroundColor Yellow
    flutter pub get
    flutter create --platforms=windows .   # no-op if already present
    flutter build windows --release

    $winZip = Join-Path $distDir "Symposium-$version-windows.zip"
    if (Test-Path $winZip) { Remove-Item $winZip -Force }
    Compress-Archive -Path "build/windows/x64/runner/Release/*" -DestinationPath $winZip -Force
    Write-Host "   wrote $winZip" -ForegroundColor Green

    # --- Android .apk --------------------------------------------------------
    Write-Host "-> Building Android APK..." -ForegroundColor Yellow
    flutter build apk --release

    $apkOut = Join-Path $distDir "Symposium-$version-android.apk"
    if (Test-Path $apkOut) { Remove-Item $apkOut -Force }
    Copy-Item "build/app/outputs/flutter-apk/app-release.apk" $apkOut -Force
    Write-Host "   wrote $apkOut" -ForegroundColor Green
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "== Done. dist/ contents: ==" -ForegroundColor Cyan
Get-ChildItem $distDir -File | Where-Object { $_.Name -like "Symposium-$version-*" } |
    ForEach-Object { "{0,12:N0}  {1}" -f $_.Length, $_.Name }
Write-Host ""
Write-Host "Note: Linux .tar.gz must be built on Linux — run scripts/build_release.sh there." -ForegroundColor DarkGray
