# Symposium Collaboration Relay

This folder defines the **relay** — the small web service that powers the
"visualised GitHub" Team/Admin pillar of Symposium Studio.

- The **extension** talks to the relay from `src/collab/relayClient.ts`
  (the extension host owns all network I/O; webviews never fetch).
- The **relay** stores everything in Supabase's `ide_*` tables
  (see [`schema.sql`](./schema.sql)).
- This README is the **contract**: any backend that implements these endpoints
  with this auth model works with the client as-is.

The relay backend is not required to be live for the client to run — the client
degrades gracefully and shows "relay not reachable" when it can't connect.

---

## Where the relay lives

The client reads the base URL from VS Code setting `symposium.collab.relayUrl`
(default `http://127.0.0.1:47475`, resolved in `src/ai/config.ts` →
`collabRelayUrl()`). This is deliberately the same default port as the Symposium
Dart host so a single machine can host both the model proxy and the relay.

Two backends can implement this contract:

1. **A service-key backend** (Node/Python/Edge Function) in front of Supabase,
   using the **service-role key** to read/write the RLS-on `ide_*` tables.
2. **The existing Dart `host_server.dart`**, extended with these routes — it
   already resolves the exact same headers (`x-symposium-admin`,
   `x-symposium-code`) and already owns a `POST /v1/host/limits` /
   `GET /v1/host/stats` control plane this mirrors.

---

## Auth model (identical to `host_server.dart`)

Every request authenticates with **one** header:

| Caller | Header | Meaning |
|---|---|---|
| Room **admin** | `x-symposium-admin: <token>` | Full control of the room (roles, credits, approvals). |
| Room **member** | `x-symposium-code: <joinCode>` | Join + read + open merge requests. |

- The admin token wins if both are present.
- The **service-role key never leaves the relay.** The client only ever sends
  the admin token or a join code.
- `ide_*` tables are **RLS-on with no public policies** (default-deny). They are
  reached only through the relay's service-role connection — same posture as the
  app's `team_*` tables. See `schema.sql` for the rationale.
- **Never log the admin token.**

Errors are JSON `{ "error": "message" }` with a matching HTTP status
(`401` no/invalid auth, `403` not allowed for your role, `400` bad body,
`404` unknown room/MR). The client turns a connection failure into a friendly
"relay not reachable".

---

## Endpoint contract

Base path prefix: `/v1/collab`.

### Rooms

#### `POST /v1/collab/rooms` — create a room *(admin)*
The caller becomes the room admin.
```jsonc
// request
{ "name": "Robotics Project", "ownerEmail": "lead@school.edu" }
// 200 response
{ "id": "uuid", "name": "Robotics Project", "ownerEmail": "lead@school.edu", "joinCode": "AB12CD" }
```
The relay generates a unique `joinCode` and inserts an `ide_members` row for the
owner with `role: 'admin'`.

#### `POST /v1/collab/rooms/join` — join by code *(member; `x-symposium-code`)*
```jsonc
// request
{ "code": "AB12CD", "email": "friend@school.edu" }   // email optional (guests)
// 200 response
{
  "room":   { "id": "uuid", "name": "...", "ownerEmail": "...", "joinCode": "AB12CD" },
  "member": { "email": "friend@school.edu", "role": "viewer", "aiCreditsPerDay": 50, "commitsPerDay": 20 }
}
```
Upserts an `ide_members` row (default `role: 'viewer'`). A missing email gets a
stable `guestId`.

### Roster & credits (the admin "router page")

#### `GET /v1/collab/rooms/{id}/roster` — list members *(admin)*
```jsonc
// 200 response
[
  { "email": "lead@school.edu",   "role": "admin",     "aiCreditsPerDay": 0,  "commitsPerDay": 0  },
  { "email": "friend@school.edu", "role": "committer", "aiCreditsPerDay": 50, "commitsPerDay": 20 }
]
```

#### `POST /v1/collab/rooms/{id}/members/{email}` — set role and/or credits *(admin)*
Partial body — only the fields present are changed (mirrors the partial-merge
style of `POST /v1/host/limits`).
```jsonc
// request (any subset)
{ "role": "committer", "aiCreditsPerDay": 100, "commitsPerDay": 30 }
// 200 response = the updated member row
{ "email": "friend@school.edu", "role": "committer", "aiCreditsPerDay": 100, "commitsPerDay": 30 }
```
`0` on a credit field means **unlimited** (same convention as `HostLimits`).
`{email}` is URL-encoded (emails contain `@`).

#### `GET /v1/collab/rooms/{id}/stats` — live usage *(admin)*
Mirrors `GET /v1/host/stats` in spirit.
```jsonc
// 200 response
{
  "inFlight": 1,
  "todayTotal": 42,
  "uniqueUsersToday": 5,
  "perMember": { "friend@school.edu": { "aiCalls": 12, "commits": 3 } }
}
```

### Merge requests

#### `GET /v1/collab/rooms/{id}/merge-requests` — list *(member or admin)*
```jsonc
[
  { "id": "uuid", "roomId": "uuid", "author": "friend@school.edu", "branch": "feature/login",
    "title": "New login screen", "diffSummary": "3 files changed, 40 insertions(+)",
    "status": "open", "createdAt": "2026-07-25T10:00:00Z" }
]
```

#### `POST /v1/collab/rooms/{id}/merge-requests` — open one *(committer/member)*
```jsonc
// request
{ "author": "friend@school.edu", "branch": "feature/login",
  "title": "New login screen", "diffSummary": "3 files changed, 40 insertions(+)" }
// 200 response = the created merge request (status "open")
```

#### `POST /v1/collab/merge-requests/{id}/approve` — approve *(admin)*
#### `POST /v1/collab/merge-requests/{id}/reject` — send back *(admin)*
```jsonc
// reject body (optional)
{ "reason": "please add tests" }
// 200 response = the updated merge request (status "approved" | "rejected")
// (a bare 204 No Content is also accepted by the client)
```

### Activity feed

#### `GET /v1/collab/rooms/{id}/events?since={id}` — recent activity *(member or admin)*
`since` is optional (0 = from the start of the window). Newest-first.
```jsonc
[
  { "id": 128, "kind": "merge_request_opened",
    "payload": { "title": "New login screen", "author": "friend@school.edu" },
    "createdAt": "2026-07-25T10:00:00Z" }
]
```
Suggested `kind` values: `room_created`, `member_joined`, `role_changed`,
`credits_changed`, `work_saved`, `merge_request_opened`,
`merge_request_approved`, `merge_request_rejected`.

---

## Implementation notes for the relay backend

- **Authz gate first.** Resolve the caller (admin token vs join code) exactly
  like `host_server.dart._resolveTier`, then check the required role for the
  route before touching Supabase.
- **Credits are advisory in v1.** The relay stores `ai_credits_per_day` /
  `commits_per_day`; enforcing them (blocking a member who's over budget) is the
  same fixed-window counting the Dart host already does — add it when wiring the
  member's AI calls through the relay. `0 = unlimited`.
- **Write an `ide_events` row** on every state change so the feed stays live.
- **Never expose the service-role key** to the client or in logs; never log the
  admin token.
- **Join codes** should be short, unambiguous (avoid `0/O`, `1/I`), and unique
  on `ide_rooms.join_code`.

See [`schema.sql`](./schema.sql) for the exact tables, RLS posture, and indexes.
