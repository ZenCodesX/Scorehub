-- ScoreLine: table permissions for the Supabase Data API.
-- This project does not grant table access to API roles by default, so grant exactly what the app needs.
-- Row level security policies (previous migrations) still decide WHICH rows each user can touch.

-- backend / data ingest (service role key, server-side only)
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

-- sports data: read-only for everyone
grant select on public.sports, public.competitions, public.seasons, public.teams, public.season_teams,
                public.players, public.fixtures, public.fixture_events, public.fixture_stats,
                public.lineups, public.standings, public.player_season_stats
  to anon, authenticated;

-- user data: signed-in users only (rows limited to their own by RLS)
grant select, update                 on public.profiles              to authenticated;
grant select, insert, update, delete on public.follows               to authenticated;
grant select, insert, update         on public.notification_settings to authenticated;
grant select, insert, update, delete on public.push_devices          to authenticated;
