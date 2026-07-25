/**
 * Reusable webview scaffolding for Studio panels — extracted from the Engine
 * Tracker's proven CSP/nonce/template pattern so every panel renders the same
 * safe way (strict CSP, nonce'd script, no remote loads; the extension host
 * does all network I/O and pushes data in via postMessage).
 */
import * as vscode from "vscode";

export function makeNonce(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let out = "";
  for (let i = 0; i < 32; i++) out += chars.charAt(Math.floor(Math.random() * chars.length));
  return out;
}

export interface PanelHtmlOpts {
  /** File names under media/, e.g. "coder.html" / "coder.js" / "coder.css". */
  htmlFile: string;
  scriptFile: string;
  styleFile: string;
  /** Extra media files exposed to the webview (e.g. "vendor/mermaid.min.js"). */
  extraScripts?: string[];
}

/**
 * Reads media/<htmlFile> and substitutes the standard placeholders:
 *   %CSP% %NONCE% %SCRIPT_URI% %STYLE_URI%  and  %EXTRA_SCRIPTS%
 * (%EXTRA_SCRIPTS% expands to <script nonce=… src=…></script> tags).
 */
export function renderPanelHtml(
  webview: vscode.Webview,
  extensionUri: vscode.Uri,
  opts: PanelHtmlOpts
): string {
  const mediaUri = vscode.Uri.joinPath(extensionUri, "media");
  const uri = (f: string) => webview.asWebviewUri(vscode.Uri.joinPath(mediaUri, ...f.split("/"))).toString();
  const nonce = makeNonce();

  const csp = [
    `default-src 'none'`,
    `img-src ${webview.cspSource} data:`,
    `style-src ${webview.cspSource} 'unsafe-inline'`,
    `font-src ${webview.cspSource}`,
    `script-src 'nonce-${nonce}'`,
    `connect-src 'none'`
  ].join("; ");

  const extra = (opts.extraScripts ?? [])
    .map((f) => `<script nonce="${nonce}" src="${uri(f)}"></script>`)
    .join("\n");

  const fs = require("fs") as typeof import("fs");
  const htmlPath = vscode.Uri.joinPath(mediaUri, ...opts.htmlFile.split("/")).fsPath;
  const html = fs.readFileSync(htmlPath, "utf8");

  return html
    .replace(/%CSP%/g, csp)
    .replace(/%NONCE%/g, nonce)
    .replace(/%SCRIPT_URI%/g, uri(opts.scriptFile))
    .replace(/%STYLE_URI%/g, uri(opts.styleFile))
    .replace(/%EXTRA_SCRIPTS%/g, extra);
}

/** Panels that want media/ readable set this on webview.options. */
export function panelWebviewOptions(extensionUri: vscode.Uri): vscode.WebviewOptions {
  return {
    enableScripts: true,
    localResourceRoots: [vscode.Uri.joinPath(extensionUri, "media")]
  };
}
