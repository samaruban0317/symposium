# GCP GPU quickstart — the friendly on-ramp

**Goal:** rent a GPU box in the cloud, host models on it, download / use / delete
them, then tear it all down to **₹0**. This is the *beginner* path — copy-paste,
one command at a time.

> **The golden rule:** the box is **normally STOPPED = ₹0**. You start it only for
> a session (learning, a demo, pulling a model), then **STOP** it again. On SPOT
> pricing you pay by the second **only while it runs**. A 24/7 box is NOT the plan.

**This project:** `visionary-ml-lab` — billing enabled, ~**₹28,710 free credit
expiring 24 Sep 2026**. Everything below runs in that project. Nothing here spends
money until *you* run a `create`/`start` command.

**Want the real public host** (friends chat over HTTPS at `host.visionarysparks.in`,
Caddy TLS, pairing codes, admin/viewer tiers, budget kill-switch)? That's the
production runbook — see **[`deploy/README.md`](./README.md)**. This file is just
the on-ramp: get a GPU running and talking to your Symposium desktop app.

**Placeholders** (fill these in): `<ZONE>` (default `asia-southeast1-b`),
`<REGION>` (default `asia-southeast1`). The instance is named `symposium-gpu`
throughout; the static IP is `symposium-ip`.

---

## 0. Before you start — two decisions

| Decision | Options | Beginner pick |
|---|---|---|
| **Region / zone** | anywhere Google has GPUs | `asia-southeast1` / `asia-southeast1-b` (Singapore — close to India, same region the main app uses) |
| **GPU** | **T4** (older, cheaper, 16 GB) vs **L4** (newer, faster, 24 GB) | Start with **T4** — cheapest, fine for 8B models. Move to **L4** if you need bigger/faster. |

You can't just create a GPU VM out of the box — you must **request GPU quota
first** (step 1). That approval can take **minutes to hours**, so do it early.

---

## 1. One-time prep (login, project, GPU quota)

```bash
# log in (opens a browser)
gcloud auth login

# point every command at this project
gcloud config set project visionary-ml-lab

# make sure Compute Engine is on
gcloud services enable compute.googleapis.com
```

**Request GPU quota — do this FIRST.** New projects have a GPU quota of **0**, so
`create` will fail with `QUOTA_EXCEEDED` until you raise it. There's no clean
`gcloud` flow for this — use the Console:

1. Console → **IAM & Admin → Quotas & System Limits**.
2. In the filter, search the GPU you picked, e.g. **`NVIDIA T4 GPUs`** or
   **`NVIDIA L4 GPUs`** (or the broader **`GPUs (all regions)`**).
3. Pick the row for your region (`asia-southeast1`), tick it → **Edit Quotas** →
   request a **new limit of `1`** → submit.
4. **Wait for the approval email.** It can take minutes to hours. Until it lands,
   creating the VM will fail — that's expected, don't retry blindly.

> Quota must exist **before** you create the VM. This is the #1 thing that trips
> up beginners.

---

## 2. Reserve a static IP (optional now)

Skip this if you only ever use the SSH tunnel (step 6). Reserve it now if you
think you'll want a stable public address later (the `deploy/README.md` host):

```bash
gcloud compute addresses create symposium-ip --region=asia-southeast1
# read it back:
gcloud compute addresses describe symposium-ip \
  --region=asia-southeast1 --format='value(address)'
```

A reserved static IP is **free while attached to a running VM**, but costs a small
amount while it sits **unused/reserved**. If you're not using it, **release it**
(step 7).

---

## 3. Create the SPOT GPU VM

Pick ONE of the two commands. Both use **SPOT** pricing (much cheaper) with
`--instance-termination-action=STOP`, so if Google reclaims capacity the VM
**stops itself** (disk kept) instead of billing forever — a built-in cost cap.

**(a) L4 — newer, faster, 24 GB (G2 family):**

```bash
gcloud compute instances create symposium-gpu \
  --project=visionary-ml-lab \
  --zone=asia-southeast1-b \
  --provisioning-model=SPOT \
  --instance-termination-action=STOP \
  --machine-type=g2-standard-4 \
  --accelerator=type=nvidia-l4,count=1 \
  --maintenance-policy=TERMINATE \
  --image-family=common-cu129-ubuntu-2204-nvidia-580 \
  --image-project=deeplearning-platform-release \
  --metadata=install-nvidia-driver=True \
  --boot-disk-size=100GB
```

**(b) T4 — older, cheapest, 16 GB (N1 family):**

```bash
gcloud compute instances create symposium-gpu \
  --project=visionary-ml-lab \
  --zone=asia-southeast1-b \
  --provisioning-model=SPOT \
  --instance-termination-action=STOP \
  --machine-type=n1-standard-4 \
  --accelerator=type=nvidia-tesla-t4,count=1 \
  --maintenance-policy=TERMINATE \
  --image-family=common-cu129-ubuntu-2204-nvidia-580 \
  --image-project=deeplearning-platform-release \
  --metadata=install-nvidia-driver=True \
  --boot-disk-size=100GB
```

What the flags mean:

- `--provisioning-model=SPOT` — spot pricing, much cheaper than on-demand.
- `--instance-termination-action=STOP` — on preemption the VM **stops** (disk
  preserved), never deleted; just start it again later.
- `--accelerator=…` — the GPU. **Don't mix** an L4 with `n1-*` or a T4 with
  `g2-*`; the machine family and GPU go together as shown.
- `--image-family=common-cu129-ubuntu-2204-nvidia-580 --image-project=deeplearning-platform-release`
  — Google's Deep Learning image with CUDA preinstalled; `install-nvidia-driver=True`
  finishes the driver on first boot.
- `--maintenance-policy=TERMINATE` — required for GPU VMs.
- `--boot-disk-size=100GB` — room for model files (they're big).

> To attach the reserved static IP from step 2, add `--address=symposium-ip`.
> For the tunnel-only quickstart you don't need it.

**SPOT caveat:** a spot VM can be **preempted (stopped) at any time** if Google
needs the capacity. Great for cost, but don't rely on it staying up mid-demo —
your data on disk is safe, you just start it again.

---

## 4. Install Ollama on the box

```bash
# SSH in (first connection sets up keys automatically)
gcloud compute ssh symposium-gpu --zone=asia-southeast1-b --project=visionary-ml-lab
```

Then, **on the box**:

```bash
# confirm the GPU is visible (driver finished installing)
nvidia-smi        # should print a table with your L4 / T4

# install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# the installer sets up + starts a systemd service; confirm it's up
systemctl status ollama --no-pager
```

If `nvidia-smi` errors right after boot, the driver is still installing — wait a
minute and try again.

---

## 5. Download / use / list / delete models

All on the box (inside the SSH session):

```bash
ollama pull llama3.1:8b      # DOWNLOAD a model
ollama run llama3.1:8b       # USE it — interactive chat (type /bye to exit)
ollama list                  # LIST what's downloaded
ollama rm llama3.1:8b        # DELETE a model (frees disk)
```

Model files are large; deleting ones you're done with keeps the 100 GB disk
comfortable.

---

## 6. Connect from the Symposium desktop app

**Quick / dev way — an SSH tunnel (no HTTPS, no public exposure):**

Open a tunnel from your laptop that forwards local `:11434` to Ollama on the box:

```bash
gcloud compute ssh symposium-gpu \
  --zone=asia-southeast1-b --project=visionary-ml-lab \
  -- -L 11434:localhost:11434
```

Leave that terminal open. In Symposium, point the engine at **`127.0.0.1:11434`** —
the app talks to the cloud GPU as if it were local. Close the terminal to end the
tunnel.

**Real public host** (friends connect over the internet with a pairing code):
that's the full runbook — Caddy HTTPS at `host.visionarysparks.in`, a 6-digit
pairing code for viewers, and `SYMPOSIUM_ADMIN_TOKEN` for the admin (who alone can
pull/delete models). See **[`deploy/README.md`](./README.md)**.

---

## 7. Cost control (the important part)

**STOP when idle** — this is your everyday ₹0 habit. Spot billing stops when the
instance stops:

```bash
gcloud compute instances stop symposium-gpu --zone=asia-southeast1-b
# start it again next time you need it:
gcloud compute instances start symposium-gpu --zone=asia-southeast1-b
```

**DELETE entirely when you're done for good** (removes the VM + its boot disk):

```bash
gcloud compute instances delete symposium-gpu --zone=asia-southeast1-b
# and release the static IP so it stops costing while unused:
gcloud compute addresses delete symposium-ip --region=asia-southeast1
```

**Set a budget alert** as a safety net:

- Console → **Billing → Budgets & alerts → Create budget** → scope to project
  `visionary-ml-lab` → set an amount (e.g. **₹5,000**) with alerts at 50/90/100%.
- For an *automated* stop when the budget is hit (budget → Pub/Sub → Cloud
  Function), the script is already in this repo:
  **[`deploy/killswitch/budget-guard.sh`](./killswitch/budget-guard.sh)** — it's a
  pure `gcloud compute instances stop`, reversible, never destructive.

> **Credit note:** the ~₹28,710 credit **expires 24 Sep 2026**. It's real money
> while it lasts — a forgotten running GPU burns it fast. **STOP religiously.**

---

## 8. "Is it costing me anything right now?" checklist

Run/glance through these — all clear = ₹0:

```bash
# instance should say TERMINATED (stopped) or not exist at all
gcloud compute instances list

# no leftover static IP sitting unused (RESERVED but not IN_USE = small charge)
gcloud compute addresses list

# no orphaned disks left behind after a delete
gcloud compute disks list
```

- [ ] Instance state is **TERMINATED** (stopped) — or the instance is gone.
- [ ] No static IP in **RESERVED / unused** state (release it if so).
- [ ] No orphaned **disks** left over from a deleted VM.
- [ ] Budget alert is set on `visionary-ml-lab`.

End state you're aiming for: **"used it, stopped it (₹0)"** — or, when truly done,
**"deleted everything, IP released (₹0)."**
