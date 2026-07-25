# Connect a GPU

A "GPU" here just means **a place to run your models**. Symposium can talk to a
model engine anywhere — on this laptop, on a friend's PC, or on a cloud box you
rent by the second. You pick one and Symposium remembers it.

Run **Symposium: Connect a GPU…** (Command Palette) and choose:

## This PC (local)
Best when you already run **Ollama** or the **Symposium host** on this machine.
Symposium checks that it's reachable and you're done — free, offline, private.
Nothing installed yet? Get Ollama from <https://ollama.com/download>, then re-run
the wizard.

## A friend's or my other PC (LAN)
Your friend runs the Symposium host and shares an address like
`http://192.168.1.20:47475`. Paste it. If they protected it with a **6-digit
pairing code**, add it under `symposium.ai.local.pairingCode`.

## Google Cloud spot GPU
Rent a real cloud GPU when you need to run bigger models. The wizard opens a
step-by-step runbook and can copy the exact `gcloud` commands for you. The golden
rule: the box is **normally STOPPED = ₹0** — you start it only for a session and
stop it right after. On spot pricing you pay by the second only while it runs.

The quick path uses an SSH tunnel, so your cloud GPU shows up at
`http://127.0.0.1:11434` just like a local one. The full public host (friends
connect over HTTPS with a pairing code) is in `deploy/README.md`.

## Rented GPU (paste URL)
Already have a box on vast.ai / RunPod / your own server? Paste its URL — public
HTTPS or a local tunnel address both work.

---

Once connected, open the **Models** view to browse recommended models and
download any model you like. Downloads stream a live progress bar right in the
sidebar. On a shared host, **downloading** models needs the admin token
(`symposium.ai.local.adminToken`); viewers can chat but not pull.
