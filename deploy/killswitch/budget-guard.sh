#!/usr/bin/env bash
# =============================================================================
# budget-guard.sh — the ₹5,000 kill-switch for the Symposium GPU box.
# -----------------------------------------------------------------------------
# WHAT IT DOES: stops the GPU instance so it stops billing. Nothing else.
#
# HOW IT SHOULD BE WIRED (the founder does this — not automatic):
#   Preferred: Cloud Billing budget (₹5,000, 100% threshold) → Pub/Sub topic →
#              Cloud Function that runs `gcloud compute instances stop ...`
#              (this script is the reference for that stop command).
#   Simpler:   a cron job on another always-free machine that polls
#              `gcloud billing` and calls this script when spend nears the cap.
#
# This script stays provider-command-only and SAFE: it does nothing destructive
# and defaults to --dry-run. It only STOPS the box (reversible), never deletes.
#
# USAGE:
#   ./budget-guard.sh              # dry-run: prints what it WOULD do
#   CONFIRM=1 ./budget-guard.sh    # actually stop the instance
#
# ENV (override the placeholders):
#   INSTANCE  GPU VM name        (default: symposium-gpu)
#   ZONE      GCP zone           (default: asia-southeast1-b)
#   PROJECT   isolated GCP proj  (default: symposium-gpu-host)
# =============================================================================
set -euo pipefail

INSTANCE="${INSTANCE:-symposium-gpu}"
ZONE="${ZONE:-asia-southeast1-b}"
PROJECT="${PROJECT:-symposium-gpu-host}"

# Assemble the stop command once so dry-run prints EXACTLY what would run.
CMD=(gcloud compute instances stop "$INSTANCE" --zone "$ZONE" --project "$PROJECT" --quiet)

echo "[budget-guard] target: instance=$INSTANCE zone=$ZONE project=$PROJECT"

if [[ "${CONFIRM:-0}" != "1" ]]; then
  echo "[budget-guard] DRY-RUN (set CONFIRM=1 to actually stop). Would run:"
  printf '    %q ' "${CMD[@]}"; echo
  exit 0
fi

echo "[budget-guard] CONFIRM=1 — stopping the GPU box now to cap spend..."
"${CMD[@]}"
echo "[budget-guard] stop command issued. Verify with: gcloud compute instances describe $INSTANCE --zone $ZONE --project $PROJECT --format='value(status)'"
