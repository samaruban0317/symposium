/**
 * The "Team & Git" WebviewView — Symposium's visualised, beginner-first GitHub.
 *
 * Mirrors the Engine Tracker / Coder split: the extension host owns ALL network
 * and git I/O (via GitService + RelayClient) and posts render-ready data into
 * the webview; the webview only draws and posts back the user's intent.
 *
 * What the user sees:
 *   • the branch they're on,
 *   • one big friendly "💾 Save & Share" button (asks for a message, commits +
 *     pushes if a team home exists),
 *   • a vertical TIMELINE of recent commits (their work history, visualised),
 *   • a "Merge requests" list (members open one; the ADMIN sees Approve/Reject),
 *   • New Room / Join Room (by code) entry points.
 *
 * Webview -> host:
 *   { type:"ready" }
 *   { type:"refresh" }
 *   { type:"save", message }
 *   { type:"newBranch", name }
 *   { type:"createRoom", name, email }
 *   { type:"joinRoom", code, email }
 *   { type:"openMr", title }
 *   { type:"approveMr", id } / { type:"rejectMr", id }
 *
 * Host -> webview:
 *   { type:"state", ... }   // the whole panel snapshot (branch, commits, room…)
 *   { type:"toast", level, text }
 */
import * as vscode from "vscode";
import { renderPanelHtml, panelWebviewOptions } from "../webview";
import type { GitService } from "../../git/gitService";
import {
  RelayClient,
  RelayUnreachable,
  type Member,
  type MergeRequest,
  type Room,
} from "../../collab/relayClient";

export class CollabViewProvider implements vscode.WebviewViewProvider, vscode.Disposable {
  public static readonly viewType = "symposium.collab";

  private view: vscode.WebviewView | undefined;

  /** The room the user is currently in (undefined until they create/join one). */
  private room: Room | undefined;
  /** The current user's identity within the room, if known. */
  private me: Member | undefined;

  constructor(
    private readonly extensionUri: vscode.Uri,
    private readonly relay: RelayClient,
    private readonly git: GitService
  ) {}

  /** The room id the tool runner / other panels can read. */
  currentRoomId(): string | undefined {
    return this.room?.id;
  }

  resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken
  ): void {
    this.view = webviewView;
    webviewView.webview.options = panelWebviewOptions(this.extensionUri);
    webviewView.webview.html = renderPanelHtml(webviewView.webview, this.extensionUri, {
      htmlFile: "collab.html",
      scriptFile: "collab.js",
      styleFile: "collab.css",
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
      case "save":
        void this.doSave(String(msg.message ?? ""));
        break;
      case "newBranch":
        void this.doNewBranch(String(msg.name ?? ""));
        break;
      case "createRoom":
        void this.doCreateRoom(String(msg.name ?? ""), String(msg.email ?? ""));
        break;
      case "joinRoom":
        void this.doJoinRoom(String(msg.code ?? ""), String(msg.email ?? ""));
        break;
      case "openMr":
        void this.doOpenMr(String(msg.title ?? ""));
        break;
      case "approveMr":
        void this.doApproveMr(String(msg.id ?? ""));
        break;
      case "rejectMr":
        void this.doRejectMr(String(msg.id ?? ""));
        break;
    }
  }

  // ---- Actions -----------------------------------------------------------

  private async doSave(message: string): Promise<void> {
    const clean = message.trim() || "Update from Symposium";
    try {
      const res = await this.git.saveAndShare(clean);
      this.toast(res.committed ? "ok" : "info", res.message);
    } catch (e) {
      this.toast("error", "Couldn't save: " + errMsg(e));
    }
    await this.pushState();
  }

  private async doNewBranch(name: string): Promise<void> {
    try {
      await this.git.createBranch(name);
      this.toast("ok", `New branch "${name.trim()}" created — a safe space to try ideas.`);
    } catch (e) {
      this.toast("error", errMsg(e));
    }
    await this.pushState();
  }

  private async doCreateRoom(name: string, email: string): Promise<void> {
    if (!name.trim()) return this.toast("error", "Give your room a name first.");
    try {
      this.room = await this.relay.createRoom(name.trim(), email.trim());
      this.toast("ok", `Room "${this.room.name}" created. Share code ${this.room.joinCode} with your team.`);
    } catch (e) {
      this.toast("error", relayMsg(e, "create room"));
    }
    await this.pushState();
  }

  private async doJoinRoom(code: string, email: string): Promise<void> {
    if (!code.trim()) return this.toast("error", "Enter the room code your teammate shared.");
    try {
      const res = await this.relay.joinRoom(code.trim(), email.trim() || undefined);
      this.room = res.room;
      this.me = res.member;
      this.toast("ok", `Joined "${res.room.name}" as ${res.member.role}.`);
    } catch (e) {
      this.toast("error", relayMsg(e, "join room"));
    }
    await this.pushState();
  }

  private async doOpenMr(title: string): Promise<void> {
    if (!this.room) return this.toast("error", "Create or join a room first.");
    try {
      const branch = await this.git.currentBranch();
      const diffSummary = await this.git.diffSummary();
      await this.relay.createMergeRequest(this.room.id, {
        author: this.me?.email || "me",
        branch,
        title: title.trim() || branch,
        diffSummary,
      });
      this.toast("ok", "Merge request opened — the admin can review it.");
    } catch (e) {
      this.toast("error", relayMsg(e, "open merge request"));
    }
    await this.pushState();
  }

  private async doApproveMr(id: string): Promise<void> {
    try {
      await this.relay.approveMergeRequest(id);
      this.toast("ok", "Approved. Nice work by your teammate!");
    } catch (e) {
      this.toast("error", relayMsg(e, "approve"));
    }
    await this.pushState();
  }

  private async doRejectMr(id: string): Promise<void> {
    try {
      await this.relay.rejectMergeRequest(id);
      this.toast("info", "Sent back with a note.");
    } catch (e) {
      this.toast("error", relayMsg(e, "reject"));
    }
    await this.pushState();
  }

  // ---- State push --------------------------------------------------------

  /** Gather git + room state and hand the whole snapshot to the webview. */
  private async pushState(): Promise<void> {
    if (!this.view) return;

    const isRepo = await this.git.isRepo();
    let branch = "(no project)";
    let branches: string[] = [];
    let commits: Array<{ hash: string; subject: string; author: string; date: string }> = [];
    let hasRemote = false;
    let clean = true;
    let changedCount = 0;

    if (isRepo) {
      try {
        branch = await this.git.currentBranch();
        branches = await this.git.branches();
        commits = await this.git.listCommits(15);
        hasRemote = await this.git.hasRemote();
        const st = await this.git.status();
        clean = st.clean;
        changedCount = st.changed.length;
      } catch {
        /* leave friendly defaults */
      }
    }

    // Room + merge requests (only when the relay is reachable).
    let mergeRequests: MergeRequest[] = [];
    let relayOffline = false;
    if (this.room) {
      try {
        mergeRequests = await this.relay.listMergeRequests(this.room.id);
      } catch (e) {
        if (e instanceof RelayUnreachable) relayOffline = true;
      }
    }

    this.post({
      type: "state",
      isRepo,
      branch,
      branches,
      commits,
      hasRemote,
      clean,
      changedCount,
      // Room summary (no secrets — join code is meant to be shared).
      room: this.room ? { id: this.room.id, name: this.room.name, joinCode: this.room.joinCode } : null,
      myRole: this.me?.role ?? null,
      isAdmin: this.me?.role === "admin" || this.relay.auth.adminToken != null,
      mergeRequests,
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

function errMsg(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** Turn a relay failure into a beginner-friendly line. */
function relayMsg(e: unknown, action: string): string {
  if (e instanceof RelayUnreachable) return `Relay not reachable — couldn't ${action}. Team features are offline right now.`;
  return `Couldn't ${action}: ${errMsg(e)}`;
}
