# Symposium cloud host — runbook (GCP spot GPU VM)

Goal: run the Symposium host proxy on a cloud **GPU box** (Linux, no display) and
serve it at **`host.visionarysparks.in`** over **HTTPS**, so friends can chat with
your local models. Friends are **viewer-only**; only the **admin token** can pull
or delete models.

**Chosen path: a GCP Compute Engine _spot_ GPU VM in an isolated project.** Cheaper
GPU rentals exist (vast.ai / RunPod), but we chose GCP for the isolated-project +
Cloud Billing budget-alert kill-switch integration. Spot pricing + "normally
stopped" keeps it ₹0-first.

> **You (the founder) run every command below.** These artifacts are config +
> runbook only — nothing here provisions real infrastructure or touches billing.
> Placeholders like `<STATIC_IP>`, `<INSTANCE>`, `<ZONE>`, `<PROJECT>` are yours to fill.

Files in this folder:

| File | Purpose |
|---|---|
| `Caddyfile` | Terminates HTTPS at `host.visionarysparks.in`, forwards to the proxy on `:47475`. |
| `systemd/ollama.service` | Runs Ollama bound to `127.0.0.1:11434`. |
| `systemd/symposium-host.service` | Runs the Symposium host proxy on `:47475` (entrypoint built separately). |
| `symposium-host.env.example` | Template for `/etc/symposium-host.env` (pairing code + admin token). |
| `killswitch/budget-guard.sh` | Stops the GPU VM to enforce the ₹5,000 cap. |

Architecture: **internet → Caddy (:443, TLS) → Symposium proxy (:47475, auth) → Ollama (:11434)**.
Only 80 + 443 are public; `47475` and `11434` stay on localhost.

**The core cost rule:** the box is **normally STOPPED (₹0)** and started only for a
demo/test session, then stopped again. Spot fits this perfectly — you pay by the
second only while it runs, and spot preemption itself caps any runaway. End state:
**"Built + tested live, stopped (₹0)."** A 24/7 instance is NOT the plan.

---

## 1. Isolated GCP project + GPU quota

Keep the GPU host in its **own project**, separate from `visionary-sparks`, so its
spend, budget alert, and kill-switch are cleanly isolated.

```bash
gcloud projects create <PROJECT>            # e.g. symposium-gpu-host
gcloud billing projects link <PROJECT> --billing-account <BILLING_ACCOUNT_ID>
gcloud config set project <PROJECT>
gcloud services enable compute.googleapis.com --project <PROJECT>
```

**GPU quota — do this FIRST (it can take hours to a day).** New projects have a
default GPU quota of 0. Request quota in your chosen region before creating the VM:

- Console → **IAM & Admin → Quotas & System Limits** → filter for the GPU quota in
  your region, e.g. `NVIDIA T4 GPUs` (metric `NVIDIA_T4_GPUS`) or `NVIDIA L4 GPUs`
  (`NVIDIA_L4_GPUS`) → request **1**.
- Also confirm a **Preemptible/Spot GPU** quota exists for that GPU type in-region.
- If `gcloud compute instances create` later fails with `QUOTA_EXCEEDED` for GPUs,
  the quota request hasn't been granted yet — wait, don't retry blindly.

---

## 2. Reserve a static external IP

The DNS `A` record must point at a **stable** IP. An ephemeral IP changes on every
stop/start (and this box stops often), which would break DNS + the cert. Reserve
one regional static IP and attach it to the VM:

```bash
gcloud compute addresses create symposium-host-ip \
  --project <PROJECT> --region <REGION>
# read it back — this is <STATIC_IP>:
gcloud compute addresses describe symposium-host-ip \
  --project <PROJECT> --region <REGION> --format='value(address)'
```

> `--no-address` (no external IP) is fine ONLY for a private/SSH-via-IAP test box.
> For a public host that Let's Encrypt must reach, you need the **reserved static
> IP** attached (step 3 uses `--address symposium-host-ip`).

---

## 3. Create the spot GPU VM

Concrete command — a spot T4 on `n1-standard-4`, Deep Learning (CUDA) image, static
IP attached, auto-install NVIDIA drivers, and firewall tag `symposium-host`:

```bash
gcloud compute instances create <INSTANCE> \
  --project <PROJECT> --zone <ZONE> \
  --provisioning-model=SPOT \
  --instance-termination-action=STOP \
  --machine-type=n1-standard-4 \
  --accelerator=type=nvidia-tesla-t4,count=1 \
  --maintenance-policy=TERMINATE \
  --image-family=common-cu124-debian-11 \
  --image-project=deeplearning-platform-release \
  --metadata=install-nvidia-driver=True \
  --boot-disk-size=100GB --boot-disk-type=pd-balanced \
  --address symposium-host-ip \
  --tags symposium-host
```

Key flags:
- `--provisioning-model=SPOT` — spot pricing (much cheaper than on-demand).
- `--instance-termination-action=STOP` — on preemption the VM **stops** (disk kept),
  it is not deleted; you just start it again. Preemption also naturally caps cost.
- `--accelerator=type=nvidia-tesla-t4,count=1` on `n1-standard-4` — a solid, cheap
  GPU for small-model inference.
- **L4 alternative** (newer, more VRAM, needs the G2 family — do NOT mix L4 with
  `n1-*`): swap the two lines above for
  `--machine-type=g2-standard-4 --accelerator=type=nvidia-l4,count=1`.
- `--image-family=common-cu124-debian-11 --image-project=deeplearning-platform-release`
  — Google's Deep Learning VM image with CUDA preinstalled; `install-nvidia-driver=True`
  finishes driver setup on first boot.
- `--address symposium-host-ip` — attach the reserved static IP from step 2.

---

## 4. DNS — point the subdomain at the box

At your DNS provider (**Cloudflare**), add:

```
Type: A    Name: host    Value: <STATIC_IP>    Proxy: DNS only (grey cloud)
```

- Start **DNS-only (grey cloud)** so Let's Encrypt's HTTP-01 challenge reaches
  Caddy directly and the cert issues cleanly.
- Later you *may* switch to **Proxied (orange cloud)** for Cloudflare's edge/DDoS
  benefits — but then TLS terminates at Cloudflare; only do this after HTTPS works
  end-to-end, and set Cloudflare SSL mode to **Full (strict)**.

Verify it resolves before continuing:
```bash
dig +short host.visionarysparks.in    # should print <STATIC_IP>
```

---

## 5. Install on the box (Ollama, Caddy, Dart)

SSH in (`gcloud compute ssh <INSTANCE> --zone <ZONE> --project <PROJECT>`), then:

```bash
# Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Caddy — ships its own caddy.service, we don't write one
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy

# Dart SDK (runs the Symposium host entrypoint)
wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/dart.gpg
echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download/storage/v1/b/dart-archive/o?prefix=channels/stable/release/latest/linux_packages/ stable main' | sudo tee /etc/apt/sources.list.d/dart_stable.list
sudo apt update && sudo apt install -y dart

# Clone the repo (adjust path to match WorkingDirectory in the unit)
sudo mkdir -p /opt/symposium && sudo chown "$USER" /opt/symposium
git clone https://github.com/samaruban0317/symposium.git /opt/symposium
# app dir = /opt/symposium/app  (contains bin/symposium_host.dart, built separately)
```

Drop the config into place:

```bash
# Secrets
sudo cp /opt/symposium/deploy/symposium-host.env.example /etc/symposium-host.env
sudo chmod 600 /etc/symposium-host.env
sudo nano /etc/symposium-host.env    # fill SYMPOSIUM_PAIRING_CODE + SYMPOSIUM_ADMIN_TOKEN

# systemd units
sudo cp /opt/symposium/deploy/systemd/ollama.service /etc/systemd/system/
sudo cp /opt/symposium/deploy/systemd/symposium-host.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ollama
sudo systemctl enable --now symposium-host

# Caddy config
sudo cp /opt/symposium/deploy/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Pull at least one model as admin (see step 8), e.g. `ollama pull llama3.2`.

---

## 6. Firewall — only 80 + 443 public

`11434` (Ollama) and `47475` (Symposium proxy) must **never** be reachable from the
internet — they're bound to localhost and the firewall must not open them.

```bash
gcloud compute firewall-rules create symposium-web \
  --project <PROJECT> --direction INGRESS --action ALLOW \
  --rules tcp:80,tcp:443 --target-tags symposium-host
# the VM already carries the `symposium-host` tag (step 3); do NOT open 11434/47475
```

Sanity check from your laptop — these should **fail/timeout** (good):
```bash
nc -vz host.visionarysparks.in 11434   # must NOT connect
nc -vz host.visionarysparks.in 47475   # must NOT connect
```

---

## 7. HTTPS — Caddy auto-provisions the cert

Once DNS resolves and 80/443 are open, Caddy requests a Let's Encrypt cert
automatically on first start/reload. Verify:

```bash
curl -I https://host.visionarysparks.in            # expect a TLS response (401 is fine — see below)
sudo journalctl -u caddy -n 50 --no-pager           # look for "certificate obtained"
```

A `401` with "pairing code missing" is the **correct** result of an
unauthenticated request — it proves TLS works AND the app-layer auth is live.
A real request needs the `x-symposium-code` header:

```bash
curl -H 'x-symposium-code: <YOUR_6_DIGIT_CODE>' https://host.visionarysparks.in/api/tags
```

---

## 8. Admin "download any model" vs viewer-only

- Pulling, creating, copying, pushing, or **deleting** models is **admin-only**:
  the request must carry `x-symposium-admin: <SYMPOSIUM_ADMIN_TOKEN>` (enforced in
  `app/lib/net/host_server.dart`).
- Friends get the 6-digit pairing code only → they can **chat/read** but get
  `403` on any management endpoint. They cannot pull or delete models.
- As admin, pull models straight on the box (simplest):
  ```bash
  ollama pull llama3.2
  ```
  or remotely with the admin header:
  ```bash
  curl -X POST https://host.visionarysparks.in/api/pull \
    -H 'x-symposium-code: <YOUR_6_DIGIT_CODE>' \
    -H 'x-symposium-admin: <YOUR_ADMIN_TOKEN>' \
    -d '{"name":"llama3.2"}'
  ```

---

## 9. The ₹5,000 kill-switch

Three layers — the first is the real ₹0 guarantee:

1. **Normally STOPPED (habit).** Start the box only for a demo/test, stop it right
   after. Spot pricing means you pay only while it runs.
   ```bash
   gcloud compute instances stop <INSTANCE> --zone <ZONE> --project <PROJECT>
   gcloud compute instances start <INSTANCE> --zone <ZONE> --project <PROJECT>   # when needed
   ```

2. **Spot preemption** already caps runaway cost: with
   `--instance-termination-action=STOP`, if Google reclaims capacity the VM stops
   itself (disk preserved) rather than billing indefinitely.

3. **Automated ₹5,000 cap (Cloud Billing budget → Pub/Sub → Cloud Function):**
   - In the **isolated `<PROJECT>`**, create a Cloud Billing **budget** at
     **₹5,000, alert threshold 100%**.
   - Connect the budget to a **Pub/Sub topic**.
   - A tiny **Cloud Function** subscribed to that topic runs the stop from
     `killswitch/budget-guard.sh` (with `CONFIRM=1` and `INSTANCE/ZONE/PROJECT` set).
   - `budget-guard.sh` stays a pure `gcloud compute instances stop` — reversible,
     never destructive.

   Test the script safely first (prints, does nothing):
   ```bash
   INSTANCE=<INSTANCE> ZONE=<ZONE> PROJECT=<PROJECT> ./killswitch/budget-guard.sh
   # then arm for real inside the Function with CONFIRM=1
   ```

---

## 10. "Safe to share" checklist (before sending the link to friends)

- [ ] `https://host.visionarysparks.in` loads over **HTTPS** (valid Let's Encrypt cert).
- [ ] Unauthenticated request returns **401** (pairing enforced), not the raw engine.
- [ ] A friend's pairing code can **chat** but gets **403** on `/api/pull` and
      `/api/delete` (viewer-only confirmed).
- [ ] The **admin token** is long, random, and shared with **nobody**.
- [ ] Ports **11434** and **47475** are **not** reachable from the internet.
- [ ] The **budget guard** is armed (₹5,000 budget → Pub/Sub → Function → stop).
- [ ] The box is **stopped by default** — end state is "Built + tested live, stopped (₹0)."
