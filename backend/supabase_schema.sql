-- ============================================================================
-- DateWise AI — Supabase schema (accounts + subscriptions + admin)
-- ----------------------------------------------------------------------------
-- Run this ONCE in your Supabase project: Dashboard → SQL Editor → New query →
-- paste everything → Run. It is safe to re-run (idempotent).
--
-- What it creates:
--   • profiles        — one row per user (email, name, role: user|admin)
--   • subscriptions   — each user's chosen plan + status (your "paid" truth)
--   • a trigger that auto-creates a profile whenever someone signs up
--   • row-level security so users can only see their OWN data
--   • admin_user_overview — a ready-made VIEW = your admin user list
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. PROFILES  (1:1 with Supabase Auth users)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text,
  display_name text,
  avatar_url  text,
  role        text not null default 'user' check (role in ('user', 'admin')),
  suspended   boolean not null default false,
  created_at  timestamptz not null default now()
);

-- Safe to re-run on an existing project (adds columns if they're missing):
alter table public.profiles
  add column if not exists suspended boolean not null default false;
alter table public.profiles
  add column if not exists avatar_url text;
-- Set by the in-app "Delete account" action so you can find & remove these
-- users from the dashboard (the public anon key can't delete auth users).
alter table public.profiles
  add column if not exists deletion_requested boolean not null default false;

-- ---------------------------------------------------------------------------
-- 2. SUBSCRIPTIONS  (1:1 with a user; the source of truth for "who paid")
--    status meanings:
--      pending_payment — picked a plan, not yet charged (today, pre-Stripe)
--      active          — currently paying  → this is your real "paid user"
--      canceled        — was paying, stopped
-- ---------------------------------------------------------------------------
create table if not exists public.subscriptions (
  user_id            uuid primary key references auth.users (id) on delete cascade,
  tier               text not null default 'spark'
                       check (tier in ('spark', 'flame', 'magnet')),
  status             text not null default 'pending_payment'
                       check (status in ('pending_payment', 'active', 'canceled')),
  -- Reserved for when you wire real payments (Stripe / IAP) later:
  provider           text,        -- 'stripe' | 'apple' | 'google' | null
  provider_customer  text,        -- e.g. Stripe customer id
  current_period_end timestamptz, -- when the paid period ends
  updated_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 3. Auto-create a profile (and a starter subscription row) on sign-up.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'display_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 4. Admin check helper (SECURITY DEFINER so it doesn't trip RLS recursion).
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- ---------------------------------------------------------------------------
-- 5. Row-Level Security: users see only their own rows; admins see all.
-- ---------------------------------------------------------------------------
alter table public.profiles      enable row level security;
alter table public.subscriptions enable row level security;

-- profiles --------------------------------------------------------------
drop policy if exists "own profile read"   on public.profiles;
drop policy if exists "own profile update" on public.profiles;
drop policy if exists "admin profile read" on public.profiles;

create policy "own profile read"
  on public.profiles for select using (auth.uid() = id);
create policy "own profile update"
  on public.profiles for update using (auth.uid() = id);
create policy "admin profile read"
  on public.profiles for select using (public.is_admin());

-- Admins may update any profile (used to suspend/unsuspend users).
drop policy if exists "admin profile update" on public.profiles;
create policy "admin profile update"
  on public.profiles for update using (public.is_admin());

-- subscriptions ---------------------------------------------------------
drop policy if exists "own sub read"   on public.subscriptions;
drop policy if exists "own sub write"  on public.subscriptions;
drop policy if exists "own sub update" on public.subscriptions;
drop policy if exists "admin sub read" on public.subscriptions;

create policy "own sub read"
  on public.subscriptions for select using (auth.uid() = user_id);
create policy "own sub write"
  on public.subscriptions for insert with check (auth.uid() = user_id);
create policy "own sub update"
  on public.subscriptions for update using (auth.uid() = user_id);
create policy "admin sub read"
  on public.subscriptions for select using (public.is_admin());

-- Admins may create/change any user's subscription (set plan + status,
-- including marking someone 'active' as a manual comp). This is gated to
-- admins by public.is_admin(); regular users can still only touch their own.
drop policy if exists "admin sub write"  on public.subscriptions;
drop policy if exists "admin sub update2" on public.subscriptions;
create policy "admin sub write"
  on public.subscriptions for insert with check (public.is_admin());
create policy "admin sub update2"
  on public.subscriptions for update using (public.is_admin());
-- NOTE: a regular user can only write their own row as 'pending_payment'.
-- When you add Stripe, flip rows to 'active' from a trusted server
-- (Edge Function with the service-role key), NOT from the client.

-- ---------------------------------------------------------------------------
-- 6. ADMIN VIEW — your user list. Open it in Table Editor or query it.
-- ---------------------------------------------------------------------------
-- Dropped first so re-running can change/reorder columns (create-or-replace
-- alone can't insert a column in the middle of an existing view).
drop view if exists public.admin_user_overview;
create view public.admin_user_overview
with (security_invoker = on) as
select
  p.id,
  p.email,
  p.display_name,
  p.avatar_url,
  p.role,
  p.suspended,
  p.created_at                       as joined_at,
  coalesce(s.tier, 'spark')          as tier,
  coalesce(s.status, 'pending_payment') as status,
  s.provider,
  s.current_period_end
from public.profiles p
left join public.subscriptions s on s.user_id = p.id
order by p.created_at desc;

-- ---------------------------------------------------------------------------
-- 7. AVATAR STORAGE — a public bucket for profile pictures.
--    Files are stored at  avatars/<user-id>/avatar.<ext>  so each user can
--    only write their own folder. Anyone can read (pictures are public).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatars public read"  on storage.objects;
drop policy if exists "avatars user insert"  on storage.objects;
drop policy if exists "avatars user update"  on storage.objects;
drop policy if exists "avatars user delete"  on storage.objects;

create policy "avatars public read"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "avatars user insert"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars'
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars user update"
  on storage.objects for update to authenticated
  using (bucket_id = 'avatars'
         and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars user delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'avatars'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================================
-- HOW TO USE (admin):
--   • Full user list:   select * from public.admin_user_overview;
--   • Paid users only:  select * from public.admin_user_overview where status = 'active';
--   • Count paid/plan:  select tier, count(*) from public.subscriptions
--                       where status = 'active' group by tier;
--   • Make yourself admin (after signing up once in the app):
--       update public.profiles set role = 'admin' where email = 'you@example.com';
--   • Suspend/remove a user: Dashboard → Authentication → Users → ban or delete.
-- ============================================================================
