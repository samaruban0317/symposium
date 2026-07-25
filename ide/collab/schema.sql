-- Symposium Studio · Collaboration ("visualised GitHub") schema.
--
-- These `ide_*` tables back the Team/Admin pillar: rooms, members (with roles +
-- per-user credits), merge requests, and an activity feed.
--
-- SECURITY MODEL — mirrors the app's `team_*` tables EXACTLY:
--   • Row Level Security is ON for every table.
--   • There are NO public policies, so RLS default-DENIES all access to the
--     `anon` and `authenticated` roles. Nothing reaches these tables through
--     the client Supabase key.
--   • They are reached ONLY by the relay backend using the SERVICE-ROLE key,
--     which bypasses RLS. The relay is the single trusted gate (it checks the
--     x-symposium-admin token / x-symposium-code join code before any write).
--   This avoids RLS recursion (like team_members) and keeps all authz in one
--   place — the relay — instead of scattered policies.
--
-- Supabase's advisor will flag "RLS enabled, no policy" as INFO. That is
-- INTENTIONAL here (same as team_*/news_*/calendar_events). Do not "fix" it by
-- adding public policies.
--
-- Apply with the Supabase SQL editor or `supabase db push`. Safe to re-run
-- (IF NOT EXISTS everywhere).

-- gen_random_uuid() comes from pgcrypto (usually already enabled on Supabase).
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Rooms — one per team project space.
-- ---------------------------------------------------------------------------
create table if not exists public.ide_rooms (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  owner_email text,                       -- who created it (the first admin)
  join_code   text unique not null,       -- the short code members type to join
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Members — the "router device list": role + per-user daily budgets.
--   role: admin (full control) | committer (can save & share) | viewer (read).
--   *_per_day: 0 means unlimited (same convention as the Dart HostLimits).
-- ---------------------------------------------------------------------------
create table if not exists public.ide_members (
  id                 uuid primary key default gen_random_uuid(),
  room_id            uuid not null references public.ide_rooms(id) on delete cascade,
  member_email       text,               -- null for guests (see guest_id)
  guest_id           text,               -- stable id for a login-less guest
  role               text not null default 'viewer'
                       check (role in ('admin', 'committer', 'viewer')),
  ai_credits_per_day int  not null default 50,
  commits_per_day    int  not null default 20,
  updated_at         timestamptz not null default now(),
  -- One row per email per room (guests are deduped by the relay via guest_id).
  unique (room_id, member_email)
);

-- ---------------------------------------------------------------------------
-- Merge requests — "please approve my work" cards the admin acts on.
-- ---------------------------------------------------------------------------
create table if not exists public.ide_merge_requests (
  id           uuid primary key default gen_random_uuid(),
  room_id      uuid not null references public.ide_rooms(id) on delete cascade,
  author       text not null,            -- email or display name of the opener
  branch       text,                     -- the branch being proposed
  title        text not null,
  diff_summary text,                     -- e.g. "3 files changed, 40 insertions(+)"
  status       text not null default 'open'
                 check (status in ('open', 'approved', 'rejected')),
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Events — the room activity feed (joined / saved / approved …).
--   payload is free-form JSON so new event kinds need no migration.
-- ---------------------------------------------------------------------------
create table if not exists public.ide_events (
  id         bigint generated always as identity primary key,
  room_id    uuid not null references public.ide_rooms(id) on delete cascade,
  kind       text not null,
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Indexes — every read is scoped to a room, so index (room_id) everywhere.
-- ---------------------------------------------------------------------------
create index if not exists ide_members_room_idx        on public.ide_members(room_id);
create index if not exists ide_merge_requests_room_idx on public.ide_merge_requests(room_id);
create index if not exists ide_events_room_idx         on public.ide_events(room_id);
-- Feed reads want newest-first within a room.
create index if not exists ide_events_room_id_desc_idx on public.ide_events(room_id, id desc);

-- ---------------------------------------------------------------------------
-- RLS ON, NO POLICIES = default-deny to public. Reached only via service key.
-- (Identical posture to the app's team_* tables.)
-- ---------------------------------------------------------------------------
alter table public.ide_rooms           enable row level security;
alter table public.ide_members         enable row level security;
alter table public.ide_merge_requests  enable row level security;
alter table public.ide_events          enable row level security;
