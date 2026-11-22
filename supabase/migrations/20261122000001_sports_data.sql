-- ScoreLine: sports reference and live match data.
-- Written by your data-ingest backend using the service role key.
-- Apps (anon / signed-in users) can only read.

-- ---------- helpers ----------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------- reference data ----------
create table public.sports (
  id            text primary key,                 -- 'football', 'basketball'
  name          text not null,
  score_format  text not null default 'goals'     -- goals | points | runs | sets | position
);

create table public.competitions (
  id            text primary key,                 -- 'epl', 'bundesliga'
  sport_id      text not null references public.sports(id),
  name          text not null,
  country       text not null,
  region        text,                             -- grouping in the Leagues tab
  type          text not null default 'league' check (type in ('league','cup','tournament')),
  logo_url      text,                             -- licensed image from the data provider
  display_order int  not null default 100,
  provider_ref  text unique,                      -- id in your data provider
  updated_at    timestamptz not null default now()
);
create index competitions_sport_idx on public.competitions (sport_id);

create table public.seasons (
  id             uuid primary key default gen_random_uuid(),
  competition_id text not null references public.competitions(id) on delete cascade,
  label          text not null,                   -- '2026/27'
  start_date     date,
  end_date       date,
  is_current     boolean not null default false,
  unique (competition_id, label)
);
create unique index seasons_one_current_per_competition
  on public.seasons (competition_id) where is_current;

create table public.teams (
  id              text primary key,               -- 'ars', 'fcb'
  sport_id        text not null references public.sports(id),
  name            text not null,
  short_name      text not null,                  -- 'ARS'
  country         text,
  primary_color   text,
  secondary_color text,
  logo_url        text,                           -- licensed crest from the data provider
  provider_ref    text unique,
  updated_at      timestamptz not null default now()
);
create index teams_sport_idx on public.teams (sport_id);
create index teams_name_idx on public.teams (lower(name));

-- which teams play in which season (a team can be in a league AND cups)
create table public.season_teams (
  season_id uuid not null references public.seasons(id) on delete cascade,
  team_id   text not null references public.teams(id) on delete cascade,
  primary key (season_id, team_id)
);
create index season_teams_team_idx on public.season_teams (team_id);

create table public.players (
  id            uuid primary key default gen_random_uuid(),
  team_id       text references public.teams(id) on delete set null,
  name          text not null,
  position      text,
  shirt_number  int,
  nationality   text,
  date_of_birth date,
  photo_url     text,
  provider_ref  text unique,
  updated_at    timestamptz not null default now()
);
create index players_team_idx on public.players (team_id);
create index players_name_idx on public.players (lower(name));

-- ---------- matches ----------
create table public.fixtures (
  id             uuid primary key default gen_random_uuid(),
  season_id      uuid not null references public.seasons(id) on delete cascade,
  competition_id text not null references public.competitions(id) on delete cascade,
  round          text,
  home_team_id   text not null references public.teams(id),
  away_team_id   text not null references public.teams(id),
  kickoff_at     timestamptz not null,
  status         text not null default 'scheduled'
                 check (status in ('scheduled','live','half_time','finished','postponed','cancelled','abandoned')),
  minute         int,                              -- football minute / basketball elapsed
  period         text,                             -- '1H', '2H', 'ET', 'Q3' ...
  home_score     int not null default 0,
  away_score     int not null default 0,
  score_detail   jsonb not null default '{}'::jsonb, -- quarter scores, penalties, sets
  venue          text,
  referee        text,
  provider_ref   text unique,
  updated_at     timestamptz not null default now(),
  check (home_team_id <> away_team_id)
);
create index fixtures_kickoff_idx     on public.fixtures (kickoff_at);
create index fixtures_competition_idx on public.fixtures (competition_id, kickoff_at);
create index fixtures_season_idx      on public.fixtures (season_id);
create index fixtures_home_idx        on public.fixtures (home_team_id, kickoff_at);
create index fixtures_away_idx        on public.fixtures (away_team_id, kickoff_at);
create index fixtures_live_idx        on public.fixtures (status) where status in ('live','half_time');

create table public.fixture_events (
  id                bigint generated always as identity primary key,
  fixture_id        uuid not null references public.fixtures(id) on delete cascade,
  type              text not null check (type in (
                      'goal','own_goal','penalty_goal','missed_penalty',
                      'yellow_card','second_yellow','red_card',
                      'substitution','var_review','goal_disallowed',
                      'period_start','period_end')),
  minute            int,
  extra_minute      int,
  team_id           text references public.teams(id),
  player_id         uuid references public.players(id) on delete set null,
  related_player_id uuid references public.players(id) on delete set null, -- assist, or player subbed off
  detail            jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now()
);
create index fixture_events_fixture_idx on public.fixture_events (fixture_id, minute);
create index fixture_events_team_idx    on public.fixture_events (team_id);
create index fixture_events_player_idx  on public.fixture_events (player_id);
create index fixture_events_related_idx on public.fixture_events (related_player_id);

create table public.fixture_stats (
  fixture_id uuid not null references public.fixtures(id) on delete cascade,
  team_id    text not null references public.teams(id),
  stats      jsonb not null default '{}'::jsonb,  -- {"possession":55,"xg":1.42,"shots":12,...}
  updated_at timestamptz not null default now(),
  primary key (fixture_id, team_id)
);
create index fixture_stats_team_idx on public.fixture_stats (team_id);

create table public.lineups (
  fixture_id   uuid not null references public.fixtures(id) on delete cascade,
  team_id      text not null references public.teams(id),
  player_id    uuid not null references public.players(id) on delete cascade,
  is_starter   boolean not null default true,
  position     text,
  shirt_number int,
  formation    text,                               -- '4-3-3'
  grid         text,                               -- pitch slot, e.g. '2:3'
  rating       numeric(3,1),
  primary key (fixture_id, player_id)
);
create index lineups_team_idx   on public.lineups (team_id);
create index lineups_player_idx on public.lineups (player_id);

-- ---------- tables and leaderboards ----------
create table public.standings (
  season_id      uuid not null references public.seasons(id) on delete cascade,
  team_id        text not null references public.teams(id) on delete cascade,
  group_name     text not null default '',
  rank           int not null,
  played         int not null default 0,
  won            int not null default 0,
  drawn          int not null default 0,
  lost           int not null default 0,
  goals_for      int not null default 0,
  goals_against  int not null default 0,
  goal_difference int generated always as (goals_for - goals_against) stored,
  points         int not null default 0,
  form           text,                             -- 'WWDLW', newest last
  updated_at     timestamptz not null default now(),
  primary key (season_id, group_name, team_id)
);
create index standings_team_idx on public.standings (team_id);

create table public.player_season_stats (
  season_id   uuid not null references public.seasons(id) on delete cascade,
  player_id   uuid not null references public.players(id) on delete cascade,
  team_id     text references public.teams(id),
  appearances int not null default 0,
  minutes     int not null default 0,
  goals       int not null default 0,
  assists     int not null default 0,
  points      numeric,                             -- basketball points per game etc.
  rating      numeric(3,2),
  updated_at  timestamptz not null default now(),
  primary key (season_id, player_id)
);
create index player_season_stats_player_idx on public.player_season_stats (player_id);
create index player_season_stats_team_idx   on public.player_season_stats (team_id);
create index player_season_stats_goals_idx  on public.player_season_stats (season_id, goals desc);

-- ---------- updated_at triggers ----------
create trigger competitions_updated_at before update on public.competitions for each row execute function public.set_updated_at();
create trigger teams_updated_at        before update on public.teams        for each row execute function public.set_updated_at();
create trigger players_updated_at      before update on public.players      for each row execute function public.set_updated_at();
create trigger fixtures_updated_at     before update on public.fixtures     for each row execute function public.set_updated_at();
create trigger fixture_stats_updated_at before update on public.fixture_stats for each row execute function public.set_updated_at();
create trigger standings_updated_at    before update on public.standings    for each row execute function public.set_updated_at();
create trigger player_season_stats_updated_at before update on public.player_season_stats for each row execute function public.set_updated_at();

-- ---------- security: everyone can read, only the service role writes ----------
do $$
declare t text;
begin
  foreach t in array array['sports','competitions','seasons','teams','season_teams','players',
                           'fixtures','fixture_events','fixture_stats','lineups','standings','player_season_stats']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "Public read" on public.%I for select to anon, authenticated using (true)', t);
    execute format('revoke insert, update, delete, truncate on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------- live updates ----------
alter publication supabase_realtime add table public.fixtures, public.fixture_events;
