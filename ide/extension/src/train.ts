import * as vscode from "vscode";
import { rigEndpoints, rigToken } from "./rigUrls";

/**
 * Starts a training run on the rig by POSTing to the trainer's `/runs` endpoint.
 *
 * We deliberately do NOT ship the active file's source for the rig to execute —
 * that would be remote code execution by design. Instead the user picks a model
 * preset + step count and the rig's own trainer service runs it, streaming
 * metrics back to the Engine Tracker.
 */
export async function startRun(): Promise<void> {
  const preset = await vscode.window.showQuickPick(
    [
      { label: "nano", description: "~0.85M params · trains visibly in minutes on CPU" },
      { label: "micro", description: "~2.7M params · more coherent · wants a GPU" }
    ],
    { title: "Symposium: model preset", placeHolder: "Choose a model size to train" }
  );
  if (!preset) return; // cancelled

  const stepsRaw = await vscode.window.showInputBox({
    title: "Symposium: training steps",
    prompt: "How many steps to train?",
    value: "2000",
    validateInput: (v) => {
      const n = Number(v);
      return Number.isInteger(n) && n > 0 ? undefined : "Enter a positive whole number.";
    }
  });
  if (stepsRaw === undefined) return; // cancelled
  const steps = Number(stepsRaw);

  const { runs: runsUrl } = rigEndpoints();
  const token = rigToken();
  const body = JSON.stringify({ preset: preset.label, steps });

  await vscode.window.withProgress(
    {
      location: vscode.ProgressLocation.Notification,
      title: `Symposium: starting a "${preset.label}" run (${steps} steps)…`,
      cancellable: true
    },
    async (_progress, cancelToken) => {
      const controller = new AbortController();
      cancelToken.onCancellationRequested(() => controller.abort());

      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (token) headers["Authorization"] = `Bearer ${token}`;

      try {
        const res = await fetch(runsUrl, { method: "POST", headers, body, signal: controller.signal });

        if (!res.ok) {
          const text = await safeText(res);
          vscode.window.showErrorMessage(
            `Symposium: rig rejected the run (HTTP ${res.status}${text ? ` — ${text}` : ""}).`
          );
          return;
        }

        const id = await runId(res);
        const msg = id ? `Symposium: run ${id} started — watch it in the Engine Tracker.` : "Symposium: run started.";
        const open = "Open Engine Tracker";
        const choice = await vscode.window.showInformationMessage(msg, open);
        if (choice === open) {
          void vscode.commands.executeCommand("symposium.engineTracker.focus");
        }
      } catch (err) {
        if (controller.signal.aborted) {
          vscode.window.showInformationMessage("Symposium: run submission cancelled.");
          return;
        }
        const m = err instanceof Error ? err.message : String(err);
        vscode.window.showErrorMessage(`Symposium: could not reach the rig at ${runsUrl} — ${m}`);
      }
    }
  );
}

async function safeText(res: Response): Promise<string> {
  try {
    const t = (await res.text()).trim();
    return t.length > 200 ? `${t.slice(0, 200)}…` : t;
  } catch {
    return "";
  }
}

async function runId(res: Response): Promise<string | undefined> {
  try {
    const data = (await res.json()) as Record<string, unknown>;
    if (typeof data.id === "string") return data.id;
  } catch {
    /* non-fatal */
  }
  return undefined;
}
