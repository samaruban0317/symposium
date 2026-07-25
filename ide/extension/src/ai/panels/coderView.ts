import * as vscode from "vscode";
import { renderPanelHtml, panelWebviewOptions } from "../webview";
import type { StudioSession, SessionEvent } from "../agent/session";
import type { ProviderInfo } from "../types";

/**
 * The "AI Coder" (vibe-coding) WebviewView. Mirrors the Engine Tracker split:
 * the extension host owns the `StudioSession` (providers, tools, network I/O)
 * and posts messages into the webview; the webview only renders and posts back
 * user intent. Exactly one turn is in flight at a time — the host holds its
 * `AbortController` and the `onApproval` promise map so the webview can approve
 * plans and side-effecting tools (diffs / commands) without touching the model.
 *
 * Webview -> host:
 *   { type:"ready" }
 *   { type:"send", text, providerId, agentMode, planFirst }
 *   { type:"approve", id, ok }
 *   { type:"stop" }
 *   { type:"reset" }
 *
 * Host -> webview:
 *   { type:"providers", providers, defaultId }
 *   { type:"event", event }         // one SessionEvent, forwarded verbatim
 *   { type:"error", message }       // a send() rejected
 *   { type:"busy", busy }           // a turn started (true) / ended (false)
 */
export class CoderViewProvider implements vscode.WebviewViewProvider, vscode.Disposable {
  public static readonly viewType = "symposium.coder";

  private view: vscode.WebviewView | undefined;

  /** Aborts the in-flight turn, if any. */
  private turn: AbortController | undefined;
  /** Pending approval resolvers, keyed by request id. */
  private readonly approvals = new Map<string, (ok: boolean) => void>();

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
      htmlFile: "coder.html",
      scriptFile: "coder.js",
      styleFile: "coder.css"
    });

    webviewView.webview.onDidReceiveMessage((msg) => this.onMessage(msg));

    webviewView.onDidDispose(() => {
      this.abortTurn();
      this.view = undefined;
    });
  }

  private onMessage(msg: any): void {
    if (!msg || typeof msg.type !== "string") return;
    switch (msg.type) {
      case "ready":
        void this.sendProviders();
        break;
      case "send":
        void this.runTurn(msg);
        break;
      case "approve":
        this.resolveApproval(msg.id, !!msg.ok);
        break;
      case "stop":
        this.abortTurn();
        break;
      case "reset":
        this.abortTurn();
        this.session.reset();
        break;
    }
  }

  private async sendProviders(): Promise<void> {
    let providers: ProviderInfo[];
    try {
      providers = await this.session.listProviders();
    } catch {
      providers = [];
    }
    // Local first, then the rest in their listed order.
    providers.sort((a, b) => (a.id === "local" ? -1 : b.id === "local" ? 1 : 0));
    // Default: the first available provider (local wins by the sort above).
    const def = providers.find((p) => p.available) ?? providers[0];
    this.post({ type: "providers", providers, defaultId: def?.id });
  }

  private async runTurn(msg: any): Promise<void> {
    if (this.turn) return; // one turn at a time
    const text = typeof msg.text === "string" ? msg.text : "";
    const providerId = typeof msg.providerId === "string" ? msg.providerId : "local";
    if (!text.trim()) return;

    const ctrl = new AbortController();
    this.turn = ctrl;
    this.post({ type: "busy", busy: true });

    try {
      await this.session.send(providerId, text, {
        agentMode: !!msg.agentMode,
        planFirst: !!msg.planFirst,
        signal: ctrl.signal,
        onEvent: (e: SessionEvent) => this.post({ type: "event", event: e }),
        onApproval: (id, summary, detail) => this.awaitApproval(id, summary, detail)
      });
    } catch (err) {
      if (!ctrl.signal.aborted) {
        this.post({ type: "error", message: err instanceof Error ? err.message : String(err) });
      }
    } finally {
      if (this.turn === ctrl) this.turn = undefined;
      // Reject any approvals still pending for this turn.
      this.clearApprovals();
      this.post({ type: "busy", busy: false });
    }
  }

  /**
   * Bridges the loop's `onApproval` promise to the webview: register a resolver,
   * ask the webview to render Approve/Reject, and settle when it answers (or the
   * turn is aborted). Reused for both plan-first and per-tool approvals.
   */
  private awaitApproval(id: string, summary: string, detail?: string): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      this.approvals.set(id, resolve);
      this.post({ type: "event", event: { kind: "approvalRequest", id, summary, detail } });
    });
  }

  private resolveApproval(id: string, ok: boolean): void {
    const resolve = this.approvals.get(id);
    if (resolve) {
      this.approvals.delete(id);
      resolve(ok);
    }
  }

  /** Deny every outstanding approval (turn ended or aborted). */
  private clearApprovals(): void {
    for (const [id, resolve] of this.approvals) {
      this.approvals.delete(id);
      resolve(false);
    }
  }

  private abortTurn(): void {
    this.turn?.abort();
    this.turn = undefined;
    this.clearApprovals();
  }

  private post(msg: unknown): void {
    void this.view?.webview.postMessage(msg);
  }

  dispose(): void {
    this.abortTurn();
    this.view = undefined;
  }
}
