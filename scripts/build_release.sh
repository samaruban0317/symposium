#!/usr/bin/env bash
# ============================================================================
#  Symposium — local release build (Linux host).
#  Mirrors .github/workflows/release.yml, but for building on your own machine.
#
#  Usage (from anywhere):
#      bash scripts/build_release.sh
#
#  Builds Linux (.tar.gz) + Android (.apk) — the two platforms a Linux host can
#  produce. (Windows .zip must be built on Windows; use build_release.ps1 there.)
#  Version is read from app/pubspec.yaml. Output goes to dist/ with versioned
#  names. Idempotent: safe to re-run; overwrites its own dist/ outputs.
# ============================================================================
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
app="$repo/app"
dist="$repo/dist"

# --- Read version from pubspec.yaml: `version: 0.2.1` or `0.2.1+3` -> 0.2.1 ---
ver_line="$(grep -E '^[[:space:]]*version:' "$app/pubspec.yaml" | head -n1)"
version="$(echo "$ver_line" | sed -E 's/^[[:space:]]*version:[[:space:]]*//' | tr -d '[:space:]' | cut -d'+' -f1)"
[ -n "$version" ] || { echo "Could not read version from app/pubspec.yaml" >&2; exit 1; }

echo "== Symposium release build (Linux host) =="
echo "   repo:    $repo"
echo "   version: $version"
echo

mkdir -p "$dist"
cd "$app"

# --- Linux .tar.gz -----------------------------------------------------------
echo "-> Building Linux..."
# GTK build deps are required; nudge the user if they're missing.
if ! dpkg -s libgtk-3-dev >/dev/null 2>&1; then
  echo "   (heads-up) install build deps first: sudo apt-get install -y ninja-build libgtk-3-dev" >&2
fi
flutter pub get
flutter create --platforms=linux .   # no-op if already present
flutter build linux --release

lin_out="$dist/Symposium-$version-linux.tar.gz"
rm -f "$lin_out"
tar -czf "$lin_out" -C build/linux/x64/release/bundle .
echo "   wrote $lin_out"

# --- Android .apk ------------------------------------------------------------
echo "-> Building Android APK..."
flutter build apk --release
apk_out="$dist/Symposium-$version-android.apk"
rm -f "$apk_out"
cp build/app/outputs/flutter-apk/app-release.apk "$apk_out"
echo "   wrote $apk_out"

echo
echo "== Done. dist/ contents: =="
ls -la "$dist"/Symposium-"$version"-* 2>/dev/null || true
echo
echo "Note: Windows .zip must be built on Windows — run scripts/build_release.ps1 there."
