/**
 * Model Marketplace client — the extension host's only door to the local model
 * engine (the Symposium host proxy, or a raw Ollama server behind it).
 *
 * Ollama-native contract (the host proxy speaks the same shape):
 *   GET  {ep}/api/tags  -> { models: [{ name, size, details }] }   (installed)
 *   POST {ep}/api/pull  -> NDJSON stream of { status, completed?, total? } lines,
 *                          ending with { status: "success" }.
 *
 * The webview NEVER touches the network — this host object does, then pushes
 * progress in via postMessage (see MarketplaceViewProvider).
 *
 * Auth headers, when configured:
 *   x-symposium-code   — the 6-digit pairing code (any request).
 *   x-symposium-admin  — the admin token; management calls (pull) need it or the
 *                        host answers 403 ("viewer-only for you").
 */
import * as vscode from "vscode";
import { localEndpoints, localPairingCode } from "../ai/config";

/** One installed model, as reported by GET /api/tags. */
export interface InstalledModel {
  name: string;
  size?: number; // bytes on disk
  details?: { family?: string; parameter_size?: string; quantization_level?: string };
}

/** One recommended, pullable model from the curated catalog. */
export interface CatalogModel {
  name: string; // exact Ollama pull name, e.g. "qwen2.5-coder:1.5b"
  label: string; // friendly display name
  size: string; // rough human download size, e.g. "~1.0 GB"
  goodFor: string; // one-line "good for …"
  description: string; // a sentence of context
}

/** A single progress tick parsed from the NDJSON pull stream. */
export interface PullProgress {
  status: string;
  completed?: number;
  total?: number;
  /** Derived 0–100 (undefined until the host reports a total). */
  percent?: number;
}

/**
 * A small, opinionated catalog of models worth recommending to ML/AI trainers.
 * Sizes are approximate download footprints for the default quant. This is just
 * a starter menu — the "pull any model by name" field covers everything else.
 */
export const CURATED_CATALOG: CatalogModel[] = [
  {
    name: "qwen2.5-coder:1.5b",
    label: "Qwen2.5 Coder 1.5B",
    size: "~1.0 GB",
    goodFor: "Tiny, fast code assistant",
    description: "A lightweight coding model that runs on almost any laptop — great first pull."
  },
  {
    name: "qwen2.5-coder:7b",
    label: "Qwen2.5 Coder 7B",
    size: "~4.7 GB",
    goodFor: "Serious local coding",
    description: "Much stronger code reasoning; wants ~8 GB VRAM or a patient CPU."
  },
  {
    name: "llama3.2:3b",
    label: "Llama 3.2 3B",
    size: "~2.0 GB",
    goodFor: "General chat & writing",
    description: "A well-rounded small general model — a solid everyday default."
  },
  {
    name: "llama3.1:8b",
    label: "Llama 3.1 8B",
    size: "~4.7 GB",
    goodFor: "Higher-quality general use",
    description: "Noticeably smarter general model; comfortable on a T4/L4 GPU."
  },
  {
    name: "phi3.5:3.8b",
    label: "Phi-3.5 Mini",
    size: "~2.2 GB",
    goodFor: "Reasoning on modest hardware",
    description: "Microsoft's compact reasoning model — strong for its size."
  },
  {
    name: "gemma2:2b",
    label: "Gemma 2 2B",
    size: "~1.6 GB",
    goodFor: "Very small, snappy general",
    description: "Google's tiny Gemma — quick replies, low memory."
  },
  {
    name: "mistral:7b",
    label: "Mistral 7B",
    size: "~4.1 GB",
    goodFor: "Balanced general workhorse",
    description: "A popular, dependable 7B for chat and drafting."
  },
  {
    name: "nomic-embed-text",
    label: "Nomic Embed Text",
    size: "~0.3 GB",
    goodFor: "Embeddings / RAG",
    description: "A small embedding model for building search & retrieval over your docs."
  }
];

/** Settings key for the (optional) host admin token — read directly so this file
 * stays self-contained and does not depend on config.ts changes. */
function adminToken(): string | undefined {
  return vscode.workspace.getConfiguration("symposium").get<string>("ai.local.adminToken") || undefined;
}

/** Thrown when the host accepts you as a viewer but refuses a management call. */
export class ViewerOnlyError extends Error {
  constructor() {
    super("This host is viewer-only for you — pulling models needs the admin token.");
    this.name = "ViewerOnlyError";
  }
}

export interface MarketplaceListResult {
  models: InstalledModel[];
  /** The endpoint we successfully reached (for display). */
  endpoint: string;
}

export class MarketplaceClient {
  /** The endpoints to try, primary (host proxy) first, then fallback (raw Ollama). */
  private endpoints(): string[] {
    const { primary, fallback } = localEndpoints();
    return primary === fallback ? [primary] : [primary, fallback];
  }

  private headers(includeAdmin: boolean): Record<string, string> {
    const h: Record<string, string> = { "Content-Type": "application/json" };
    const code = localPairingCode();
    if (code) h["x-symposium-code"] = code;
    if (includeAdmin) {
      const admin = adminToken();
      if (admin) h["x-symposium-admin"] = admin;
    }
    return h;
  }

  /** The curated recommendations (static; no network). */
  catalog(): CatalogModel[] {
    return CURATED_CATALOG;
  }

  /**
   * List installed models. Tries the primary endpoint, then the fallback.
   * Throws the last error if every endpoint fails.
   */
  async listInstalled(signal?: AbortSignal): Promise<MarketplaceListResult> {
    let lastErr: unknown;
    for (const ep of this.endpoints()) {
      try {
        const res = await fetch(`${ep}/api/tags`, { headers: this.headers(false), signal });
        if (!res.ok) {
          lastErr = new Error(`HTTP ${res.status} from ${ep}/api/tags`);
          continue;
        }
        const data = (await res.json()) as { models?: InstalledModel[] };
        return { models: Array.isArray(data.models) ? data.models : [], endpoint: ep };
      } catch (err) {
        lastErr = err;
      }
    }
    throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
  }

  /**
   * Pull a model, invoking `onProgress` for each NDJSON line the host streams.
   * Resolves when the stream ends (status "success"); rejects on transport
   * error, a non-OK response, or a 403 (surfaced as {@link ViewerOnlyError}).
   *
   * Only the primary (host proxy) endpoint is used for pulls — management calls
   * are auth-gated and belong to the host, not a bare fallback Ollama.
   */
  async pull(
    name: string,
    onProgress: (p: PullProgress) => void,
    signal?: AbortSignal
  ): Promise<void> {
    const { primary } = localEndpoints();
    const res = await fetch(`${primary}/api/pull`, {
      method: "POST",
      headers: this.headers(true),
      body: JSON.stringify({ name, stream: true }),
      signal
    });

    if (res.status === 403) throw new ViewerOnlyError();
    if (!res.ok) {
      const text = await safeText(res);
      throw new Error(`Pull failed (HTTP ${res.status}${text ? ` — ${text}` : ""}).`);
    }
    if (!res.body) throw new Error("The host returned no progress stream.");

    // Parse the NDJSON body line-by-line off the byte stream.
    const reader = (res.body as ReadableStream<Uint8Array>).getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    // eslint-disable-next-line no-constant-condition
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      let nl = buffer.indexOf("\n");
      while (nl !== -1) {
        const line = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        emitLine(line, onProgress);
        nl = buffer.indexOf("\n");
      }
    }
    // Flush any trailing partial line.
    emitLine(buffer.trim(), onProgress);
  }
}

/** Parse one NDJSON line into a PullProgress and hand it to the callback. */
function emitLine(line: string, onProgress: (p: PullProgress) => void): void {
  if (!line) return;
  let obj: { status?: string; completed?: number; total?: number; error?: string };
  try {
    obj = JSON.parse(line);
  } catch {
    return; // ignore non-JSON noise
  }
  if (obj.error) throw new Error(obj.error);
  const status = typeof obj.status === "string" ? obj.status : "";
  const completed = typeof obj.completed === "number" ? obj.completed : undefined;
  const total = typeof obj.total === "number" && obj.total > 0 ? obj.total : undefined;
  const percent =
    completed !== undefined && total !== undefined
      ? Math.max(0, Math.min(100, (completed / total) * 100))
      : undefined;
  onProgress({ status, completed, total, percent });
}

async function safeText(res: Response): Promise<string> {
  try {
    const t = (await res.text()).trim();
    return t.length > 200 ? `${t.slice(0, 200)}…` : t;
  } catch {
    return "";
  }
}
