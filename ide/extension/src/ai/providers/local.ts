/**
 * LocalProvider — the default brain. Talks to the Symposium host proxy
 * (127.0.0.1:47475) first, then falls back to a raw Ollama server
 * (127.0.0.1:11434). Both expose an OpenAI-compatible `/v1/chat/completions`
 * SSE endpoint, so one implementation covers both.
 *
 * Local models frequently lack native tool-calling, so when tools are supplied
 * we inject a "emit a fenced ```tool_call``` block" instruction and parse that
 * fence out of the text stream into a `toolCall` delta. Robust by design:
 * malformed fences are ignored and streamed as ordinary text.
 *
 * The extension host owns the socket (mirrors `RigClient`); no webview touches
 * the network. Keys are never involved — local is keyless.
 */
import type {
  AiProvider,
  ChatMessage,
  ChatOptions,
  Delta,
  Role,
  ToolCall,
  ToolSpec
} from "../types";
import { localEndpoints, localPairingCode } from "../config";
import { readSse, tryParse } from "./sse";

/** OpenAI-compatible streaming chunk shape (only the fields we read). */
interface ChatChunk {
  choices?: { delta?: { content?: string } }[];
}

/** `GET /v1/models` response shape. */
interface ModelsResponse {
  data?: { id?: string }[];
}

export class LocalProvider implements AiProvider {
  readonly id: string = "local";
  readonly label: string = "Local (Symposium host / Ollama)";
  readonly needsKey = false;

  /** Fixed model + preamble for subclasses (Symposium's own fine-tune). */
  protected readonly pinnedModel: string | undefined;
  protected readonly preamble: string | undefined;

  constructor(opts?: { id?: string; label?: string; pinnedModel?: string; preamble?: string }) {
    if (opts?.id) this.id = opts.id;
    if (opts?.label) this.label = opts.label;
    this.pinnedModel = opts?.pinnedModel;
    this.preamble = opts?.preamble;
  }

  async isAvailable(): Promise<boolean> {
    // Reachable if either endpoint answers the models list quickly.
    const { primary, fallback } = localEndpoints();
    for (const ep of [primary, fallback]) {
      if (await this.ping(ep)) return true;
    }
    return false;
  }

  async chat(messages: ChatMessage[], opts: ChatOptions): Promise<void> {
    const { primary, fallback } = localEndpoints();
    const model = this.pinnedModel ?? opts.model ?? (await this.firstModel(primary, fallback));
    const body = this.buildBody(messages, opts.tools, model);

    // Try primary (host proxy) then fallback (raw Ollama).
    let lastErr: unknown;
    for (const ep of [primary, fallback]) {
      try {
        await this.stream(ep, body, opts);
        return;
      } catch (err) {
        lastErr = err;
      }
    }
    throw lastErr instanceof Error ? lastErr : new Error("Local model unreachable");
  }

  // --- request building -----------------------------------------------------

  /** Compose the request body, injecting preamble + tool-fallback instruction. */
  private buildBody(messages: ChatMessage[], tools: ToolSpec[] | undefined, model: string) {
    const wire: { role: Role; content: string }[] = [];
    if (this.preamble) {
      wire.push({ role: "system", content: this.preamble });
    }
    if (tools && tools.length) {
      wire.push({ role: "system", content: toolFallbackPrompt(tools) });
    }
    for (const m of messages) {
      // Collapse `tool` results into user context; local chat APIs are plain.
      wire.push({ role: m.role === "tool" ? "user" : m.role, content: m.content });
    }
    return { model, stream: true, messages: wire, temperature: 0.7 };
  }

  private headers(): Record<string, string> {
    const h: Record<string, string> = { "content-type": "application/json" };
    const code = localPairingCode();
    if (code) h["x-symposium-code"] = code;
    return h;
  }

  // --- streaming ------------------------------------------------------------

  private async stream(ep: string, body: unknown, opts: ChatOptions): Promise<void> {
    const res = await fetch(`${ep}/v1/chat/completions`, {
      method: "POST",
      headers: this.headers(),
      body: JSON.stringify(body),
      signal: opts.signal
    });
    if (!res.ok) {
      throw new Error(`Local chat HTTP ${res.status}`);
    }

    const parser = new ToolFenceScanner((d) => opts.onDelta(d));
    const started = Date.now();
    let chunks = 0;
    let lastEmit = 0;

    for await (const payload of readSse(res, opts.signal)) {
      const chunk = tryParse<ChatChunk>(payload);
      const token = chunk?.choices?.[0]?.delta?.content;
      if (!token) continue;
      chunks += 1;
      parser.push(token);

      // Each SSE chunk ≈ one token, so chunks/elapsed ≈ tok/s (mirrors
      // app_state.dart). Emit at most ~every 250ms to avoid UI spam.
      const now = Date.now();
      if (now - lastEmit > 250) {
        const secs = (now - started) / 1000;
        if (secs > 0.2) opts.onDelta({ kind: "tokPerSec", value: chunks / secs });
        lastEmit = now;
      }
    }
    parser.flush();
  }

  // --- model discovery ------------------------------------------------------

  private async firstModel(primary: string, fallback: string): Promise<string> {
    for (const ep of [primary, fallback]) {
      const id = await this.listFirst(ep);
      if (id) return id;
    }
    // Sensible default when nothing is discoverable.
    return "llama3.1";
  }

  private async listFirst(ep: string): Promise<string | undefined> {
    try {
      const res = await fetch(`${ep}/v1/models`, { headers: this.headers() });
      if (!res.ok) return undefined;
      const json = (await res.json()) as ModelsResponse;
      return json.data?.[0]?.id;
    } catch {
      return undefined;
    }
  }

  private async ping(ep: string): Promise<boolean> {
    try {
      const ctl = new AbortController();
      const t = setTimeout(() => ctl.abort(), 1500);
      const res = await fetch(`${ep}/v1/models`, { headers: this.headers(), signal: ctl.signal });
      clearTimeout(t);
      return res.ok;
    } catch {
      return false;
    }
  }
}

// --- local tool-calling fallback --------------------------------------------

/** System instruction teaching a plain local model to emit a tool_call fence. */
export function toolFallbackPrompt(tools: ToolSpec[]): string {
  const lines = tools.map((t) => `- ${t.name}: ${t.description}`);
  return [
    "You can use tools. To call one, output EXACTLY one fenced block:",
    "```tool_call",
    '{"name":"<tool>","arguments":{ ... }}',
    "```",
    "Emit nothing after the closing fence in the same turn. Available tools:",
    ...lines
  ].join("\n");
}

/**
 * Streams text through untouched EXCEPT for ```tool_call ...``` fences, which
 * it buffers, parses, and re-emits as a `toolCall` delta. Written to be robust:
 * an unterminated or malformed fence at flush-time is emitted as plain text.
 */
class ToolFenceScanner {
  private buf = "";
  private inFence = false;
  private fenceBuf = "";
  private static readonly OPEN = "```tool_call";
  private static readonly CLOSE = "```";

  constructor(private readonly emit: (d: Delta) => void) {}

  push(token: string): void {
    if (this.inFence) {
      this.fenceBuf += token;
      this.tryCloseFence();
      return;
    }
    this.buf += token;
    this.scanForOpen();
  }

  private scanForOpen(): void {
    const idx = this.buf.indexOf(ToolFenceScanner.OPEN);
    if (idx < 0) {
      // Keep a small tail in case the opener straddles two tokens.
      const keep = ToolFenceScanner.OPEN.length - 1;
      if (this.buf.length > keep) {
        this.emit({ kind: "text", text: this.buf.slice(0, this.buf.length - keep) });
        this.buf = this.buf.slice(this.buf.length - keep);
      }
      return;
    }
    // Flush text before the fence, then switch into fence-capture mode.
    if (idx > 0) this.emit({ kind: "text", text: this.buf.slice(0, idx) });
    this.buf = "";
    this.inFence = true;
    this.fenceBuf = "";
  }

  private tryCloseFence(): void {
    const end = this.fenceBuf.indexOf(ToolFenceScanner.CLOSE);
    if (end < 0) return;
    const inner = this.fenceBuf.slice(0, end);
    this.inFence = false;
    this.fenceBuf = "";
    this.emitToolCall(inner);
  }

  private emitToolCall(inner: string): void {
    const parsed = tryParse<{ name?: string; arguments?: Record<string, unknown> }>(inner.trim());
    if (parsed?.name) {
      const call: ToolCall = {
        id: `local-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
        name: parsed.name,
        arguments: parsed.arguments ?? {}
      };
      this.emit({ kind: "toolCall", call });
    } else {
      // Malformed → surface as text rather than dropping it silently.
      this.emit({ kind: "text", text: inner });
    }
  }

  flush(): void {
    if (this.inFence) {
      // Unterminated fence — best effort parse, else raw text.
      this.emitToolCall(this.fenceBuf);
      this.fenceBuf = "";
      this.inFence = false;
    }
    if (this.buf) {
      this.emit({ kind: "text", text: this.buf });
      this.buf = "";
    }
  }
}
