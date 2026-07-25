import * as vscode from "vscode";
import type { ToolRunner, ToolResult } from "../tools";
import type { ToolCall } from "../types";

/**
 * Tool surface for the Explainer panel — handles the "explain" and "visualize"
 * tools from TOOL_SPECS. It does NOT call a model itself: it gathers the current
 * file / selection / workspace context in the extension host and returns a
 * ToolResult whose `content` is an INSTRUCTION for the model to produce either a
 * plain-language explanation or a Mermaid diagram.
 *
 * Two callers use it:
 *   - The Explain panel builds prompts directly (it owns the editor reads) and
 *     talks to the session; it does not strictly need this runner.
 *   - The Coder panel's agent loop CAN call `explain` / `visualize` as tools —
 *     this runner answers those calls with grounded context + instructions so
 *     the model then produces the explanation/diagram in its next turn.
 *
 * Read-only and side-effect-free: it never edits, so it ignores `approve`.
 */
export class VizToolRunner implements ToolRunner {
  private static readonly TOOLS = new Set(["explain", "visualize"]);

  handles(name: string): boolean {
    return VizToolRunner.TOOLS.has(name);
  }

  async run(
    call: ToolCall,
    _approve: (summary: string, detail?: string) => Promise<boolean>
  ): Promise<ToolResult> {
    if (call.name === "explain") return this.runExplain(call);
    if (call.name === "visualize") return this.runVisualize(call);
    return { ok: false, content: `vizRunner cannot handle tool "${call.name}".` };
  }

  // ---- explain ----------------------------------------------------------

  private async runExplain(call: ToolCall): Promise<ToolResult> {
    const audience = normalizeAudience(call.arguments?.audience);
    const path = typeof call.arguments?.path === "string" ? call.arguments.path : undefined;

    const ctx = await this.gatherCode(path);
    if (!ctx.ok) return { ok: false, content: ctx.message };

    const instruction = [
      `Explain the following ${ctx.label} in plain language for a ${AUDIENCE_LABEL[audience]}.`,
      AUDIENCE_GUIDE[audience],
      "Do not restate the code line by line — describe what it DOES and WHY it matters.",
      "",
      `--- ${ctx.label} ---`,
      fence(ctx.language, ctx.code)
    ].join("\n");

    return {
      ok: true,
      content: instruction,
      display: `Explaining ${ctx.label} for a ${AUDIENCE_LABEL[audience]}.`
    };
  }

  // ---- visualize --------------------------------------------------------

  private async runVisualize(call: ToolCall): Promise<ToolResult> {
    const kind = normalizeKind(call.arguments?.kind);
    const target =
      typeof call.arguments?.target === "string" ? call.arguments.target : undefined;

    const ctx = await this.gatherCode(target && target !== "workspace" ? target : undefined);
    if (!ctx.ok) return { ok: false, content: ctx.message };

    const instruction = [
      `Draw a Mermaid ${kind} showing how the parts of this ${ctx.label} relate`,
      `(functions, files, steps, or the flow of control).`,
      "Reply with ONLY one Mermaid code block and nothing else:",
      "```mermaid",
      `${kind === "flowchart" ? "flowchart TD" : kind}`,
      "  ... your diagram ...",
      "```",
      "Keep node labels short and beginner-friendly.",
      "",
      `--- ${ctx.label} ---`,
      fence(ctx.language, ctx.code)
    ].join("\n");

    return {
      ok: true,
      content: instruction,
      display: `Drawing a ${kind} of ${ctx.label}.`
    };
  }

  // ---- context gathering ------------------------------------------------

  /**
   * Resolve code to explain/visualize. When `path` is given, read that workspace
   * file; otherwise use the active editor (its selection if any, else whole
   * document). Caps very large inputs so a single tool call can't blow the
   * context budget.
   */
  private async gatherCode(
    path: string | undefined
  ): Promise<
    | { ok: true; label: string; language: string; code: string }
    | { ok: false; message: string }
  > {
    if (path) {
      const uri = resolveWorkspaceUri(path);
      if (!uri) return { ok: false, message: `No workspace folder to resolve "${path}".` };
      try {
        const doc = await vscode.workspace.openTextDocument(uri);
        return {
          ok: true,
          label: `file "${path}"`,
          language: doc.languageId,
          code: clip(doc.getText())
        };
      } catch {
        return { ok: false, message: `Could not read file "${path}".` };
      }
    }

    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      return { ok: false, message: "No file is open. Open a file, then try again." };
    }
    const doc = editor.document;
    const sel = editor.selection;
    if (sel && !sel.isEmpty) {
      return {
        ok: true,
        label: "selected code",
        language: doc.languageId,
        code: clip(doc.getText(sel))
      };
    }
    return {
      ok: true,
      label: `file "${basename(doc.uri)}"`,
      language: doc.languageId,
      code: clip(doc.getText())
    };
  }
}

// ---- shared audience copy (also used by the panel) ----------------------

export type Audience = "kid" | "student" | "engineer";

export const AUDIENCE_LABEL: Record<Audience, string> = {
  kid: "curious 10-year-old (no coding background)",
  student: "beginner student learning to code",
  engineer: "working software engineer"
};

export const AUDIENCE_GUIDE: Record<Audience, string> = {
  kid: "Use everyday words and simple analogies (toys, recipes, games). No jargon. Short, warm, encouraging sentences. If you must name a tech word, explain it in the same breath.",
  student: "Friendly and clear. Introduce the key terms but define them simply. Use small concrete examples. Assume they know almost nothing yet.",
  engineer: "Concise and technical. Assume fluency. Focus on design, data flow, edge cases, and trade-offs. Skip the basics."
};

function normalizeAudience(v: unknown): Audience {
  return v === "kid" || v === "student" || v === "engineer" ? v : "student";
}

function normalizeKind(v: unknown): "flowchart" | "sequence" | "class" {
  return v === "sequence" || v === "class" ? v : "flowchart";
}

const MAX_CHARS = 12000;

function clip(code: string): string {
  if (code.length <= MAX_CHARS) return code;
  return code.slice(0, MAX_CHARS) + "\n… (truncated — file is large)";
}

function fence(lang: string, code: string): string {
  return "```" + (lang || "") + "\n" + code + "\n```";
}

function basename(uri: vscode.Uri): string {
  const p = uri.path;
  const i = p.lastIndexOf("/");
  return i >= 0 ? p.slice(i + 1) : p;
}

function resolveWorkspaceUri(rel: string): vscode.Uri | undefined {
  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length === 0) return undefined;
  return vscode.Uri.joinPath(folders[0].uri, ...rel.split(/[\\/]/));
}
