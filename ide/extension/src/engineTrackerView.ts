import * as vscode from "vscode";
import { RigClient, RigStatus } from "./rigClient";
import { rigEndpoints, rigToken } from "./rigUrls";
import { metricToFrame, parseEvent } from "./trainerEvents";

/**
 * The "Engine Tracker" WebviewView. The extension host owns the metrics socket
 * (RigClient, connected to the rig's `/runs/latest/metrics` stream) and posts
 * messages into the webview; the webview only renders.
 *
 * The trainer streams `kind`-tagged JSON events; we translate `metric` events
 * into the flat frame the webview expects and surface `status` events as the
 * run's lifecycle (running / finished / stopped / error). `sample` events are
 * left to the Rig logs channel.
 */
export class EngineTrackerViewProvider implements vscode.WebviewViewProvider, vscode.Disposable {
  public static readonly viewType = "symposium.engineTracker";

  private view: vscode.WebviewView | undefined;
  private client: RigClient | undefined;
  private runStatus: string | undefined;

  constructor(private readonly extensionUri: vscode.Uri) {}

  resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken
  ): void {
    this.view = webviewView;
    const mediaUri = vscode.Uri.joinPath(this.extensionUri, "media");

    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [mediaUri]
    };

    webviewView.webview.html = this.getHtml(webviewView.webview);

    // The webview asks for a snapshot once it has booted.
    webviewView.webview.onDidReceiveMessage((msg) => {
      if (msg?.type === "ready") {
        this.postStatus(this.client?.currentStatus ?? "disconnected");
      }
    });

    webviewView.onDidDispose(() => {
      this.client?.dispose();
      this.client = undefined;
      this.view = undefined;
    });

    // React to rig URL / token changes while the view is open.
    const sub = vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration("symposium.rig.url") || e.affectsConfiguration("symposium.rig.token")) {
        this.restartClient();
      }
    });
    webviewView.onDidDispose(() => sub.dispose());

    this.startClient();
  }

  private startClient(): void {
    this.runStatus = undefined;
    this.client = new RigClient({
      url: () => rigEndpoints().latestMetricsWs,
      token: () => rigToken(),
      onStatus: (status: RigStatus, detail?: string) => this.postStatus(status, detail),
      onMessage: (data: string) => this.handleEvent(data)
    });
    this.client.start();
  }

  private restartClient(): void {
    this.client?.stop();
    this.startClient();
  }

  private handleEvent(raw: string): void {
    const ev = parseEvent(raw);
    if (!ev) return;
    if (ev.kind === "metric") {
      this.view?.webview.postMessage({ type: "metric", metric: metricToFrame(ev) });
    } else if (ev.kind === "status" && ev.status) {
      // Fold the run's lifecycle into the status line's detail, keeping the
      // connection state as "live" (we only get events while connected).
      this.runStatus = ev.status;
      this.postStatus("live");
    }
  }

  private postStatus(status: RigStatus, detail?: string): void {
    // Prefer the run's lifecycle as the detail when we have it and we're live.
    const shown = status === "live" && this.runStatus ? `run: ${this.runStatus}` : detail;
    this.view?.webview.postMessage({ type: "status", status, detail: shown });
  }

  dispose(): void {
    this.client?.dispose();
    this.client = undefined;
  }

  private getHtml(webview: vscode.Webview): string {
    const mediaUri = vscode.Uri.joinPath(this.extensionUri, "media");
    const scriptUri = webview.asWebviewUri(vscode.Uri.joinPath(mediaUri, "engineTracker.js"));
    const styleUri = webview.asWebviewUri(vscode.Uri.joinPath(mediaUri, "engineTracker.css"));
    const nonce = makeNonce();

    // Strict CSP: only our nonce'd script, only our stylesheet, no remote loads.
    const csp = [
      `default-src 'none'`,
      `img-src ${webview.cspSource} data:`,
      `style-src ${webview.cspSource}`,
      `script-src 'nonce-${nonce}'`,
      `connect-src 'none'`
    ].join("; ");

    const html = readTemplate(this.extensionUri);
    return html
      .replace(/%CSP%/g, csp)
      .replace(/%NONCE%/g, nonce)
      .replace(/%SCRIPT_URI%/g, scriptUri.toString())
      .replace(/%STYLE_URI%/g, styleUri.toString());
  }
}

function makeNonce(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let out = "";
  for (let i = 0; i < 32; i++) {
    out += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return out;
}

function readTemplate(extensionUri: vscode.Uri): string {
  const fs = require("fs") as typeof import("fs");
  const path = vscode.Uri.joinPath(extensionUri, "media", "engineTracker.html").fsPath;
  return fs.readFileSync(path, "utf8");
}
