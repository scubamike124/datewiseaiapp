-- ============================================================================
-- DateWise AI — Migration: profile pictures (avatars)
-- Run this ONCE in Supabase → SQL Editor (safe to re-run). Adds the avatar
-- column, a public 'avatars' storage bucket, its security policies, and
-- refreshes the admin view to include avatars.
-- ============================================================================

-- 1) Column to remember each user's picture URL
alter table public.profiles add column if not exists avatar_url text;

-- 2) Public storage bucket for the images
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- 3) Storage security: anyone can view; a user may only write their own folder
--    (files live at  avatars/<user-id>/avatar.<ext> )
drop policy if exists "avatars public read" on storage.objects;
drop policy if exists "avatars user insert" on storage.objects;
drop policy if exists "avatars user update" on storage.objects;
drop policy if exists "avatars user delete" on storage.objects;

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

-- 4) Rebuild the admin user-list view to include avatar_url
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
  p.created_at                          as joined_at,
  coalesce(s.tier, 'spark')             as tier,
  coalesce(s.status, 'pending_payment') as status,
  s.provider,
  s.current_period_end
from public.profiles p
left join public.subscriptions s on s.user_id = p.id
order by p.created_at desc;
