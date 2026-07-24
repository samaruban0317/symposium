#!/usr/bin/env bash
# Symposium dev environment bootstrap (Linux / macOS / Arch).
#   bash scripts/setup_env.sh
# Idempotent: safe to re-run. Sets up the lab Python venv + .env files.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
echo "== Symposium setup ==  ($repo)"

check() {  # name  cmd
  if command -v "$2" >/dev/null 2>&1; then
    echo "  [ok]   $1 -> $(command -v "$2")"
  else
    echo "  [MISS] $1 — install it, then re-run"
  fi
}

echo
echo "Checking tools:"
check "Flutter" flutter
check "Dart"    dart
check "Ollama"  ollama
# Arch: 'ollama' via pacman; 'systemctl status ollama' to check the service.

PY=""
for cand in python3.11 python3; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys; exit(0 if sys.version_info[:2]==(3,11) else 1)' 2>/dev/null; then
    PY="$cand"; break
  fi
done
if [ -n "$PY" ]; then echo "  [ok]   Python 3.11 -> $PY"
else echo "  [MISS] Python 3.11 — the ML lab needs 3.11 (not 3.13/3.14)"; fi

# --- lab venv + deps (RAG, CPU-only) ---
if [ -n "$PY" ]; then
  venv="$repo/lab/.venv"
  [ -d "$venv" ] || { echo; echo "Creating lab venv (Python 3.11)..."; "$PY" -m venv "$venv"; }
  "$venv/bin/python" -m pip install --upgrade pip
  "$venv/bin/python" -m pip install -r "$repo/lab/requirements.txt"
  echo "  lab RAG deps installed. Activate with: source lab/.venv/bin/activate"
fi

# --- .env from .env.example (never overwrite a real one) ---
for pair in "lab/.env.example:lab/.env" "deploy/symposium-host.env.example:deploy/symposium-host.env"; do
  ex="$repo/${pair%%:*}"; dst="$repo/${pair##*:}"
  if [ -f "$ex" ] && [ ! -f "$dst" ]; then
    cp "$ex" "$dst"; echo "  created ${pair##*:} — fill in the placeholders"
  fi
done

echo
echo "Done. Next: cd lab && python rag_pipeline.py ingest ./data"
