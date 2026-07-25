/**
 * Shared AI contracts for Symposium Studio.
 *
 * The extension host owns ALL network I/O (exactly like `RigClient` for the
 * Engine Tracker); webviews only render and `postMessage`. Every model — local
 * Ollama/Symposium host, a bring-your-own cloud key, or our own fine-tuned
 * model — implements the one `AiProvider` interface below, so panels never care
 * which brain is answering.
 */

export type Role = "system" | "user" | "assistant" | "tool";

export interface ChatMessage {
  role: Role;
  content: string;
  /** Present on `assistant` turns that requested tools. */
  toolCalls?: ToolCall[];
  /** Present on `tool` turns: which call this result answers. */
  toolCallId?: string;
  /** Optional tool name on `tool` turns (some providers want it). */
  name?: string;
}

/** JSON-schema-ish description of one tool the model may call. */
export interface ToolSpec {
  name: string;
  description: string;
  /** JSON Schema object for the arguments. */
  parameters: Record<string, unknown>;
}

export interface ToolCall {
  id: string;
  name: string;
  /** Parsed arguments (already JSON.parsed). */
  arguments: Record<string, unknown>;
}

/**
 * Streaming events a provider emits through `onDelta`. Mirrors the Engine
 * Tracker's message style: small, tagged, render-ready.
 */
export type Delta =
  | { kind: "text"; text: string }
  | { kind: "toolCall"; call: ToolCall }
  | { kind: "tokPerSec"; value: number }
  | { kind: "status"; status: "thinking" | "streaming" | "done" | "error"; detail?: string };

export interface ChatOptions {
  /** Tools the model may call this turn. Omit for a plain chat. */
  tools?: ToolSpec[];
  /** Model id override (else the provider's configured default). */
  model?: string;
  /** Cancels the in-flight request. */
  signal?: AbortSignal;
  /** Called for every streamed delta. */
  onDelta: (d: Delta) => void;
}

/**
 * One brain. `id` is stable ("local" | "anthropic" | "gemini" | "openai" |
 * "symposium"); cloud providers set `needsKey` and are hidden by the registry
 * until a key exists in SecretStorage.
 */
export interface AiProvider {
  readonly id: string;
  readonly label: string;
  /** True for cloud providers that require a user-supplied API key. */
  readonly needsKey: boolean;
  /** Whether this provider can be used right now (key present / host reachable). */
  isAvailable(): Promise<boolean>;
  /**
   * Run one streaming chat turn. Resolves when the turn (incl. any tool-call
   * emissions) has finished streaming. Throws on transport/auth errors.
   */
  chat(messages: ChatMessage[], opts: ChatOptions): Promise<void>;
}

/** Minimal info the UI needs to list a provider in a dropdown. */
export interface ProviderInfo {
  id: string;
  label: string;
  available: boolean;
  needsKey: boolean;
}
