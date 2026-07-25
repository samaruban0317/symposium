/**
 * "Connect a GPU" wizard — the friendly, non-expert path behind the
 * `symposium.connectGpu` command.
 *
 * A GPU is just "an endpoint that runs your models". This wizard walks the user
 * through four ways to point Symposium at one:
 *   1. This PC (local)            — verify the local host/Ollama is reachable.
 *   2. A friend's / my other PC   — paste a LAN URL.
 *   3. Google Cloud spot GPU      — open the guided runbook, offer to copy the
 *                                   exact gcloud commands, then paste the host URL.
 *   4. Rented GPU                  — paste any URL (vast.ai / RunPod / SSH tunnel).
 *
 * Whatever URL is chosen is written into settings:
 *   symposium.rig.url        (training service base)
 *   symposium.ai.local.url   (model endpoint — for cloud/LAN/rented hosts)
 *
 * The wizard never provisions anything or spends money. For GCP it only shows
 * the copy-paste commands from deploy/ — the founder runs them.
 */
import * as vscode from "vscode";
import { localEndpoints, localPairingCode } from "../ai/config";

type Choice = "local" | "lan" | "gcp" | "rented";

interface PickItem extends vscode.QuickPickItem {
  choice: Choice;
}

const CFG = "symposium";

/** Entry point for the `symposium.connectGpu` command. */
export async function connectGpu(): Promise<void> {
  const items: PickItem[] = [
    {
      choice: "local",
      label: "$(device-desktop) This PC (local)",
      description: "Use the GPU (or CPU) in this computer",
      detail: "Best if you already run Ollama or the Symposium host here. Free, offline, private."
    },
    {
      choice: "lan",
      label: "$(broadcast) A friend's or my other PC (LAN)",
      description: "Point at another machine on your network",
      detail: "Paste the host URL your friend shared (e.g. http://192.168.1.20:47475)."
    },
    {
      choice: "gcp",
      label: "$(cloud) Google Cloud spot GPU",
      description: "Rent a cloud GPU by the second (₹0 when stopped)",
      detail: "We'll show you the exact commands, step by step. Great for big models."
    },
    {
      choice: "rented",
      label: "$(link) Rented GPU (paste URL)",
      description: "vast.ai, RunPod, an SSH tunnel, or any host URL",
      detail: "Already have a GPU box running? Just paste its address."
    }
  ];

  const picked = await vscode.window.showQuickPick(items, {
    title: "Connect a GPU",
    placeHolder: "Where should Symposium run your models?",
    ignoreFocusOut: true
  });
  if (!picked) return; // cancelled

  switch (picked.choice) {
    case "local":
      return connectLocal();
    case "lan":
      return connectByUrl({
        title: "Connect a friend's / other PC",
        prompt: "Paste the host URL your friend shared",
        placeholder: "http://192.168.1.20:47475",
        reassurance: "This is the address of the Symposium host running on the other machine."
      });
    case "gcp":
      return connectGcp();
    case "rented":
      return connectByUrl({
        title: "Connect a rented GPU",
        prompt: "Paste the URL of your rented GPU host",
        placeholder: "https://your-box.example.com  or  http://127.0.0.1:11434 (SSH tunnel)",
        reassurance: "Use the public URL, or a local tunnel address if you forwarded the port over SSH."
      });
  }
}

/** Option 1 — verify the local endpoint is reachable, then keep the defaults. */
async function connectLocal(): Promise<void> {
  const { primary, fallback } = localEndpoints();
  const reached = await vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: "Checking your local model engine…" },
    async () => (await ping(primary)) || (await ping(fallback))
  );

  if (reached) {
    // Local is already the default; make sure both settings point home.
    await writeUrl("ai.local.url", reached);
    await writeUrl("rig.url", vscode.workspace.getConfiguration(CFG).get<string>("rig.url", "http://127.0.0.1:8765"));
    vscode.window.showInformationMessage(
      `Symposium is connected to your local engine at ${reached}. You're ready to browse & download models.`
    );
    void offerMarketplace();
    return;
  }

  const install = "How do I start it?";
  const paste = "Enter a URL instead";
  const choice = await vscode.window.showWarningMessage(
    `No model engine answered at ${primary} or ${fallback}. Start the Symposium host or Ollama, then try again.`,
    install,
    paste
  );
  if (choice === install) {
    void vscode.env.openExternal(vscode.Uri.parse("https://ollama.com/download"));
  } else if (choice === paste) {
    await connectByUrl({
      title: "Connect a model engine",
      prompt: "Paste your local model engine URL",
      placeholder: "http://127.0.0.1:11434",
      reassurance: "This is where Ollama or the Symposium host is listening."
    });
  }
}

interface UrlFlowOpts {
  title: string;
  prompt: string;
  placeholder: string;
  reassurance: string;
}

/** Options 2 & 4 (and GCP's final step) — validate a URL and save it. */
async function connectByUrl(opts: UrlFlowOpts): Promise<void> {
  const url = await vscode.window.showInputBox({
    title: opts.title,
    prompt: `${opts.prompt}. ${opts.reassurance}`,
    placeHolder: opts.placeholder,
    ignoreFocusOut: true,
    validateInput: (v) => (isValidHostUrl(v) ? undefined : "Enter an http:// or https:// URL.")
  });
  if (!url) return; // cancelled

  const clean = url.trim().replace(/\/+$/, "");

  // Offer a quick reachability check (non-blocking on failure — the box may be
  // asleep or behind auth, and that's fine to save anyway).
  const reachable = await vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: `Checking ${clean}…` },
    async () => ping(clean)
  );

  await writeUrl("ai.local.url", clean);
  await writeUrl("rig.url", clean);

  if (reachable) {
    vscode.window.showInformationMessage(`Connected to ${clean}. Symposium can now use this GPU.`);
  } else {
    vscode.window.showInformationMessage(
      `Saved ${clean}. It didn't answer just now (it may be asleep or need a pairing code) — Symposium will use it once it's up.`
    );
  }
  void offerMarketplace();
}

/** Option 3 — the guided Google Cloud spot-GPU flow. */
async function connectGcp(): Promise<void> {
  const openRunbook = "Open step-by-step runbook";
  const copyQuickstart = "Copy the quickstart commands";
  const havUrl = "I already have my host URL";

  const choice = await vscode.window.showInformationMessage(
    "Renting a Google Cloud GPU is a few copy-paste commands. The box is billed by the second and costs ₹0 while stopped. " +
      "Open the runbook to follow along, or copy the starter commands.",
    { modal: false },
    openRunbook,
    copyQuickstart,
    havUrl
  );

  if (choice === openRunbook) {
    await openDeployDoc("gcp-quickstart.md");
    // Fall through to also prompting for the URL once they've provisioned it.
    await promptGcpUrl();
  } else if (choice === copyQuickstart) {
    await vscode.env.clipboard.writeText(GCP_QUICKSTART_COMMANDS);
    const openToo = "Open full runbook";
    const next = await vscode.window.showInformationMessage(
      "Copied the GCP quickstart commands to your clipboard. Run them one at a time in a terminal, then come back with your host URL.",
      openToo,
      "Enter host URL"
    );
    if (next === openToo) await openDeployDoc("gcp-quickstart.md");
    await promptGcpUrl();
  } else if (choice === havUrl) {
    await promptGcpUrl();
  }
}

async function promptGcpUrl(): Promise<void> {
  await connectByUrl({
    title: "Connect your Google Cloud GPU",
    prompt: "Paste the host URL of your cloud box",
    placeholder: "https://host.visionarysparks.in  or  http://127.0.0.1:11434 (SSH tunnel)",
    reassurance:
      "Use your public HTTPS host, or the local tunnel address if you ran `gcloud compute ssh … -L 11434:localhost:11434`."
  });
  if (localPairingCode()) return;
  // Gentle nudge if they'll need a pairing code for a shared host.
  const set = "Set pairing code";
  const pick = await vscode.window.showInformationMessage(
    "If this host is shared and protected by a 6-digit pairing code, add it so Symposium can connect.",
    set,
    "Not needed"
  );
  if (pick === set) {
    await vscode.commands.executeCommand("workbench.action.openSettings", "symposium.ai.local.pairingCode");
  }
}

/** The starter commands we copy for the GCP flow — kept in sync with deploy/gcp-quickstart.md. */
const GCP_QUICKSTART_COMMANDS = [
  "# 1. Log in and pick the project",
  "gcloud auth login",
  "gcloud config set project visionary-ml-lab",
  "gcloud services enable compute.googleapis.com",
  "",
  "# 2. Create a SPOT T4 GPU VM (stops itself instead of billing forever)",
  "gcloud compute instances create symposium-gpu \\",
  "  --project=visionary-ml-lab --zone=asia-southeast1-b \\",
  "  --provisioning-model=SPOT --instance-termination-action=STOP \\",
  "  --machine-type=n1-standard-4 --accelerator=type=nvidia-tesla-t4,count=1 \\",
  "  --maintenance-policy=TERMINATE \\",
  "  --image-family=common-cu129-ubuntu-2204-nvidia-580 \\",
  "  --image-project=deeplearning-platform-release \\",
  "  --metadata=install-nvidia-driver=True --boot-disk-size=100GB",
  "",
  "# 3. SSH in and install Ollama",
  "gcloud compute ssh symposium-gpu --zone=asia-southeast1-b --project=visionary-ml-lab",
  "#   (on the box)",
  "curl -fsSL https://ollama.com/install.sh | sh",
  "",
  "# 4. Tunnel the model port to your laptop (leave this terminal open)",
  "gcloud compute ssh symposium-gpu --zone=asia-southeast1-b \\",
  "  --project=visionary-ml-lab -- -L 11434:localhost:11434",
  "#   then use  http://127.0.0.1:11434  as your host URL in Symposium",
  "",
  "# 5. STOP the box when done — this is your ₹0 habit",
  "gcloud compute instances stop symposium-gpu --zone=asia-southeast1-b"
].join("\n");

/** Open a doc from the repo's deploy/ folder in an editor tab. */
async function openDeployDoc(fileName: string): Promise<void> {
  const uri = findDeployDoc(fileName);
  if (uri) {
    await vscode.commands.executeCommand("markdown.showPreview", uri).then(undefined, async () => {
      const doc = await vscode.workspace.openTextDocument(uri);
      await vscode.window.showTextDocument(doc);
    });
    return;
  }
  // Not found locally (extension may be installed away from the repo) — link to GitHub.
  void vscode.env.openExternal(
    vscode.Uri.parse(`https://github.com/samaruban0317/symposium/blob/main/deploy/${fileName}`)
  );
}

/** Locate deploy/<fileName> by walking up from the first workspace folder, then
 * falling back to a couple of paths relative to the extension. */
function findDeployDoc(fileName: string): vscode.Uri | undefined {
  const fs = require("fs") as typeof import("fs");
  const path = require("path") as typeof import("path");

  const roots: string[] = [];
  for (const f of vscode.workspace.workspaceFolders ?? []) roots.push(f.uri.fsPath);

  for (const root of roots) {
    // Walk up a few levels looking for deploy/<fileName>.
    let dir = root;
    for (let i = 0; i < 6; i++) {
      const candidate = path.join(dir, "deploy", fileName);
      try {
        if (fs.existsSync(candidate)) return vscode.Uri.file(candidate);
      } catch {
        /* ignore */
      }
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  }
  return undefined;
}

/** After connecting, nudge the user toward the Models marketplace. */
async function offerMarketplace(): Promise<void> {
  const browse = "Browse models";
  const choice = await vscode.window.showInformationMessage(
    "Want to download a model to run on this GPU?",
    browse
  );
  if (choice === browse) {
    await vscode.commands.executeCommand("symposium.openMarketplace").then(undefined, () =>
      vscode.commands.executeCommand("symposium.marketplace.focus")
    );
  }
}

/** GET {url}/api/tags with a short timeout; true if it answers at all. */
async function ping(url: string): Promise<string | false> {
  const clean = url.replace(/\/+$/, "");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 4000);
  try {
    const headers: Record<string, string> = {};
    const code = localPairingCode();
    if (code) headers["x-symposium-code"] = code;
    const res = await fetch(`${clean}/api/tags`, { headers, signal: controller.signal });
    // Any HTTP answer (even 401/403) proves something is listening.
    return res.status < 500 || res.ok ? clean : false;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

/** Persist a setting at Global scope (so it applies across windows). */
async function writeUrl(key: string, value: string): Promise<void> {
  await vscode.workspace
    .getConfiguration(CFG)
    .update(key, value, vscode.ConfigurationTarget.Global);
}

function isValidHostUrl(v: string): boolean {
  const s = (v || "").trim();
  if (!/^https?:\/\//i.test(s)) return false;
  try {
    // eslint-disable-next-line no-new
    new URL(s);
    return true;
  } catch {
    return false;
  }
}
