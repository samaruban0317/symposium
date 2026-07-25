/**
 * The Collaboration Relay client — Symposium's "visualised GitHub" back end.
 *
 * Plain English: this talks to a small web service (the "relay") that remembers
 * TEAMS. It knows who is in a room, who is allowed to commit, how many AI
 * credits each person gets, and which "merge requests" (please-approve-my-work
 * cards) are open. The relay stores all of that in Supabase's `ide_*` tables.
 *
 * Auth model — mirrors the Dart host server EXACTLY:
 *   • Admins send   `x-symposium-admin: <token>`  (full control of the room)
 *   • Members send   `x-symposium-code: <joinCode>` (join + read + open MRs)
 * The service-role key stays on the relay (server-only), never here. Those
 * `ide_*` tables are RLS-ON with NO public policies, reached only through this
 * relay — same default-deny pattern as the app's `team_*` tables.
 *
 * The extension host owns this network I/O (webviews never fetch). If the relay
 * isn't running yet, every method degrades gracefully: it throws a friendly
 * `RelayUnreachable` the panels turn into "relay not reachable — team features
 * are offline" instead of a scary stack trace.
 */
import { collabRelayUrl } from "../ai/config";

/** Headers that authenticate a request. Admin token OR a room join code. */
export interface RelayAuth {
  /** Room admin token (from Google login / admin sign-in). Never logged. */
  adminToken?: string;
  /** Room join code a member typed in. */
  joinCode?: string;
}

/** A person in a room, with their role and credits (the "router admin" row). */
export interface Member {
  email: string;
  /** guests (no email login) get a stable id instead. */
  guestId?: string;
  role: "admin" | "committer" | "viewer";
  aiCreditsPerDay: number;
  commitsPerDay: number;
}

/** A room = one team's shared project space. */
export interface Room {
  id: string;
  name: string;
  ownerEmail: string;
  /** The short code members type to join. */
  joinCode: string;
}

/** A "please approve my work" card. */
export interface MergeRequest {
  id: string;
  roomId: string;
  author: string;
  branch: string;
  title: string;
  diffSummary: string;
  status: "open" | "approved" | "rejected";
  createdAt: string;
}

/** A room activity item for the live feed (joined, saved, approved…). */
export interface RoomEvent {
  id: number;
  kind: string;
  payload: Record<string, unknown>;
  createdAt: string;
}

/** Live usage snapshot — mirrors the Dart host's GET /v1/host/stats shape. */
export interface RoomStats {
  inFlight: number;
  todayTotal: number;
  uniqueUsersToday: number;
  /** Per-member usage today, keyed by email. */
  perMember: Record<string, { aiCalls: number; commits: number }>;
}

/** Thrown when the relay can't be reached. Panels show a soft "offline" note. */
export class RelayUnreachable extends Error {
  constructor(message = "relay not reachable") {
    super(message);
    this.name = "RelayUnreachable";
  }
}

/** Thrown when the relay answered but said no (403/400/etc). */
export class RelayError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
    this.name = "RelayError";
  }
}

/**
 * HTTP client for the relay. One instance per extension session. `auth` holds
 * the current admin token / join code and can be updated as the user signs in
 * or joins a room.
 */
export class RelayClient {
  /** Current credentials. Updated by the panels via `setAuth`. */
  auth: RelayAuth = {};

  /** Where the relay lives (config-driven, same default as the local host). */
  private base(): string {
    return collabRelayUrl();
  }

  /** Update the current admin token / join code. */
  setAuth(auth: RelayAuth): void {
    this.auth = { ...this.auth, ...auth };
  }

  /** True once we have SOME way to authenticate (admin token or join code). */
  get isSignedIn(): boolean {
    return Boolean(this.auth.adminToken || this.auth.joinCode);
  }

  // ---- Rooms -------------------------------------------------------------

  /** Create a new room. The caller becomes its admin. Needs an admin token. */
  createRoom(name: string, ownerEmail: string): Promise<Room> {
    return this.req<Room>("POST", "/v1/collab/rooms", { name, ownerEmail });
  }

  /** Join an existing room by its short code. Returns the room + your member row. */
  joinRoom(code: string, email?: string): Promise<{ room: Room; member: Member }> {
    // Use the code we're joining with as auth for THIS call.
    return this.req("POST", `/v1/collab/rooms/join`, { code, email }, { joinCode: code });
  }

  // ---- Roster & credits (the "router admin page") ------------------------

  /** Everyone in the room, with roles + credits. */
  getRoster(roomId: string): Promise<Member[]> {
    return this.req<Member[]>("GET", `/v1/collab/rooms/${enc(roomId)}/roster`);
  }

  /** Admin: change one member's role (admin | committer | viewer). */
  setMemberRole(roomId: string, email: string, role: Member["role"]): Promise<Member> {
    return this.req<Member>("POST", `/v1/collab/rooms/${enc(roomId)}/members/${enc(email)}`, { role });
  }

  /** Admin: set one member's daily AI-credit and commit budgets. */
  setMemberCredits(
    roomId: string,
    email: string,
    credits: { aiCreditsPerDay?: number; commitsPerDay?: number }
  ): Promise<Member> {
    return this.req<Member>("POST", `/v1/collab/rooms/${enc(roomId)}/members/${enc(email)}`, credits);
  }

  /** Live usage numbers for the admin dashboard. */
  getStats(roomId: string): Promise<RoomStats> {
    return this.req<RoomStats>("GET", `/v1/collab/rooms/${enc(roomId)}/stats`);
  }

  // ---- Merge requests ----------------------------------------------------

  /** All merge requests in a room (open ones matter most). */
  listMergeRequests(roomId: string): Promise<MergeRequest[]> {
    return this.req<MergeRequest[]>("GET", `/v1/collab/rooms/${enc(roomId)}/merge-requests`);
  }

  /** A member opens a merge request from their branch. */
  createMergeRequest(
    roomId: string,
    mr: { author: string; branch: string; title: string; diffSummary: string }
  ): Promise<MergeRequest> {
    return this.req<MergeRequest>("POST", `/v1/collab/rooms/${enc(roomId)}/merge-requests`, mr);
  }

  /** Admin: approve a merge request (green light). */
  approveMergeRequest(id: string): Promise<MergeRequest> {
    return this.req<MergeRequest>("POST", `/v1/collab/merge-requests/${enc(id)}/approve`);
  }

  /** Admin: reject a merge request (send it back). */
  rejectMergeRequest(id: string, reason?: string): Promise<MergeRequest> {
    return this.req<MergeRequest>("POST", `/v1/collab/merge-requests/${enc(id)}/reject`, { reason });
  }

  // ---- Activity feed -----------------------------------------------------

  /** Recent room activity (joined / saved / approved …) for the live timeline. */
  getEvents(roomId: string, sinceId = 0): Promise<RoomEvent[]> {
    const q = sinceId > 0 ? `?since=${sinceId}` : "";
    return this.req<RoomEvent[]>("GET", `/v1/collab/rooms/${enc(roomId)}/events${q}`);
  }

  // ---- Transport ---------------------------------------------------------

  /**
   * One HTTP round-trip. Adds the right auth header, parses JSON, and turns any
   * connection failure into a friendly `RelayUnreachable`. `authOverride` lets
   * join use the code it's joining with before it's saved as the session auth.
   */
  private async req<T>(
    method: string,
    path: string,
    body?: unknown,
    authOverride?: RelayAuth
  ): Promise<T> {
    const url = this.base() + path;
    const auth = authOverride ?? this.auth;

    const headers: Record<string, string> = { accept: "application/json" };
    if (body !== undefined) headers["content-type"] = "application/json";
    // Admin token wins if present; otherwise a join code identifies a member.
    // NOTE: never log these headers — the admin token is a secret.
    if (auth.adminToken) headers["x-symposium-admin"] = auth.adminToken;
    else if (auth.joinCode) headers["x-symposium-code"] = auth.joinCode;

    let res: Response;
    try {
      res = await fetch(url, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch {
      // DNS/connection refused/timeout — the relay simply isn't up.
      throw new RelayUnreachable();
    }

    if (!res.ok) {
      let msg = `${res.status}`;
      try {
        const j = (await res.json()) as { error?: string };
        if (j?.error) msg = j.error;
      } catch {
        /* non-JSON error body — keep the status code */
      }
      throw new RelayError(res.status, msg);
    }

    // Some endpoints (approve/reject) may reply 204 with no body.
    if (res.status === 204) return undefined as unknown as T;
    try {
      return (await res.json()) as T;
    } catch {
      return undefined as unknown as T;
    }
  }
}

/** URL-encode a path segment (emails contain '@', ids are uuids). */
function enc(s: string): string {
  return encodeURIComponent(s);
}
