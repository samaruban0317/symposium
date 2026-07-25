/**
 * The "Admin" WebviewView — a WiFi-router-style control page for a room.
 *
 * Think of your home router's admin page: a list of devices, and for each one a
 * few dials (allowed / blocked, speed limit). This is the same idea for a team:
 * a roster where the admin sets, LIVE, each member's role (admin | committer |
 * viewer), AI-credits/day, and commits/day — plus live usage stats. It mirrors
 * the Dart host server's control plane (POST /v1/host/limits + GET
 * /v1/host/stats) exactly; here the relay stores it in Supabase `ide_members`.
 *
 * Only a room ADMIN can use this: every change carries the `x-symposium-admin`
 * token (held by RelayClient, never logged, never shown). Non-admins see a
 * gentle "admins only" state.
 *
 * Webview -> host:
 *   { type:"ready" } / { type:"refresh" }
 *   { type:"signIn", token }                 // paste/receive an admin token
 *   { type:"setRole", email, role }
 *   { type:"setCredits", email, aiCreditsPerDay, commitsPerDay }
 *
 * Host -> webview:
 *   { type:"state", isAdmin, room, roster, stats, relayOffline }
 *   { type:"toast", level, text }
 */
import * as vscode from "vscode";
import { renderPanelHtml, panelWebviewOptions } from "../webview";
import {
  RelayClient,
  RelayUnreachable,
  type Member,
  type RoomStats,
} from "../../collab/relayClient";

export class AdminViewProvider implements vscode.WebviewViewProvider, vscode.Disposable {
  public static readonly viewType = "symposium.admin";

  private view: vscode.WebviewView | undefined;

  constructor(
    private readonly extensionUri: vscode.Uri,
    private readonly relay: RelayClient,
    /** The room this admin page controls (shared with CollabView). */
    private readonly roomId: () => string | undefined
  ) {}

  resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken
  ): void {
    this.view = webviewView;
    webviewView.webview.options = panelWebviewOptions(this.extensionUri);
    webviewView.webview.html = renderPanelHtml(webviewView.webview, this.extensionUri, {
      htmlFile: "admin.html",
      scriptFile: "admin.js",
      styleFile: "admin.css",
    });
    webviewView.webview.onDidReceiveMessage((msg) => this.onMessage(msg));
    webviewView.onDidDispose(() => {
      this.view = undefined;
    });
  }

  private onMessage(msg: any): void {
    if (!msg || typeof msg.type !== "string") return;
    switch (msg.type) {
      case "ready":
      case "refresh":
        void this.pushState();
        break;
      case "signIn":
        // Store the admin token in memory only (never logged, never persisted here).
        this.relay.setAuth({ adminToken: String(msg.token ?? "").trim() || undefined });
        this.toast("ok", "Admin token set. You now control this room.");
        void this.pushState();
        break;
      case "setRole":
        void this.doSetRole(String(msg.email ?? ""), String(msg.role ?? ""));
        break;
      case "setCredits":
        void this.doSetCredits(msg);
        break;
    }
  }

  private async doSetRole(email: string, role: string): Promise<void> {
    const roomId = this.roomId();
    if (!roomId) return this.toast("error", "No room selected yet.");
    if (role !== "admin" && role !== "committer" && role !== "viewer") return;
    try {
      await this.relay.setMemberRole(roomId, email, role);
      this.toast("ok", `${email} is now a ${role}.`);
    } catch (e) {
      this.toast("error", relayMsg(e, "change role"));
    }
    await this.pushState();
  }

  private async doSetCredits(msg: any): Promise<void> {
    const roomId = this.roomId();
    if (!roomId) return this.toast("error", "No room selected yet.");
    const email = String(msg.email ?? "");
    const credits: { aiCreditsPerDay?: number; commitsPerDay?: number } = {};
    if (msg.aiCreditsPerDay !== undefined) credits.aiCreditsPerDay = clampInt(msg.aiCreditsPerDay);
    if (msg.commitsPerDay !== undefined) credits.commitsPerDay = clampInt(msg.commitsPerDay);
    try {
      await this.relay.setMemberCredits(roomId, email, credits);
      this.toast("ok", `Updated ${email}'s daily budget.`);
    } catch (e) {
      this.toast("error", relayMsg(e, "update credits"));
    }
    await this.pushState();
  }

  private async pushState(): Promise<void> {
    if (!this.view) return;
    const roomId = this.roomId();
    const isAdmin = this.relay.auth.adminToken != null;

    let roster: Member[] = [];
    let stats: RoomStats | null = null;
    let relayOffline = false;

    if (roomId && isAdmin) {
      try {
        roster = await this.relay.getRoster(roomId);
      } catch (e) {
        if (e instanceof RelayUnreachable) relayOffline = true;
      }
      try {
        stats = await this.relay.getStats(roomId);
      } catch (e) {
        if (e instanceof RelayUnreachable) relayOffline = true;
      }
    }

    this.post({
      type: "state",
      isAdmin,
      hasRoom: Boolean(roomId),
      roster,
      stats,
      relayOffline,
    });
  }

  private toast(level: "ok" | "info" | "error", text: string): void {
    this.post({ type: "toast", level, text });
  }

  private post(msg: unknown): void {
    void this.view?.webview.postMessage(msg);
  }

  dispose(): void {
    this.view = undefined;
  }
}

/** Keep credit numbers sane (0 = unlimited, matching the Dart host convention). */
function clampInt(v: unknown): number {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.min(n, 100000);
}

function relayMsg(e: unknown, action: string): string {
  if (e instanceof RelayUnreachable) return `Relay not reachable — couldn't ${action}. Team controls are offline.`;
  return `Couldn't ${action}: ${e instanceof Error ? e.message : String(e)}`;
}
