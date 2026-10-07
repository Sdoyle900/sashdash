-- ════════════════════════════════════════════════════════════════════
--  SashDash — Supabase setup
--  Run this ONCE in your Supabase project:  SQL Editor → New query →
--  paste everything → Run.   Safe to re-run (it drops/recreates policies).
-- ════════════════════════════════════════════════════════════════════

-- ── 1. TABLES ──────────────────────────────────────────────────────────

-- One row per login (you + each service man). Created automatically when
-- you add a user in Authentication → Users.
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null default '',
  role        text not null default 'serviceman' check (role in ('admin','serviceman')),
  phone       text,
  colour      text not null default '#4f46e5',
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

-- A site (e.g. "Herons Lock") belongs to one service man.
create table if not exists public.sites (
  id             uuid primary key default gen_random_uuid(),
  serviceman_id  uuid not null references public.profiles(id) on delete cascade,
  name           text not null,
  address        text,
  contact        text,
  archived       boolean not null default false,
  created_at     timestamptz not null default now()
);

-- A job = one uploaded order sheet / site instruction PDF.
create table if not exists public.jobs (
  id               uuid primary key default gen_random_uuid(),
  site_id          uuid not null references public.sites(id) on delete cascade,
  serviceman_id    uuid not null references public.profiles(id) on delete cascade,
  title            text not null,
  ref_no           text,
  notes            text,
  pdf_path         text,                 -- storage path of the original
  pdf_bytes        bigint not null default 0,
  marked_path      text,                 -- storage path of the marked-up copy
  marked_bytes     bigint not null default 0,
  markup           jsonb  not null default '[]'::jsonb,   -- pen strokes (so they stay editable)
  completed        boolean not null default false,
  completed_at     timestamptz,
  admin_unread     boolean not null default false,  -- something new for the office
  tech_unread      boolean not null default true,   -- something new for the service man
  last_activity_at timestamptz not null default now(),
  created_by       uuid references public.profiles(id),
  created_at       timestamptz not null default now()
);

-- The conversation beside each job.
create table if not exists public.comments (
  id          uuid primary key default gen_random_uuid(),
  job_id      uuid not null references public.jobs(id) on delete cascade,
  author_id   uuid not null references public.profiles(id) on delete cascade,
  body        text not null check (length(trim(body)) > 0),
  kind        text not null default 'message' check (kind in ('message','event')),
  created_at  timestamptz not null default now()
);

create index if not exists sites_serviceman_idx on public.sites(serviceman_id);
create index if not exists jobs_site_idx        on public.jobs(site_id);
create index if not exists jobs_serviceman_idx  on public.jobs(serviceman_id);
create index if not exists comments_job_idx     on public.comments(job_id, created_at);

-- ── 2. HELPERS ─────────────────────────────────────────────────────────

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- New login → new profile (defaults to service man, name from email).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, initcap(replace(split_part(new.email, '@', 1), '.', ' ')))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Back-fill profiles for any users that existed before this script ran.
insert into public.profiles (id, full_name)
select id, initcap(replace(split_part(email, '@', 1), '.', ' ')) from auth.users
on conflict (id) do nothing;

-- New comment → flag the job as unread for the *other* side.
create or replace function public.on_comment_added() returns trigger
language plpgsql security definer set search_path = public as $$
declare author_is_admin boolean;
begin
  select role = 'admin' into author_is_admin from public.profiles where id = new.author_id;
  update public.jobs set
    last_activity_at = now(),
    admin_unread = case when author_is_admin then admin_unread else true end,
    tech_unread  = case when author_is_admin then true else tech_unread end
  where id = new.job_id;
  return new;
end $$;

drop trigger if exists comment_added on public.comments;
create trigger comment_added after insert on public.comments
  for each row execute function public.on_comment_added();

-- ── 3. ACTIONS SERVICE MEN ARE ALLOWED TO DO ──────────────────────────
-- Service men can't edit job rows directly; they go through these,
-- which check the job is theirs.

create or replace function public.can_touch_job(p_job uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists(
    select 1 from public.jobs where id = p_job and serviceman_id = auth.uid());
$$;

create or replace function public.set_job_complete(p_job uuid, p_done boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.can_touch_job(p_job) then raise exception 'Not your job'; end if;
  update public.jobs set completed = p_done,
         completed_at = case when p_done then now() else null end,
         last_activity_at = now(),
         admin_unread = case when public.is_admin() then admin_unread else true end,
         tech_unread  = case when public.is_admin() then true else tech_unread end
   where id = p_job;
  insert into public.comments(job_id, author_id, body, kind)
  values (p_job, auth.uid(), case when p_done then 'Marked job as completed ✔' else 'Re-opened job' end, 'event');
end $$;

create or replace function public.save_markup(p_job uuid, p_markup jsonb, p_marked_path text, p_marked_bytes bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.can_touch_job(p_job) then raise exception 'Not your job'; end if;
  update public.jobs set markup = coalesce(p_markup, '[]'::jsonb),
         marked_path = p_marked_path, marked_bytes = coalesce(p_marked_bytes, 0),
         last_activity_at = now(),
         admin_unread = case when public.is_admin() then admin_unread else true end,
         tech_unread  = case when public.is_admin() then true else tech_unread end
   where id = p_job;
  insert into public.comments(job_id, author_id, body, kind)
  values (p_job, auth.uid(), 'Updated the marked-up sheet ✏️', 'event');
end $$;

create or replace function public.mark_job_seen(p_job uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.can_touch_job(p_job) then return; end if;
  if public.is_admin() then update public.jobs set admin_unread = false where id = p_job;
  else update public.jobs set tech_unread = false where id = p_job; end if;
end $$;

grant execute on function public.set_job_complete(uuid, boolean)            to authenticated;
grant execute on function public.save_markup(uuid, jsonb, text, bigint)      to authenticated;
grant execute on function public.mark_job_seen(uuid)                         to authenticated;
grant execute on function public.is_admin()                                  to authenticated;

-- ── 4. ROW LEVEL SECURITY (who sees what) ─────────────────────────────

alter table public.profiles enable row level security;
alter table public.sites    enable row level security;
alter table public.jobs     enable row level security;
alter table public.comments enable row level security;

drop policy if exists profiles_read  on public.profiles;
drop policy if exists profiles_admin on public.profiles;
create policy profiles_read  on public.profiles for select to authenticated using (true);  -- names only
create policy profiles_admin on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists sites_admin on public.sites;
drop policy if exists sites_own   on public.sites;
create policy sites_admin on public.sites for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy sites_own   on public.sites for select to authenticated using (serviceman_id = auth.uid());

drop policy if exists jobs_admin on public.jobs;
drop policy if exists jobs_own   on public.jobs;
create policy jobs_admin on public.jobs for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy jobs_own   on public.jobs for select to authenticated using (serviceman_id = auth.uid());

drop policy if exists comments_read   on public.comments;
drop policy if exists comments_write  on public.comments;
drop policy if exists comments_admin  on public.comments;
create policy comments_read  on public.comments for select to authenticated using (public.can_touch_job(job_id));
create policy comments_write on public.comments for insert to authenticated
  with check (author_id = auth.uid() and kind = 'message' and public.can_touch_job(job_id));
create policy comments_admin on public.comments for delete to authenticated using (public.is_admin());

-- ── 5. FILE STORAGE (private bucket) ──────────────────────────────────
-- Files are stored as  <serviceman id>/<job id>/original.pdf  and  marked.pdf

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('job-files', 'job-files', false, 26214400, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 26214400, allowed_mime_types = array['application/pdf'];

drop policy if exists jobfiles_admin      on storage.objects;
drop policy if exists jobfiles_tech_read  on storage.objects;
drop policy if exists jobfiles_tech_ins   on storage.objects;
drop policy if exists jobfiles_tech_upd   on storage.objects;

create policy jobfiles_admin on storage.objects for all to authenticated
  using (bucket_id = 'job-files' and public.is_admin())
  with check (bucket_id = 'job-files' and public.is_admin());

create policy jobfiles_tech_read on storage.objects for select to authenticated
  using (bucket_id = 'job-files' and (storage.foldername(name))[1] = auth.uid()::text);

-- service men may only write the marked-up copy, in their own folder
create policy jobfiles_tech_ins on storage.objects for insert to authenticated
  with check (bucket_id = 'job-files' and (storage.foldername(name))[1] = auth.uid()::text
              and storage.filename(name) = 'marked.pdf');
create policy jobfiles_tech_upd on storage.objects for update to authenticated
  using (bucket_id = 'job-files' and (storage.foldername(name))[1] = auth.uid()::text
         and storage.filename(name) = 'marked.pdf');
drop policy if exists jobfiles_tech_del on storage.objects;
create policy jobfiles_tech_del on storage.objects for delete to authenticated
  using (bucket_id = 'job-files' and (storage.foldername(name))[1] = auth.uid()::text
         and storage.filename(name) = 'marked.pdf');

-- ── 6. LIVE UPDATES (chat appears instantly) ──────────────────────────
do $$ begin
  begin alter publication supabase_realtime add table public.comments; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.jobs;     exception when duplicate_object then null; end;
end $$;

-- ── 7. MAKE YOURSELF THE ADMIN ────────────────────────────────────────
-- After you've created your own login in Authentication → Users,
-- change the email below and run just this line:
--
--   update public.profiles set role = 'admin', full_name = 'Sean'
--   where id = (select id from auth.users where email = 'seandoyle102@gmail.com');
