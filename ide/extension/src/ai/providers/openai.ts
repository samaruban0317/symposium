/**
 * OpenAiProvider — bring-your-own-key OpenAI Chat Completions access.
 *
 * OpenAI-compatible SSE (same wire shape as the local host): text arrives on
 * `choices[0].delta.content`, native tool calls on `choices[0].delta.tool_calls`
 * (assembled incrementally across chunks by index). Key read ONLY from
 * SecretStorage.
 */
import type {
  AiProvider,
  ChatMessage,
  ChatOptions,
  Role,
  ToolCall,
  ToolSpec
} from "../types";
import type * as vscode from "vscode";
import { cloudModel, getKey } from "../config";
import { readSse, tryParse } from "./sse";

const ENDPOINT = "https://api.openai.com/v1/chat/completions";
const DEFAULT_MODEL = "gpt-4o-mini";

/** OpenAI streamed chunk shape (only the fields we read). */
interface ChatChunk {
  choices?: {
    delta?: {
      content?: string;
      tool_calls?: {
        index: number;
        id?: string;
        function?: { name?: string; arguments?: string };
      }[];
    };
  }[];
}

/** In-progress tool call assembled from streamed deltas. */
interface PendingTool {
  id: string;
  name: string;
  args: string;
}

export class OpenAiProvider implements AiProvider {
  readonly id = "openai";
  readonly label = "OpenAI";
  readonly needsKey = true;

  constructor(private readonly ctx: vscode.ExtensionContext) {}

  async isAvailable(): Promise<boolean> {
    return !!(await getKey(this.ctx, "openai"));
  }

  async chat(messages: ChatMessage[], opts: ChatOptions): Promise<void> {
    const key = await getKey(this.ctx, "openai");
    if (!key) throw new Error("No OpenAI API key stored");

    const body: Record<string, unknown> = {
      model: opts.model ?? cloudModel("openai") ?? DEFAULT_MODEL,
      stream: true,
      messages: messages.map(toWire)
    };
    if (opts.tools?.length) body.tools = opts.tools.map(toOpenAiTool);

    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        authorization: `Bearer ${key}`,
        "content-type": "application/json"
      },
      body: JSON.stringify(body),
      signal: opts.signal
    });
    if (!res.ok) {
      throw new Error(`OpenAI HTTP ${res.status}`);
    }

    // Assemble tool calls incrementally; emit them when the stream ends.
    const tools = new Map<number, PendingTool>();

    for await (const payload of readSse(res, opts.signal)) {
      const chunk = tryParse<ChatChunk>(payload);
      const delta = chunk?.choices?.[0]?.delta;
      if (!delta) continue;

      if (delta.content) {
        opts.onDelta({ kind: "text", text: delta.content });
      }
      for (const tc of delta.tool_calls ?? []) {
        const t = tools.get(tc.index) ?? { id: "", name: "", args: "" };
        if (tc.id) t.id = tc.id;
        if (tc.function?.name) t.name = tc.function.name;
        if (tc.function?.arguments) t.args += tc.function.arguments;
        tools.set(tc.index, t);
      }
    }

    for (const t of tools.values()) {
      if (!t.name) continue;
      const call: ToolCall = {
        id: t.id || `openai-${t.name}`,
        name: t.name,
        arguments: tryParse<Record<string, unknown>>(t.args || "{}") ?? {}
      };
      opts.onDelta({ kind: "toolCall", call });
    }
  }
}

// --- mapping helpers --------------------------------------------------------

/** One OpenAI-shaped tool_call on an assistant turn. */
interface WireToolCall {
  id: string;
  type: "function";
  function: { name: string; arguments: string };
}

/** OpenAI wire message (superset covering assistant tool_calls + tool results). */
interface WireMessage {
  role: Role;
  content: string;
  tool_call_id?: string;
  tool_calls?: WireToolCall[];
}

/**
 * OpenAI accepts system/user/assistant/tool roles directly. Assistant turns
 * that requested tools must carry a `tool_calls` array, and each `tool` result
 * must reference its call via `tool_call_id` — otherwise the API rejects the
 * orphaned result. We reconstruct both from our neutral ChatMessage shape.
 */
function toWire(m: ChatMessage): WireMessage {
  const wire: WireMessage = { role: m.role, content: m.content };
  if (m.role === "tool" && m.toolCallId) {
    wire.tool_call_id = m.toolCallId;
  }
  if (m.role === "assistant" && m.toolCalls?.length) {
    wire.tool_calls = m.toolCalls.map((c) => ({
      id: c.id,
      type: "function",
      function: { name: c.name, arguments: JSON.stringify(c.arguments) }
    }));
  }
  return wire;
}

/** Map a ToolSpec to OpenAI's {type:"function", function:{...}}. */
function toOpenAiTool(spec: ToolSpec) {
  return {
    type: "function" as const,
    function: { name: spec.name, description: spec.description, parameters: spec.parameters }
  };
}
