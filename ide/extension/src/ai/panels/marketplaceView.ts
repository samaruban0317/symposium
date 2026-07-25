/**
 * Model Marketplace WebviewView ("Models" in the Symposium sidebar).
 *
 * The extension host owns all network I/O (MarketplaceClient); the webview only
 * renders and posts intents. Pull progress is streamed from the host's NDJSON
 * parse into an Engine-Tracker-style progress bar in the webview.
 *
 * Host → webview messages:
 *   { type: "catalog",   models: CatalogModel[] }
 *   { type: "installed", models: {name,size,details}[], endpoint }
 *   { type: "error",     message }
 *   { type: "pull:progress", name, status, percent?, completed?, total? }
 *   { type: "pull:done",     name }
 *   { type: "pull:error",    name, message }
 *
 * Webview → host messages:
 *   { type: "ready" }             — request initial catalog + installed list
 *   { type: "refresh" }           — re-list installed models
 *   { type: "pull", name }        — download a model (curated or free-text)
 *   { type: "connectGpu" }        — run the Connect-a-GPU wizard
 */
import * as vscode from "vscode";
import { panelWebviewOptions, renderPanelHtml } from "../webview";
import { MarketplaceClient, ViewerOnlyError } from "../../gpu/marketplaceClient";

export class MarketplaceViewProvider implements vscode.WebviewViewProvider, vscode.Disposable {
  public static readonly viewType = "symposium.marketplace";

  private view: vscode.WebviewView | undefined;
  /** In-flight pulls, so we can cancel them on dispose. */
  private readonly pulls = new Map<string, AbortController>();

  constructor(
    private readonly extensionUri: vscode.Uri,
    private readonly client: MarketplaceClient = new MarketplaceClient()
  ) {}

  resolveWebviewView(webviewView: vscode.WebviewView): void {
    this.view = webviewView;
    webviewView.webview.options = panelWebviewOptions(this.extensionUri);
    webviewView.webview.html = renderPanelHtml(webviewView.webview, this.extensionUri, {
      htmlFile: "marketplace.html",
      scriptFile: "marketplace.js",
      styleFile: "marketplace.css"
    });

    webviewView.webview.onDidReceiveMessage((msg) => this.onMessage(msg));

    // Re-list when the endpoint / pairing code changes.
    const sub = vscode.workspace.onDidChangeConfiguration((e) => {
      if (
        e.affectsConfiguration("symposium.ai.local.url") ||
        e.affectsConfiguration("symposium.ai.local.fallbackUrl") ||
        e.affectsConfiguration("symposium.ai.local.pairingCode")
      ) {
        void this.postInstalled();
      }
    });

    webviewView.onDidDispose(() => {
      sub.dispose();
      this.cancelAllPulls();
      this.view = undefined;
    });
  }

  private onMessage(msg: unknown): void {
    const m = msg as { type?: string; name?: string };
    if (!m || typeof m.type !== "string") return;
    switch (m.type) {
      case "ready":
        this.post({ type: "catalog", models: this.client.catalog() });
        void this.postInstalled();
        return;
      case "refresh":
        void this.postInstalled();
        return;
      case "pull":
        if (typeof m.name === "string" && m.name.trim()) void this.startPull(m.name.trim());
        return;
      case "connectGpu":
        void vscode.commands.executeCommand("symposium.connectGpu");
        return;
    }
  }

  private async postInstalled(): Promise<void> {
    try {
      const { models, endpoint } = await this.client.listInstalled();
      this.post({ type: "installed", models, endpoint });
    } catch (err) {
      this.post({ type: "error", message: describe(err) });
    }
  }

  private async startPull(name: string): Promise<void> {
    if (this.pulls.has(name)) return; // already downloading
    const controller = new AbortController();
    this.pulls.set(name, controller);
    this.post({ type: "pull:progress", name, status: "starting…", percent: 0 });

    try {
      await this.client.pull(
        name,
        (p) =>
          this.post({
            type: "pull:progress",
            name,
            status: p.status,
            percent: p.percent,
            completed: p.completed,
            total: p.total
          }),
        controller.signal
      );
      this.post({ type: "pull:done", name });
      void this.postInstalled();
    } catch (err) {
      const message =
        err instanceof ViewerOnlyError
          ? err.message
          : controller.signal.aborted
            ? "Download cancelled."
            : describe(err);
      this.post({ type: "pull:error", name, message });
    } finally {
      this.pulls.delete(name);
    }
  }

  private cancelAllPulls(): void {
    for (const c of this.pulls.values()) {
      try {
        c.abort();
      } catch {
        /* ignore */
      }
    }
    this.pulls.clear();
  }

  private post(msg: Record<string, unknown>): void {
    void this.view?.webview.postMessage(msg);
  }

  dispose(): void {
    this.cancelAllPulls();
  }
}

function describe(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}
