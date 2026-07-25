/**
 * EditRunner — the default ToolRunner for filesystem + shell tools.
 *
 * Handles: read_file, list_files (read-only, no approval); apply_edit,
 * run_command (side-effecting, MUST get approval before acting). git_save is a
 * STUB here (git is owned by another layer, P3); explain/visualize are not
 * handled here (owned by the Explainer, P2).
 *
 * The extension host owns all filesystem/terminal I/O (mirrors the Engine
 * Tracker owning the socket) — panels never touch the disk directly.
 */
import * as vscode from "vscode";
import type { ToolCall } from "../types";
import type { ToolResult, ToolRunner } from "../tools";

/** Tool names this runner is responsible for. */
// git_save is intentionally NOT handled here — the real GitToolRunner (P3)
// owns it. Registering that runner shadows nothing because we don't claim it.
const HANDLED = new Set(["read_file", "list_files", "apply_edit", "run_command"]);

export class EditRunner implements ToolRunner {
  /** A reused terminal so repeated run_commands don't spawn a forest of panels. */
  private terminal: vscode.Terminal | undefined;

  handles(name: string): boolean {
    return HANDLED.has(name);
  }

  async run(
    call: ToolCall,
    approve: (summary: string, detail?: string) => Promise<boolean>
  ): Promise<ToolResult> {
    switch (call.name) {
      case "read_file":
        return this.readFile(call);
      case "list_files":
        return this.listFiles(call);
      case "apply_edit":
        return this.applyEdit(call, approve);
      case "run_command":
        return this.runCommand(call, approve);
      default:
        return { ok: false, content: `EditRunner cannot handle "${call.name}"` };
    }
  }

  // --- read-only tools ------------------------------------------------------

  private async readFile(call: ToolCall): Promise<ToolResult> {
    const rel = String(call.arguments.path ?? "");
    const uri = this.resolve(rel);
    if (!uri) return notInWorkspace();
    try {
      const bytes = await vscode.workspace.fs.readFile(uri);
      const text = Buffer.from(bytes).toString("utf8");
      return { ok: true, content: text, display: `Read ${rel}` };
    } catch (err) {
      return { ok: false, content: `Could not read ${rel}: ${errMsg(err)}` };
    }
  }

  private async listFiles(call: ToolCall): Promise<ToolResult> {
    const rel = String(call.arguments.dir ?? "");
    const uri = this.resolve(rel);
    if (!uri) return notInWorkspace();
    try {
      const entries = await vscode.workspace.fs.readDirectory(uri);
      // Suffix directories with "/" so the model can tell them apart.
      const lines = entries
        .map(([name, type]) => (type === vscode.FileType.Directory ? `${name}/` : name))
        .sort();
      return { ok: true, content: lines.join("\n"), display: `Listed ${rel || "."}` };
    } catch (err) {
      return { ok: false, content: `Could not list ${rel}: ${errMsg(err)}` };
    }
  }

  // --- side-effecting tools (require approval) ------------------------------

  private async applyEdit(
    call: ToolCall,
    approve: (summary: string, detail?: string) => Promise<boolean>
  ): Promise<ToolResult> {
    const rel = String(call.arguments.path ?? "");
    const content = String(call.arguments.content ?? "");
    const why = call.arguments.why ? String(call.arguments.why) : "";
    const uri = this.resolve(rel);
    if (!uri) return notInWorkspace();

    // Build a simple unified-ish diff from the current file (if any) → proposed.
    const before = await this.readIfExists(uri);
    const diff = makeDiff(rel, before, content);
    const summary = why ? `Edit ${rel} — ${why}` : `Edit ${rel}`;

    const ok = await approve(summary, diff);
    if (!ok) {
      return { ok: false, content: "Edit rejected by user", diff };
    }

    try {
      // A WorkspaceEdit keeps the change in VS Code's undo history.
      const edit = new vscode.WorkspaceEdit();
      if (before === undefined) {
        edit.createFile(uri, { overwrite: false, ignoreIfExists: true });
      }
      const full = new vscode.Range(0, 0, Number.MAX_SAFE_INTEGER, 0);
      edit.replace(uri, full, content);
      const applied = await vscode.workspace.applyEdit(edit);
      if (!applied) {
        // Fallback to a raw write if the WorkspaceEdit was rejected.
        await vscode.workspace.fs.writeFile(uri, Buffer.from(content, "utf8"));
      }
      return { ok: true, content: `Wrote ${rel}`, display: `Applied edit to ${rel}`, diff };
    } catch (err) {
      return { ok: false, content: `Write failed for ${rel}: ${errMsg(err)}`, diff };
    }
  }

  private async runCommand(
    call: ToolCall,
    approve: (summary: string, detail?: string) => Promise<boolean>
  ): Promise<ToolResult> {
    const command = String(call.arguments.command ?? "").trim();
    const why = call.arguments.why ? String(call.arguments.why) : "";
    if (!command) return { ok: false, content: "No command provided" };

    const summary = why ? `Run: ${command} — ${why}` : `Run: ${command}`;
    const ok = await approve(summary, command);
    if (!ok) {
      return { ok: false, content: "Command rejected by user" };
    }

    // We launch in a terminal; we can't capture output synchronously, so we
    // report that it was launched. Output shows live in the terminal panel.
    const term = this.ensureTerminal();
    term.show(true);
    term.sendText(command, true);
    return {
      ok: true,
      content: `Launched in terminal: ${command}`,
      display: `Running \`${command}\` in the terminal`
    };
  }

  // --- helpers --------------------------------------------------------------

  /** Resolve a workspace-relative path against the first workspace folder. */
  private resolve(rel: string): vscode.Uri | undefined {
    const root = vscode.workspace.workspaceFolders?.[0]?.uri;
    if (!root) return undefined;
    // "" / "." mean the workspace root.
    const clean = rel === "." ? "" : rel.replace(/^\/+/, "");
    return clean ? vscode.Uri.joinPath(root, clean) : root;
  }

  private async readIfExists(uri: vscode.Uri): Promise<string | undefined> {
    try {
      const bytes = await vscode.workspace.fs.readFile(uri);
      return Buffer.from(bytes).toString("utf8");
    } catch {
      return undefined;
    }
  }

  private ensureTerminal(): vscode.Terminal {
    if (!this.terminal || this.terminal.exitStatus !== undefined) {
      this.terminal = vscode.window.createTerminal("Symposium Studio");
    }
    return this.terminal;
  }
}

// --- module helpers ---------------------------------------------------------

function notInWorkspace(): ToolResult {
  return { ok: false, content: "No workspace folder is open" };
}

function errMsg(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

/**
 * Produce a small unified-ish diff for the approval modal. Not a full LCS diff
 * — a readable line-by-line view (context on unchanged runs, +/- on changes)
 * is enough for the user to sanity-check an edit.
 */
function makeDiff(path: string, before: string | undefined, after: string): string {
  const oldLines = before === undefined ? [] : before.split("\n");
  const newLines = after.split("\n");
  const out: string[] = [`--- ${path}`, `+++ ${path}`];

  const max = Math.max(oldLines.length, newLines.length);
  for (let i = 0; i < max; i++) {
    const o = oldLines[i];
    const n = newLines[i];
    if (o === n) {
      if (o !== undefined) out.push(`  ${o}`);
    } else {
      if (o !== undefined) out.push(`- ${o}`);
      if (n !== undefined) out.push(`+ ${n}`);
    }
  }
  return out.join("\n");
}
