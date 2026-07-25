/**
 * GeminiProvider — bring-your-own-key Google Gemini access.
 *
 * Streams `candidates[].content.parts[].text` over SSE
 * (`?alt=sse&key=<key>`). Function-calling is supported best-effort: when the
 * model emits a `functionCall` part, we surface it as a toolCall delta; text
 * streaming is always fully supported. Key read ONLY from SecretStorage.
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

const BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const DEFAULT_MODEL = "gemini-1.5-flash";

/** Gemini streamed chunk shape (only the fields we read). */
interface GeminiChunk {
  candidates?: {
    content?: {
      parts?: {
        text?: string;
        functionCall?: { name?: string; args?: Record<string, unknown> };
      }[];
    };
  }[];
}

export class GeminiProvider implements AiProvider {
  readonly id = "gemini";
  readonly label = "Google Gemini";
  readonly needsKey = true;

  constructor(private readonly ctx: vscode.ExtensionContext) {}

  async isAvailable(): Promise<boolean> {
    return !!(await getKey(this.ctx, "gemini"));
  }

  async chat(messages: ChatMessage[], opts: ChatOptions): Promise<void> {
    const key = await getKey(this.ctx, "gemini");
    if (!key) throw new Error("No Gemini API key stored");

    const model = opts.model ?? cloudModel("gemini") ?? DEFAULT_MODEL;
    const { system, contents } = splitContents(messages);

    const body: Record<string, unknown> = { contents };
    if (system) body.systemInstruction = { parts: [{ text: system }] };
    if (opts.tools?.length) {
      body.tools = [{ functionDeclarations: opts.tools.map(toGeminiTool) }];
    }

    // Key goes in the query string per the Gemini REST contract.
    const url = `${BASE}/${encodeURIComponent(model)}:streamGenerateContent?alt=sse&key=${encodeURIComponent(key)}`;
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      signal: opts.signal
    });
    if (!res.ok) {
      throw new Error(`Gemini HTTP ${res.status}`);
    }

    for await (const payload of readSse(res, opts.signal)) {
      const chunk = tryParse<GeminiChunk>(payload);
      const parts = chunk?.candidates?.[0]?.content?.parts;
      if (!parts) continue;
      for (const part of parts) {
        if (part.text) {
          opts.onDelta({ kind: "text", text: part.text });
        } else if (part.functionCall?.name) {
          const call: ToolCall = {
            id: `gemini-${Date.now()}-${part.functionCall.name}`,
            name: part.functionCall.name,
            arguments: part.functionCall.args ?? {}
          };
          opts.onDelta({ kind: "toolCall", call });
        }
      }
    }
  }
}

// --- mapping helpers --------------------------------------------------------

/** Gemini uses role "model" for assistant and a top-level systemInstruction. */
function splitContents(messages: ChatMessage[]): {
  system: string | undefined;
  contents: { role: "user" | "model"; parts: { text: string }[] }[];
} {
  const sys: string[] = [];
  const contents: { role: "user" | "model"; parts: { text: string }[] }[] = [];
  for (const m of messages) {
    if (m.role === "system") {
      sys.push(m.content);
    } else {
      contents.push({
        role: m.role === "assistant" ? "model" : "user",
        parts: [{ text: m.content }]
      });
    }
  }
  return { system: sys.length ? sys.join("\n\n") : undefined, contents };
}

/** Map a ToolSpec to a Gemini functionDeclaration. */
function toGeminiTool(spec: ToolSpec) {
  return { name: spec.name, description: spec.description, parameters: spec.parameters };
}
