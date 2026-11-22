-- ScoreLine: user accounts (Supabase Auth), favourites and alert settings.
-- Every row belongs to one user, and users can only see and change their own rows.

create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text check (char_length(display_name) <= 60),
  avatar_url   text,
  locale       text not null default 'en',
  time_zone    text,
  theme        text not null default 'light' check (theme in ('light','dark','system')),
  onboarded    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.follows (
  user_id     uuid not null references auth.users(id) on delete cascade,
  entity_type text not null check (entity_type in ('team','competition','fixture','player')),
  entity_id   text not null,               -- team / competition id, or fixture / player uuid
  alerts      jsonb,                       -- optional per-follow alert overrides
  created_at  timestamptz not null default now(),
  primary key (user_id, entity_type, entity_id)
);
-- used by the push service to find everyone following a team / match
create index follows_entity_idx on public.follows (entity_type, entity_id);

create table public.notification_settings (
  user_id           uuid primary key references auth.users(id) on delete cascade,
  goals             boolean not null default true,
  red_cards         boolean not null default true,
  kickoff           boolean not null default true,
  half_time         boolean not null default false,
  full_time         boolean not null default true,
  lineups           boolean not null default true,
  big_moments_only  boolean not null default false,
  quiet_hours_start time,
  quiet_hours_end   time,
  updated_at        timestamptz not null default now()
);

create table public.push_devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  platform     text not null check (platform in ('ios','android','web')),
  token        text not null unique,
  app_version  text,
  last_seen_at timestamptz not null default now(),
  created_at   timestamptz not null default now()
);
create index push_devices_user_idx on public.push_devices (user_id);

create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger notification_settings_updated_at before update on public.notification_settings
  for each row execute function public.set_updated_at();

-- ---------- create a profile + default alert settings on sign-up ----------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;

  insert into public.notification_settings (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- row level security: own rows only ----------
alter table public.profiles              enable row level security;
alter table public.follows               enable row level security;
alter table public.notification_settings enable row level security;
alter table public.push_devices          enable row level security;

create policy "Own profile: read"   on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy "Own profile: update" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy "Own follows: read"   on public.follows for select to authenticated using ((select auth.uid()) = user_id);
create policy "Own follows: add"    on public.follows for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Own follows: update" on public.follows for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Own follows: remove" on public.follows for delete to authenticated using ((select auth.uid()) = user_id);

create policy "Own alert settings: read"   on public.notification_settings for select to authenticated using ((select auth.uid()) = user_id);
create policy "Own alert settings: add"    on public.notification_settings for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Own alert settings: update" on public.notification_settings for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy "Own devices: read"   on public.push_devices for select to authenticated using ((select auth.uid()) = user_id);
create policy "Own devices: add"    on public.push_devices for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Own devices: update" on public.push_devices for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Own devices: remove" on public.push_devices for delete to authenticated using ((select auth.uid()) = user_id);

-- signed-out visitors get nothing from these tables
revoke all on public.profiles, public.follows, public.notification_settings, public.push_devices from anon;
