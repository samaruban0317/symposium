/**
 * The seam between panels (UI) and the AI core (brains + tools).
 *
 * Panels depend ONLY on this interface — never on a concrete provider. The core
 * (providers/registry + agent/loop) implements `createStudioSession`. This lets
 * the Vibe-Coding / Explainer panels be built in parallel with the providers.
 */
import type * as vscode from "vscode";
import type { Delta, ProviderInfo } from "../types";
import type { ToolRunner, ToolResult } from "../tools";

/** Everything a panel observes during one agent turn. */
export type SessionEvent =
  | Delta
  | { kind: "toolResult"; name: string; result: ToolResult }
  | {
      /** The loop wants approval before a side-effecting tool runs. */
      kind: "approvalRequest";
      id: string;
      summary: string;
      detail?: string;
    }
  | { kind: "plan"; steps: string[] }
  | { kind: "turnDone" };

export interface SendOptions {
  /** Agent mode = tools enabled; false = plain chat. */
  agentMode: boolean;
  /** Draft a step plan and wait for approval before edits/commands. */
  planFirst: boolean;
  signal: AbortSignal;
  onEvent: (e: SessionEvent) => void;
  /** Called for approvalRequests; resolve true to proceed. */
  onApproval?: (id: string, summary: string, detail?: string) => Promise<boolean>;
}

export interface StudioSession {
  /** Providers available right now (local always; cloud only if key stored). */
  listProviders(): Promise<ProviderInfo[]>;
  /** Register an extra tool runner (git from P3, viz from P2). */
  addToolRunner(runner: ToolRunner): void;
  /** Run one user turn against the chosen provider, streaming via onEvent. */
  send(providerId: string, userText: string, opts: SendOptions): Promise<void>;
  /** Conversation reset. */
  reset(): void;
}

/**
 * The concrete factory `createStudioSession(ctx: vscode.ExtensionContext):
 * StudioSession` is implemented by the AI core and exported from
 * `../agent/loop` (see `agent/loop.ts`). Panels import the TYPE from this file
 * and the factory from `../agent/loop`. Kept out of this file so this module
 * stays types-only (no runtime code, safe to import anywhere).
 */
export type CreateStudioSession = (ctx: vscode.ExtensionContext) => StudioSession;
