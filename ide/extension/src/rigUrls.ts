import * as vscode from "vscode";

const CFG = "symposium";

/**
 * Resolves the one configured base URL (`symposium.rig.url`, e.g.
 * `http://127.0.0.1:8765`) into the concrete endpoints the extension talks to
 * on the `trainer/` FastAPI service. Keeping the derivation in one place means
 * the rest of the extension never hand-builds a rig URL.
 */
export interface RigEndpoints {
  /** `POST <base>/runs` — start a training run. */
  runs: string;
  /** `ws(s)://<host>/runs/latest/metrics` — live event stream for the newest run. */
  latestMetricsWs: string;
}

function base(): string {
  return vscode.workspace
    .getConfiguration(CFG)
    .get<string>("rig.url", "http://127.0.0.1:8765")
    .replace(/\/+$/, ""); // tolerate a trailing slash
}

/** ws:// for http://, wss:// for https:// (any other scheme is left as-is). */
export function toWs(httpUrl: string): string {
  if (httpUrl.startsWith("https://")) return "wss://" + httpUrl.slice("https://".length);
  if (httpUrl.startsWith("http://")) return "ws://" + httpUrl.slice("http://".length);
  return httpUrl;
}

export function rigEndpoints(): RigEndpoints {
  const b = base();
  return {
    runs: `${b}/runs`,
    latestMetricsWs: `${toWs(b)}/runs/latest/metrics`
  };
}

export function rigToken(): string | undefined {
  return vscode.workspace.getConfiguration(CFG).get<string>("rig.token") || undefined;
}
