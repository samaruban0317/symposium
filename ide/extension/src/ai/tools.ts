/**
 * The agent's tool schema — the capabilities every Studio brain "knows about".
 *
 * This same list is the fine-tune target for our own agentic model (P5): we
 * teach a small local model to emit these tool calls, so it understands
 * Symposium's editor/git/visualisation powers out of the box.
 *
 * SAFETY: `apply_edit` and `run_command` are side-effecting. The agent loop
 * MUST get explicit per-step user approval before executing those (see
 * `agent/loop.ts`); tools here only declare the schema, they do not run.
 */
import type { ToolSpec, ToolCall } from "./types";

export const TOOL_SPECS: ToolSpec[] = [
  {
    name: "read_file",
    description: "Read a text file from the workspace. Use before editing.",
    parameters: {
      type: "object",
      properties: { path: { type: "string", description: "Workspace-relative path" } },
      required: ["path"]
    }
  },
  {
    name: "list_files",
    description: "List files under a workspace-relative directory (shallow).",
    parameters: {
      type: "object",
      properties: { dir: { type: "string", description: "Workspace-relative dir, '' for root" } },
      required: ["dir"]
    }
  },
  {
    name: "apply_edit",
    description:
      "Propose a full-file replacement. Returns a diff the user must APPROVE before it is written. Read the file first.",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string" },
        content: { type: "string", description: "The complete new file contents" },
        why: { type: "string", description: "One line: what this change does" }
      },
      required: ["path", "content"]
    }
  },
  {
    name: "run_command",
    description:
      "Run a shell command in the workspace terminal. Requires user approval. Use for installs, builds, tests.",
    parameters: {
      type: "object",
      properties: { command: { type: "string" }, why: { type: "string" } },
      required: ["command"]
    }
  },
  {
    name: "git_save",
    description: "Beginner-friendly commit ('Save & Share'): stage all + commit with a message.",
    parameters: {
      type: "object",
      properties: { message: { type: "string" } },
      required: ["message"]
    }
  },
  {
    name: "explain",
    description:
      "Explain a file or the current selection in plain language at an audience level (kid|student|engineer).",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string" },
        audience: { type: "string", enum: ["kid", "student", "engineer"] }
      }
    }
  },
  {
    name: "visualize",
    description:
      "Produce a Mermaid diagram (flowchart|sequence|class) of how code/files relate, for the Explainer panel.",
    parameters: {
      type: "object",
      properties: {
        target: { type: "string", description: "file path or 'workspace'" },
        kind: { type: "string", enum: ["flowchart", "sequence", "class"] }
      }
    }
  }
];

/** Result of executing one tool call. `display` is optional UI-facing text. */
export interface ToolResult {
  ok: boolean;
  content: string;
  display?: string;
  /** For apply_edit: the unified diff to show for approval. */
  diff?: string;
}

/**
 * Executes tool calls in the extension host. Implemented by the agent layer
 * (P1) and extended by git (P3) / explain+viz (P2). Panels register their
 * handlers so the loop stays decoupled from any one feature.
 */
export interface ToolRunner {
  /** Whether this runner handles the given tool name. */
  handles(name: string): boolean;
  /**
   * Run a tool. Side-effecting tools receive `approve` and must call it (and
   * get `true`) before acting. `approve` surfaces a modal/diff to the user.
   */
  run(call: ToolCall, approve: (summary: string, detail?: string) => Promise<boolean>): Promise<ToolResult>;
}
