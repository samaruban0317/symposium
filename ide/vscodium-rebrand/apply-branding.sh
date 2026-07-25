#!/usr/bin/env bash
# apply-branding.sh — mirror of apply-branding.ps1 (macOS/Linux/Git-Bash)
# Usage: ./apply-branding.sh <path-to-vscodium-clone> [path-to-symposium-ml.vsix]
# Deep-merges product.overrides.json (via jq), copies icons, stages the vsix,
# backs up originals to *.orig-symposium, idempotent.
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
VSCODIUM="${1:?Usage: ./apply-branding.sh <vscodium-clone> [vsix]}"
VSIX="${2:-}"

backup() { [ -f "$1" ] && [ ! -f "$1.orig-symposium" ] && cp "$1" "$1.orig-symposium" || true; }

[ -d "$VSCODIUM" ] || { echo "VSCodium repo not found: $VSCODIUM" >&2; exit 1; }
[ -f "$VSCODIUM/prepare_vscode.sh" ] || { echo "Not a VSCodium clone (no prepare_vscode.sh): $VSCODIUM" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required (VSCodium needs it anyway)." >&2; exit 1; }

# (a) deep-merge product.json — strip //-comment keys, then base * overrides (overrides win)
PROD="$VSCODIUM/product.json"
backup "$PROD"
BASE="$PROD"; [ -f "$PROD" ] || BASE=<(echo '{}')
OVR="$(jq 'with_entries(select(.key | startswith("//") | not))' "$KIT/product.overrides.json")"
jq -s '.[0] * .[1]' "$BASE" <(echo "$OVR") > "$PROD.tmp" && mv "$PROD.tmp" "$PROD"
echo "[a] merged product.overrides.json -> $PROD"

# (b) icons
ICON_OUT="$KIT/assets/out"
if [ -d "$ICON_OUT" ]; then
  for os in win32 darwin linux; do
    dst="$VSCODIUM/src/stable/resources/$os"
    if [ -d "$ICON_OUT/$os" ] && [ -d "$dst" ]; then
      for f in "$ICON_OUT/$os"/*; do
        [ -f "$f" ] || continue
        backup "$dst/$(basename "$f")"
        cp -f "$f" "$dst/"
      done
      echo "[b] copied $os icons -> $dst"
    fi
  done
else
  echo "[b] SKIP icons: $ICON_OUT missing (run assets/make-icons.sh first)."
fi

# (c) stage vsix
if [ -n "$VSIX" ]; then
  if [ -f "$VSIX" ]; then
    mkdir -p "$VSCODIUM/symposium-builtins"
    cp -f "$VSIX" "$VSCODIUM/symposium-builtins/"
    echo "[c] staged $(basename "$VSIX") -> $VSCODIUM/symposium-builtins"
  else echo "[c] SKIP: vsix not found: $VSIX"; fi
else echo "[c] no vsix arg; skipping extension bundling."; fi

# (d) next steps
cat <<EOF

DONE. Next (inside $VSCODIUM):
  export OS_NAME="windows" VSCODE_ARCH="x64" VSCODE_QUALITY="stable"
  export SHOULD_BUILD="yes" CI_BUILD="no" SHOULD_BUILD_REH="no" SHOULD_BUILD_REH_WEB="no"
  . ./get_repo.sh && . ./build.sh && . ./prepare_assets.sh
Installer output -> $VSCODIUM/assets/SymposiumSetup-x64-<ver>.exe  (see RUNBOOK.md)
EOF
