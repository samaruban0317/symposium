/**
 * A tiny, beginner-friendly wrapper around real Git.
 *
 * Plain English: this file lets the rest of Symposium ask questions like
 * "what branch am I on?" and "save & share my work" WITHOUT anyone learning
 * git commands. It just runs the normal `git` program under the hood (the same
 * one professionals use), inside the folder the user has open.
 *
 * Why child_process and not a fancy library?  Because `git` is already on
 * almost every dev machine, it adds ZERO new dependencies, and it behaves
 * exactly like the real thing — no surprises. The extension host owns all of
 * this (webviews never touch git directly), matching how the Engine Tracker
 * owns its socket.
 *
 * SAFETY: we NEVER force-push and we only push when the project already has a
 * remote (a GitHub/GitLab home). No remote = we just save locally, which is
 * perfectly fine for a beginner.
 */
import * as vscode from "vscode";
import { execFile } from "child_process";

/** One commit, trimmed down to what the visual timeline needs. */
export interface CommitInfo {
  /** Short hash, e.g. "a1b2c3d". */
  hash: string;
  /** Commit message (first line). */
  subject: string;
  /** Author name. */
  author: string;
  /** ISO-ish date string git gives us. */
  date: string;
}

/** Result of a "Save & Share". `pushed` says whether it also reached the team. */
export interface SaveResult {
  committed: boolean;
  pushed: boolean;
  /** Friendly summary to show the beginner ("Saved 3 files and shared them"). */
  message: string;
}

/** A quick read of what has changed but isn't saved yet. */
export interface StatusInfo {
  branch: string;
  /** Paths with changes (staged or not), relative to the repo root. */
  changed: string[];
  /** True when there is nothing to save. */
  clean: boolean;
}

/**
 * The git wrapper. Create ONE and reuse it; it figures out the working folder
 * from the open workspace each time so it always targets the right project.
 */
export class GitService {
  /**
   * The folder we run git in = the first open workspace folder. Beginners open
   * one project at a time, so this is almost always what they mean.
   */
  private cwd(): string | undefined {
    return vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  }

  /** Run `git <args>` in the workspace and hand back stdout (trimmed). */
  private run(args: string[]): Promise<string> {
    const cwd = this.cwd();
    if (!cwd) {
      return Promise.reject(new Error("Open a folder first — Git needs a project to work in."));
    }
    return new Promise<string>((resolve, reject) => {
      // maxBuffer bumped so a big `git log`/`git status` never truncates.
      execFile("git", args, { cwd, maxBuffer: 8 * 1024 * 1024, windowsHide: true }, (err, stdout, stderr) => {
        if (err) {
          const detail = (stderr || (err as Error).message || "").trim();
          reject(new Error(detail || "git command failed"));
          return;
        }
        resolve(stdout.trim());
      });
    });
  }

  /** True if this folder is actually a git project. */
  async isRepo(): Promise<boolean> {
    try {
      const out = await this.run(["rev-parse", "--is-inside-work-tree"]);
      return out === "true";
    } catch {
      return false;
    }
  }

  /** The branch you're on right now (e.g. "main"). "(no branch yet)" if brand new. */
  async currentBranch(): Promise<string> {
    try {
      const out = await this.run(["rev-parse", "--abbrev-ref", "HEAD"]);
      // A fresh repo with no commits reports "HEAD"; make that friendly.
      return out === "HEAD" || !out ? "(no branch yet)" : out;
    } catch {
      return "(no branch yet)";
    }
  }

  /** What has changed since your last save. Uses porcelain so it's easy to parse. */
  async status(): Promise<StatusInfo> {
    const branch = await this.currentBranch();
    const out = await this.run(["status", "--porcelain"]);
    const changed = out
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.length > 0)
      // porcelain lines look like "XY path"; take everything after the 2 flag cols.
      .map((l) => l.slice(2).trim())
      // A rename shows "old -> new"; keep the new name.
      .map((p) => (p.includes(" -> ") ? p.split(" -> ")[1] : p));
    return { branch, changed, clean: changed.length === 0 };
  }

  /** All local branches, current one first. */
  async branches(): Promise<string[]> {
    const out = await this.run(["branch", "--format=%(refname:short)"]);
    const list = out.split("\n").map((b) => b.trim()).filter(Boolean);
    const current = await this.currentBranch();
    // Put the branch you're on at the top so the UI can highlight it.
    return [current, ...list.filter((b) => b !== current)];
  }

  /**
   * Save & Share: stage EVERYTHING, commit with the user's message, and push if
   * (and only if) this project has a remote. This is the one button beginners
   * press — no add/commit/push jargon.
   */
  async saveAndShare(message: string): Promise<SaveResult> {
    const clean = (message || "").trim() || "Update from Symposium";

    // Nothing changed? Say so kindly instead of erroring.
    const st = await this.status();
    if (st.clean) {
      return { committed: false, pushed: false, message: "Nothing new to save — you're all caught up." };
    }

    // Stage every change (new, edited, deleted).
    await this.run(["add", "-A"]);
    // Commit. If git complains "nothing to commit" (race), treat as no-op.
    try {
      await this.run(["commit", "-m", clean]);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (/nothing to commit/i.test(msg)) {
        return { committed: false, pushed: false, message: "Nothing new to save — you're all caught up." };
      }
      throw e;
    }

    // Only push when a team home (remote) exists. No remote = save-local only.
    if (!(await this.hasRemote())) {
      return {
        committed: true,
        pushed: false,
        message: "Saved on your computer. Connect a team home (remote) later to share it.",
      };
    }

    // Push the current branch. NEVER force — force-push can erase others' work.
    const branch = await this.currentBranch();
    try {
      // -u sets the upstream on first push so future saves just work.
      await this.run(["push", "-u", "origin", branch]);
      return { committed: true, pushed: true, message: "Saved and shared with your team." };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      // Saved locally but the share failed (offline, no access, etc.).
      return {
        committed: true,
        pushed: false,
        message: "Saved on your computer, but couldn't share right now: " + firstLine(msg),
      };
    }
  }

  /** True if the project has at least one remote (a place to share to). */
  async hasRemote(): Promise<boolean> {
    try {
      const out = await this.run(["remote"]);
      return out.split("\n").some((r) => r.trim().length > 0);
    } catch {
      return false;
    }
  }

  /**
   * A short, human summary of what changed vs the last save — perfect for a
   * merge-request card. e.g. "3 files changed, 40 insertions(+), 5 deletions(-)".
   */
  async diffSummary(): Promise<string> {
    try {
      // --stat against HEAD shows working-tree changes; fall back to staged.
      const out = await this.run(["diff", "--stat", "HEAD"]);
      const line = lastNonEmptyLine(out);
      if (line) return line;
    } catch {
      /* new repo with no HEAD — fall through */
    }
    // No committed history yet: summarise the staged/working changes instead.
    const st = await this.status();
    if (st.clean) return "no changes yet";
    const n = st.changed.length;
    return `${n} file${n === 1 ? "" : "s"} changed`;
  }

  /** Make a new branch and switch to it (a fresh, safe copy to try ideas on). */
  async createBranch(name: string): Promise<void> {
    const safe = (name || "").trim();
    if (!safe) throw new Error("Please give the new branch a name.");
    // -b creates + switches. Git itself rejects illegal names, which is fine.
    await this.run(["checkout", "-b", safe]);
  }

  /** The last `n` commits, newest first, for the visual timeline. */
  async listCommits(n = 20): Promise<CommitInfo[]> {
    const count = Math.max(1, Math.min(200, Math.floor(n) || 20));
    // Use a rare separator so messages with commas/pipes never break parsing.
    const SEP = "";
    try {
      const out = await this.run([
        "log",
        `-n${count}`,
        `--pretty=format:%h${SEP}%s${SEP}%an${SEP}%ad`,
        "--date=short",
      ]);
      if (!out) return [];
      return out.split("\n").map((line) => {
        const [hash = "", subject = "", author = "", date = ""] = line.split(SEP);
        return { hash, subject, author, date };
      });
    } catch {
      // Brand-new repo with no commits yet.
      return [];
    }
  }
}

/** First line of a possibly-multiline error, so toasts stay short. */
function firstLine(s: string): string {
  return (s || "").split("\n")[0].trim();
}

/** Last non-empty line (git --stat puts the summary on the final line). */
function lastNonEmptyLine(s: string): string {
  const lines = (s || "").split("\n").map((l) => l.trim()).filter(Boolean);
  return lines.length ? lines[lines.length - 1] : "";
}
