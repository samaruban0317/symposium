/**
 * The agent loop — `createStudioSession(ctx)` builds the StudioSession the
 * panels talk to (see `agent/session.ts`). It owns the conversation history,
 * picks a provider from the registry, streams deltas out as SessionEvents, and
 * runs a tool-use loop: when the model emits a toolCall, the matching
 * ToolRunner executes it, the result is fed back, and we loop until the model
 * stops calling tools (capped) or the turn is aborted.
 *
 * planFirst: in agent mode, first ask the model for a short numbered plan,
 * emit it, and require onApproval before any side-effecting tool runs.
 */
import type * as vscode from "vscode";
import type { ChatMessage, Delta, ProviderInfo, ToolCall } from "../types";
import type { ToolResult, ToolRunner } from "../tools";
import { TOOL_SPECS } from "../tools";
import type { SendOptions, StudioSession } from "./session";
import { EditRunner } from "./editRunner";
import { getProvider, providerInfos } from "../providers/registry";

/** Tools that mutate the workspace and therefore need explicit approval. */
const SIDE_EFFECTING = new Set(["apply_edit", "run_command", "git_save"]);

/** Safety cap on tool-call iterations per turn (avoids runaway loops). */
const MAX_ITERATIONS = 6;

/** The factory referenced by session.ts — the AI core's public entry point. */
export function createStudioSession(ctx: vscode.ExtensionContext): StudioSession {
  return new LoopSession(ctx);
}

class LoopSession implements StudioSession {
  private history: ChatMessage[] = [];
  private readonly runners: ToolRunner[] = [new EditRunner()];

  constructor(private readonly ctx: vscode.ExtensionContext) {}

  listProviders(): Promise<ProviderInfo[]> {
    return providerInfos(this.ctx);
  }

  addToolRunner(runner: ToolRunner): void {
    this.runners.push(runner);
  }

  reset(): void {
    this.history = [];
  }

  async send(providerId: string, userText: string, opts: SendOptions): Promise<void> {
    const provider = getProvider(this.ctx, providerId);
    this.history.push({ role: "user", content: userText });

    try {
      if (opts.agentMode && opts.planFirst) {
        const approved = await this.planPhase(provider, opts);
        // If the user rejected the plan, stop before doing anything.
        if (!approved) {
          opts.onEvent({ kind: "turnDone" });
          return;
        }
      }

      await this.runTurn(provider, opts);
    } catch (err) {
      if (!opts.signal.aborted) {
        opts.onEvent({ kind: "status", status: "error", detail: errMsg(err) });
      }
    } finally {
      opts.onEvent({ kind: "turnDone" });
    }
  }

  // --- plan phase -----------------------------------------------------------

  /** Ask the model for a short numbered plan; emit it; require approval. */
  private async planPhase(
    provider: ReturnType<typeof getProvider>,
    opts: SendOptions
  ): Promise<boolean> {
    const planMessages: ChatMessage[] = [
      {
        role: "system",
        content:
          "Produce a SHORT numbered plan (max 6 steps) for the user's request. " +
          "One line per step, no prose, no code. Output only the numbered list."
      },
      ...this.history
    ];

    let planText = "";
    await provider.chat(planMessages, {
      signal: opts.signal,
      onDelta: (d) => {
        if (d.kind === "text") planText += d.text;
      }
    });

    const steps = parseSteps(planText);
    opts.onEvent({ kind: "plan", steps });

    // Require explicit approval to proceed with a side-effecting run.
    if (opts.onApproval) {
      return opts.onApproval("plan", "Proceed with this plan?", planText.trim());
    }
    // No approval callback wired ⇒ treat the plan as informational, continue.
    return true;
  }

  // --- main tool loop -------------------------------------------------------

  private async runTurn(
    provider: ReturnType<typeof getProvider>,
    opts: SendOptions
  ): Promise<void> {
    const tools = opts.agentMode ? TOOL_SPECS : undefined;

    for (let i = 0; i < MAX_ITERATIONS; i++) {
      if (opts.signal.aborted) return;

      opts.onEvent({ kind: "status", status: "streaming" });

      // Collect this turn's assistant text + any tool call it emits.
      let assistantText = "";
      const calls: ToolCall[] = [];

      await provider.chat(this.snapshot(), {
        tools,
        signal: opts.signal,
        onDelta: (d: Delta) => {
          if (d.kind === "text") assistantText += d.text;
          if (d.kind === "toolCall") calls.push(d.call);
          // Forward every delta straight through to the panel.
          opts.onEvent(d);
        }
      });

      // Record the assistant turn (with tool calls, if any) in history.
      this.history.push({
        role: "assistant",
        content: assistantText,
        toolCalls: calls.length ? calls : undefined
      });

      // No tool calls ⇒ the model is done talking. End the turn.
      if (!calls.length) {
        opts.onEvent({ kind: "status", status: "done" });
        return;
      }

      // Execute every requested tool and feed results back into history.
      for (const call of calls) {
        if (opts.signal.aborted) return;
        const result = await this.execTool(call, opts);
        opts.onEvent({ kind: "toolResult", name: call.name, result });
        this.history.push({
          role: "tool",
          content: result.content,
          toolCallId: call.id,
          name: call.name
        });
      }
      // Loop again so the model can react to the tool results.
    }

    // Hit the iteration cap — stop cleanly rather than spinning.
    opts.onEvent({ kind: "status", status: "done", detail: "Reached tool-iteration limit" });
  }

  /** Run one tool via the first runner that handles it, gating side effects. */
  private async execTool(call: ToolCall, opts: SendOptions): Promise<ToolResult> {
    const runner = this.runners.find((r) => r.handles(call.name));
    if (!runner) {
      return { ok: false, content: `No runner handles "${call.name}"` };
    }

    // Approval bridge: surface an approvalRequest event AND resolve via the
    // panel-provided onApproval. Read-only tools pass a no-op that auto-allows.
    const approve = async (summary: string, detail?: string): Promise<boolean> => {
      if (!SIDE_EFFECTING.has(call.name)) return true;
      const id = `${call.name}-${call.id}`;
      opts.onEvent({ kind: "approvalRequest", id, summary, detail });
      if (opts.onApproval) return opts.onApproval(id, summary, detail);
      // No approval channel wired ⇒ deny side effects (fail safe).
      return false;
    };

    try {
      return await runner.run(call, approve);
    } catch (err) {
      return { ok: false, content: `Tool "${call.name}" failed: ${errMsg(err)}` };
    }
  }

  /** A defensive copy of history for the provider (it must not mutate ours). */
  private snapshot(): ChatMessage[] {
    return this.history.map((m) => ({ ...m }));
  }
}

// --- helpers ----------------------------------------------------------------

/** Extract numbered/bulleted plan lines into a clean step array. */
function parseSteps(text: string): string[] {
  return text
    .split("\n")
    .map((l) => l.replace(/^\s*(?:\d+[.)]|[-*])\s*/, "").trim())
    .filter((l) => l.length > 0);
}

function errMsg(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
