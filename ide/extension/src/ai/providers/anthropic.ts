/**
 * AnthropicProvider — bring-your-own-key Claude access via the Messages API.
 *
 * Streams `content_block_delta` text + `input_json_delta` tool arguments over
 * SSE, and maps our ToolSpecs to Anthropic's `tools` shape. The API key is read
 * ONLY from SecretStorage (config.getKey) — never logged, never hardcoded.
 *
 * Model note: the default `claude-sonnet-4-6` is a valid current id; other
 * current ids include `claude-opus-4-8` and `claude-haiku-4-5-20251001`.
 */
import type {
  AiProvider,
  ChatMessage,
  ChatOptions,
  ToolCall,
  ToolSpec
} from "../types";
import type * as vscode from "vscode";
import { cloudModel, getKey } from "../config";
import { readSse, tryParse } from "./sse";

const ENDPOINT = "https://api.anthropic.com/v1/messages";
const API_VERSION = "2023-06-01";
const DEFAULT_MODEL = "claude-sonnet-4-6";

/** Anthropic SSE event shapes (only the fields we read). */
interface SseEvent {
  type: string;
  index?: number;
  content_block?: { type: string; id?: string; name?: string };
  delta?: { type: string; text?: string; partial_json?: string };
}

/** In-progress tool_use block being assembled from streamed deltas. */
interface PendingTool {
  id: string;
  name: string;
  json: string;
}

export class AnthropicProvider implements AiProvider {
  readonly id = "anthropic";
  readonly label = "Anthropic (Claude)";
  readonly needsKey = true;

  constructor(private readonly ctx: vscode.ExtensionContext) {}

  async isAvailable(): Promise<boolean> {
    return !!(await getKey(this.ctx, "anthropic"));
  }

  async chat(messages: ChatMessage[], opts: ChatOptions): Promise<void> {
    const key = await getKey(this.ctx, "anthropic");
    if (!key) throw new Error("No Anthropic API key stored");

    const { system, wire } = splitSystem(messages);
    const body: Record<string, unknown> = {
      model: opts.model ?? cloudModel("anthropic") ?? DEFAULT_MODEL,
      max_tokens: 4096,
      stream: true,
      messages: wire
    };
    if (system) body.system = system;
    if (opts.tools?.length) body.tools = opts.tools.map(toAnthropicTool);

    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        "x-api-key": key,
        "anthropic-version": API_VERSION,
        "content-type": "application/json"
      },
      body: JSON.stringify(body),
      signal: opts.signal
    });
    if (!res.ok) {
      throw new Error(`Anthropic HTTP ${res.status}`);
    }

    await this.consume(res, opts);
  }

  /** Parse the SSE stream into text + toolCall deltas. */
  private async consume(res: Response, opts: ChatOptions): Promise<void> {
    // Map block index -> pending tool_use accumulator.
    const tools = new Map<number, PendingTool>();

    for await (const payload of readSse(res, opts.signal)) {
      const ev = tryParse<SseEvent>(payload);
      if (!ev) continue;

      switch (ev.type) {
        case "content_block_start":
          if (ev.content_block?.type === "tool_use" && ev.index !== undefined) {
            tools.set(ev.index, {
              id: ev.content_block.id ?? `anthropic-${ev.index}`,
              name: ev.content_block.name ?? "",
              json: ""
            });
          }
          break;

        case "content_block_delta":
          if (ev.delta?.type === "text_delta" && ev.delta.text) {
            opts.onDelta({ kind: "text", text: ev.delta.text });
          } else if (ev.delta?.type === "input_json_delta" && ev.index !== undefined) {
            const t = tools.get(ev.index);
            if (t) t.json += ev.delta.partial_json ?? "";
          }
          break;

        case "content_block_stop":
          if (ev.index !== undefined) this.flushTool(tools, ev.index, opts);
          break;

        case "message_stop":
          // Flush any tool block that never got an explicit stop.
          for (const idx of [...tools.keys()]) this.flushTool(tools, idx, opts);
          return;
      }
    }
  }

  /** Emit a completed tool_use block as a toolCall delta, if present. */
  private flushTool(tools: Map<number, PendingTool>, index: number, opts: ChatOptions): void {
    const t = tools.get(index);
    if (!t) return;
    tools.delete(index);
    const args = tryParse<Record<string, unknown>>(t.json || "{}") ?? {};
    const call: ToolCall = { id: t.id, name: t.name, arguments: args };
    opts.onDelta({ kind: "toolCall", call });
  }
}

// --- mapping helpers --------------------------------------------------------

/** Anthropic wants system as a top-level field and user/assistant messages. */
function splitSystem(messages: ChatMessage[]): {
  system: string | undefined;
  wire: { role: "user" | "assistant"; content: string }[];
} {
  const sys: string[] = [];
  const wire: { role: "user" | "assistant"; content: string }[] = [];
  for (const m of messages) {
    if (m.role === "system") {
      sys.push(m.content);
    } else {
      // Tool results ride as user turns; assistant stays assistant.
      wire.push({ role: m.role === "assistant" ? "assistant" : "user", content: m.content });
    }
  }
  return { system: sys.length ? sys.join("\n\n") : undefined, wire };
}

/** Map a ToolSpec to Anthropic's {name, description, input_schema}. */
function toAnthropicTool(spec: ToolSpec) {
  return { name: spec.name, description: spec.description, input_schema: spec.parameters };
}
