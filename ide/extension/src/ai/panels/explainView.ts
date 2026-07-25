import * as vscode from "vscode";
import { renderPanelHtml, panelWebviewOptions } from "../webview";
import type { StudioSession, SessionEvent } from "../agent/session";
import { AUDIENCE_LABEL, AUDIENCE_GUIDE, type Audience } from "../agent/vizRunner";

/**
 * The "Explain" WebviewView — a plain-language code & workflow explainer for
 * TOTAL beginners (school kids, non-tech folks). Same host/webview split as the
 * Engine Tracker & Coder panels: the host owns the `StudioSession`, reads the
 * active editor, crafts an audience-appropriate prompt, and streams the answer
 * into the webview; the webview only renders and posts back intent.
 *
 * On `turnDone` the host inspects the full model output for a ```mermaid fenced
 * block and, if present, tells the webview to render it (via the vendored
 * Mermaid UMD build, with a graceful <pre> fallback).
 *
 * Webview -> host:
 *   { type:"ready" }
 *   { type:"explain", scope:"file"|"selection", audience }
 *   { type:"diagram", audience }
 *
 * Host -> webview:
 *   { type:"context", fileName, hasSelection, hasEditor }
 *   { type:"event", event }              // one SessionEvent, forwarded verbatim
 *   { type:"mermaid", code }             // a fenced block detected on turnDone
 *   { type:"error", message }
 *   { type:"busy", busy, mode }          // mode: "explain" | "diagram"
 */
export class ExplainViewProvider implements vscode.WebviewViewProvider, vscode.Disposable {
  public static readonly viewType = "symposium.explain";

  private view: vscode.WebviewView | undefined;
  private turn: AbortController | undefined;
  private readonly disposables: vscode.Disposable[] = [];

  /** Provider used for explanations. Local wins if present. */
  private providerId = "local";

  constructor(
    private readonly extensionUri: vscode.Uri,
    private readonly session: StudioSession
  ) {}

  resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken
  ): void {
    this.view = webviewView;

    webviewView.webview.options = panelWebviewOptions(this.extensionUri);
    webviewView.webview.html = renderPanelHtml(webviewView.webview, this.extensionUri, {
      htmlFile: "explain.html",
      scriptFile: "explain.js",
      styleFile: "explain.css",
      extraScripts: ["vendor/mermaid.min.js"]
    });

    webviewView.webview.onDidReceiveMessage((msg) => this.onMessage(msg));

    // Keep the "what's open" context fresh so the panel's labels are honest.
    this.disposables.push(
      vscode.window.onDidChangeActiveTextEditor(() => this.postContext()),
      vscode.window.onDidChangeTextEditorSelection(() => this.postContext())
    );

    webviewView.onDidDispose(() => this.dispose());

    void this.pickProvider();
  }

  private onMessage(msg: any): void {
    if (!msg || typeof msg.type !== "string") return;
    switch (msg.type) {
      case "ready":
        this.postContext();
        break;
      case "explain":
        void this.explain(msg.scope === "selection" ? "selection" : "file", audienceOf(msg.audience));
        break;
      case "diagram":
        void this.diagram(audienceOf(msg.audience));
        break;
    }
  }

  /**
   * Public entry for the `symposium.explainSelection` command (extension.ts calls
   * this). Reveals the view, then explains the current selection (or whole file
   * when nothing is selected) at the given audience level.
   */
  public async explainActiveEditor(audience: Audience = "student"): Promise<void> {
    await vscode.commands.executeCommand(`${ExplainViewProvider.viewType}.focus`);
    const editor = vscode.window.activeTextEditor;
    const scope: "file" | "selection" =
      editor && editor.selection && !editor.selection.isEmpty ? "selection" : "file";
    await this.explain(scope, audience);
  }

  // ---- explanation turn -------------------------------------------------

  private async explain(scope: "file" | "selection", audience: Audience): Promise<void> {
    const code = this.readCode(scope);
    if (!code) {
      this.post({
        type: "error",
        message:
          scope === "selection"
            ? "Select some code in the editor first, then press “Explain selection”."
            : "Open a file in the editor first, then press “Explain this file”."
      });
      return;
    }
    const prompt = buildExplainPrompt(scope, audience, code);
    await this.runTurn(prompt, "explain", audience);
  }

  private async diagram(audience: Audience): Promise<void> {
    const code = this.readCode("file") ?? this.readCode("selection");
    if (!code) {
      this.post({ type: "error", message: "Open a file in the editor first, then draw its workflow." });
      return;
    }
    const prompt = buildDiagramPrompt(code);
    await this.runTurn(prompt, "diagram", audience);
  }

  private async runTurn(prompt: string, mode: "explain" | "diagram", _audience: Audience): Promise<void> {
    if (this.turn) return; // one at a time
    const ctrl = new AbortController();
    this.turn = ctrl;
    this.post({ type: "busy", busy: true, mode });

    let full = "";
    try {
      await this.session.send(this.providerId, prompt, {
        agentMode: false, // pure explanation — no tools/edits
        planFirst: false,
        signal: ctrl.signal,
        onEvent: (e: SessionEvent) => {
          if (e.kind === "text") full += e.text;
          this.post({ type: "event", event: e });
          if (e.kind === "turnDone") this.emitMermaid(full);
        }
      });
    } catch (err) {
      if (!ctrl.signal.aborted) {
        this.post({ type: "error", message: err instanceof Error ? err.message : String(err) });
      }
    } finally {
      if (this.turn === ctrl) this.turn = undefined;
      this.post({ type: "busy", busy: false, mode });
    }
  }

  /** Pull the first ```mermaid fenced block out of the model output, if any. */
  private emitMermaid(text: string): void {
    const code = extractMermaid(text);
    if (code) this.post({ type: "mermaid", code });
  }

  // ---- editor reads (host owns these) -----------------------------------

  private readCode(scope: "file" | "selection"): CodeCtx | undefined {
    const editor = vscode.window.activeTextEditor;
    if (!editor) return undefined;
    const doc = editor.document;
    if (scope === "selection") {
      const sel = editor.selection;
      if (!sel || sel.isEmpty) return undefined;
      return { language: doc.languageId, name: basename(doc.uri), text: clip(doc.getText(sel)) };
    }
    return { language: doc.languageId, name: basename(doc.uri), text: clip(doc.getText()) };
  }

  private postContext(): void {
    const editor = vscode.window.activeTextEditor;
    this.post({
      type: "context",
      fileName: editor ? basename(editor.document.uri) : null,
      hasSelection: !!editor && !!editor.selection && !editor.selection.isEmpty,
      hasEditor: !!editor
    });
  }

  private async pickProvider(): Promise<void> {
    try {
      const providers = await this.session.listProviders();
      const local = providers.find((p) => p.id === "local" && p.available);
      const any = providers.find((p) => p.available);
      this.providerId = (local ?? any ?? providers[0])?.id ?? "local";
    } catch {
      this.providerId = "local";
    }
  }

  private post(msg: unknown): void {
    void this.view?.webview.postMessage(msg);
  }

  dispose(): void {
    this.turn?.abort();
    this.turn = undefined;
    for (const d of this.disposables.splice(0)) d.dispose();
    this.view = undefined;
  }
}

// ---- prompt building ----------------------------------------------------

interface CodeCtx {
  language: string;
  name: string;
  text: string;
}

function buildExplainPrompt(scope: "file" | "selection", audience: Audience, c: CodeCtx): string {
  const what = scope === "selection" ? "selected code" : `file "${c.name}"`;
  return [
    `You are Astra, a warm, patient teacher. Explain the ${what} in plain words for a ${AUDIENCE_LABEL[audience]}.`,
    AUDIENCE_GUIDE[audience],
    "Start with one sentence: what this code is FOR. Then explain what it does, step by step, in everyday language.",
    "Do not walk through the code line by line and do not paste the code back. No unexplained jargon.",
    "",
    `Language: ${c.language || "unknown"}`,
    "```" + (c.language || "") + "\n" + c.text + "\n```"
  ].join("\n");
}

function buildDiagramPrompt(c: CodeCtx): string {
  return [
    "Draw a simple Mermaid flowchart showing how this code works — its main steps, functions, or the flow of control.",
    "Reply with ONLY one Mermaid code block, nothing before or after it:",
    "```mermaid",
    "flowchart TD",
    "  ... nodes and arrows ...",
    "```",
    "Keep node labels short and beginner-friendly (plain words, no code syntax).",
    "",
    `File: ${c.name} (${c.language || "unknown"})`,
    "```" + (c.language || "") + "\n" + c.text + "\n```"
  ].join("\n");
}

// ---- helpers ------------------------------------------------------------

function audienceOf(v: unknown): Audience {
  return v === "kid" || v === "student" || v === "engineer" ? v : "student";
}

/** Extract the first ```mermaid fenced block's inner code. */
function extractMermaid(text: string): string | undefined {
  const m = /```mermaid\s*\n([\s\S]*?)```/i.exec(text);
  const code = m?.[1]?.trim();
  return code && code.length > 0 ? code : undefined;
}

const MAX_CHARS = 12000;

function clip(text: string): string {
  return text.length <= MAX_CHARS ? text : text.slice(0, MAX_CHARS) + "\n… (truncated — file is large)";
}

function basename(uri: vscode.Uri): string {
  const p = uri.path;
  const i = p.lastIndexOf("/");
  return i >= 0 ? p.slice(i + 1) : p;
}
