/**
 * The Git ToolRunner — teaches the AI agent how to "Save & Share" and open a
 * merge request, safely.
 *
 * The agent loop (P1) calls `run()` for any tool it doesn't own. This runner
 * `handles` two tools:
 *   • "git_save"          — stage all + commit (and push if a remote exists).
 *                            Side-effecting, so it MUST get user approval first.
 *   • "git_merge_request" — records a "please approve my work" card on the relay
 *                            so the room admin can approve/reject it.
 *
 * SAFETY: `git_save` never runs without `approve()` returning true — same
 * contract as `apply_edit`/`run_command`. `gitService.saveAndShare` itself
 * never force-pushes and only pushes when a team remote is configured.
 */
import type { ToolCall } from "../ai/types";
import type { ToolRunner, ToolResult } from "../ai/tools";
import type { GitService } from "./gitService";
import type { RelayClient } from "../collab/relayClient";
import { RelayUnreachable } from "../collab/relayClient";

/** Extra tool the agent can emit to open a merge request (beyond git_save). */
export const GIT_MERGE_REQUEST_TOOL = {
  name: "git_merge_request",
  description:
    "Open a 'merge request' (a please-approve-my-work card) for the team admin from your current branch.",
  parameters: {
    type: "object",
    properties: {
      title: { type: "string", description: "Short name for what you built" }
    },
    required: ["title"]
  }
} as const;

/**
 * Handles git tools. Needs a `GitService` (to actually save) and a
 * `RelayClient` (to record merge requests). The `roomId` getter tells us which
 * team to file the merge request against — it may be undefined if the user
 * hasn't joined a room yet, in which case we explain instead of failing hard.
 */
export class GitToolRunner implements ToolRunner {
  constructor(
    private readonly git: GitService,
    private readonly relay: RelayClient,
    /** Which room merge requests go to (undefined until a room is joined). */
    private readonly roomId: () => string | undefined,
    /** Who is opening the merge request (email or display name). */
    private readonly author: () => string
  ) {}

  handles(name: string): boolean {
    return name === "git_save" || name === "git_merge_request";
  }

  async run(
    call: ToolCall,
    approve: (summary: string, detail?: string) => Promise<boolean>
  ): Promise<ToolResult> {
    if (call.name === "git_save") return this.runSave(call, approve);
    if (call.name === "git_merge_request") return this.runMergeRequest(call);
    return { ok: false, content: `git runner can't handle "${call.name}"` };
  }

  /** Save & Share: approval-gated commit (+ push when a remote exists). */
  private async runSave(
    call: ToolCall,
    approve: (summary: string, detail?: string) => Promise<boolean>
  ): Promise<ToolResult> {
    const message = String((call.arguments as { message?: unknown }).message ?? "").trim() || "Update from Symposium";

    // Show the beginner exactly what's about to be saved, then wait for a yes.
    let detail: string;
    try {
      const st = await this.git.status();
      detail = st.clean
        ? "Nothing has changed since your last save."
        : `${st.changed.length} file(s) will be saved:\n` + st.changed.slice(0, 20).map((f) => "  • " + f).join("\n");
    } catch (e) {
      detail = e instanceof Error ? e.message : String(e);
    }

    const ok = await approve(`💾 Save & Share: "${message}"`, detail);
    if (!ok) return { ok: false, content: "Save cancelled — nothing was changed.", display: "Save cancelled." };

    try {
      const res = await this.git.saveAndShare(message);
      return { ok: res.committed, content: res.message, display: res.message };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return { ok: false, content: "Couldn't save: " + msg, display: "Couldn't save: " + msg };
    }
  }

  /** Open a merge request on the relay for the room admin to review. */
  private async runMergeRequest(call: ToolCall): Promise<ToolResult> {
    const title = String((call.arguments as { title?: unknown }).title ?? "").trim() || "My changes";
    const roomId = this.roomId();
    if (!roomId) {
      const m = "Join or create a team room first — then you can open a merge request.";
      return { ok: false, content: m, display: m };
    }

    let branch = "(unknown)";
    let diffSummary = "";
    try {
      branch = await this.git.currentBranch();
      diffSummary = await this.git.diffSummary();
    } catch {
      /* keep defaults — the relay can still record the card */
    }

    try {
      const mr = await this.relay.createMergeRequest(roomId, {
        author: this.author(),
        branch,
        title,
        diffSummary,
      });
      const m = `Merge request opened: "${mr.title}" (${diffSummary || "no summary"}). The admin can approve it.`;
      return { ok: true, content: m, display: m };
    } catch (e) {
      const m =
        e instanceof RelayUnreachable
          ? "Team relay not reachable — your merge request wasn't sent. Try again when you're online."
          : "Couldn't open the merge request: " + (e instanceof Error ? e.message : String(e));
      return { ok: false, content: m, display: m };
    }
  }
}
