-- Troop Tournaments (1.1.3, 2026-11-26). DO NOT RUN until Paul approves. Then flip TOURNEYS_LIVE in web/index.html.
--
-- Production compatibility: purely additive.
--   * new tables tournaments / tournament_members (RLS on, no direct access, like every other table);
--   * two new nullable-default columns on players (pz_placed, pz_done);
--   * new functions submit_puzzle_stats, tourney_create, tourney_answer, tourney_leave, tourney_state, tourney_claim;
--   * my_news is replaced with the same output plus one new key, 'tourney' (older apps ignore unknown keys; the native reminder
--     code only reads the keys it knows).
-- Nothing existing is dropped or renamed, and submit_score is untouched, so 1.1 / 1.1.1 / 1.1.2 keep working exactly as now.
-- Safe to run twice (if not exists / create or replace).
--
-- Scoring: +10 per new level (players.level going up), +3 per puzzle piece placed (own puzzles via submit_puzzle_stats, shared ones
-- from duo_pieces), +25 per puzzle finished. Each member's totals are snapshotted at JOIN (base_*) and only move on a sync made
-- while the tournament is live (cur_*), so replays, retries, re-sent syncs and anything after the deadline count nothing.

create table if not exists public.tournaments (
  id         bigserial primary key,
  host       uuid not null references public.players(id) on delete cascade,
  starts_at  timestamptz not null default now(),
  ends_at    timestamptz not null default now() + interval '5 days',
  created_at timestamptz not null default now()
);
create table if not exists public.tournament_members (
  tourney     bigint not null references public.tournaments(id) on delete cascade,
  player      uuid not null references public.players(id) on delete cascade,
  status      text not null default 'invited' check (status in ('invited', 'joined', 'declined', 'left')),
  joined_at   timestamptz,
  base_level  int, base_placed int, base_done int,
  cur_level   int, cur_placed int, cur_done int,
  claimed     boolean not null default false,
  invited_at  timestamptz not null default now(),
  primary key (tourney, player)
);
create index if not exists tournament_members_player_idx on public.tournament_members (player, status);
alter table public.players add column if not exists pz_placed int not null default 0;
alter table public.players add column if not exists pz_done int not null default 0;
alter table public.tournaments enable row level security;
alter table public.tournament_members enable row level security;
revoke all on public.tournaments from anon, authenticated;
revoke all on public.tournament_members from anon, authenticated;

-- One member's points (levels, pieces, puzzles, points). Internal.
create or replace function public.tourney_points(m public.tournament_members, t public.tournaments)
returns table (levels int, pieces int, puzzles int, points int) language sql stable security definer set search_path = public as $$
  with x as (select
    case when m.status = 'joined' then least(greatest(coalesce(m.cur_level, m.base_level) - m.base_level, 0), 300) else 0 end as lv,
    case when m.status = 'joined' then greatest(coalesce(m.cur_placed, m.base_placed) - m.base_placed, 0)
      + (select count(*)::int from public.duo_pieces d where d.placed_by = m.player and d.placed_at >= m.joined_at and d.placed_at < t.ends_at) else 0 end as pc,
    case when m.status = 'joined' then least(greatest(coalesce(m.cur_done, m.base_done) - m.base_done, 0), 60) else 0 end as pz)
  select lv, pc, pz, lv * 10 + pc * 3 + pz * 25 from x
$$;
revoke all on function public.tourney_points(public.tournament_members, public.tournaments) from public, anon, authenticated;

-- The app's puzzle totals (pieces placed in your own puzzles, puzzles finished), never lower than before, plus every live tournament
-- you've joined takes your current level and totals. Called right after submit_score.
create or replace function public.submit_puzzle_stats(p_id uuid, p_secret text, p_placed int, p_done int) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  if p_placed < 0 or p_placed > 5000 or p_done < 0 or p_done > 400 then raise exception 'bad values'; end if;
  update public.players set pz_placed = greatest(pz_placed, p_placed), pz_done = greatest(pz_done, p_done) where id = p_id returning * into me;
  update public.tournament_members m set
      cur_level = greatest(coalesce(m.cur_level, m.base_level), me.level),
      cur_placed = greatest(coalesce(m.cur_placed, m.base_placed), me.pz_placed),
      cur_done = greatest(coalesce(m.cur_done, m.base_done), me.pz_done)
    from public.tournaments t
    where t.id = m.tourney and m.player = p_id and m.status = 'joined' and now() < t.ends_at;
  return true;
end $$;

-- Start a tournament with friends (you join at once; they're invited), or invite more friends to your live one (p_tourney).
-- Returns {status: created|added|full|no_friends|gone, id}. Friends only, 8 players at most, 3 live tournaments per player.
create or replace function public.tourney_create(p_id uuid, p_secret text, p_friends uuid[], p_name text default null, p_tourney bigint default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.players := player_auth(p_id, p_secret);
  t public.tournaments;
  f uuid;
  ok uuid[];
begin
  select coalesce(array_agg(x), '{}') into ok from (select distinct x from unnest(coalesce(p_friends, '{}')) x
    where x <> p_id and exists (select 1 from public.friend_links where player = p_id and other = x and status = 'friends')
      and exists (select 1 from public.friend_links where player = x and other = p_id and status = 'friends') limit 7) y;
  if cardinality(ok) = 0 then return json_build_object('status', 'no_friends'); end if;
  if p_tourney is not null then
    select * into t from public.tournaments where id = p_tourney and host = p_id and now() < ends_at;
    if t.id is null then return json_build_object('status', 'gone'); end if;
    foreach f in array ok loop
      exit when (select count(*) from public.tournament_members where tourney = t.id) >= 8;
      insert into public.tournament_members (tourney, player) values (t.id, f) on conflict do nothing;
    end loop;
    return json_build_object('status', 'added', 'id', t.id);
  end if;
  if (select count(*) from public.tournament_members m join public.tournaments x on x.id = m.tourney
      where m.player = p_id and m.status = 'joined' and now() < x.ends_at) >= 3 then return json_build_object('status', 'full'); end if;
  -- One new tournament an hour at most per host (keeps invites from turning into spam).
  if exists (select 1 from public.tournaments where host = p_id and created_at > now() - interval '1 hour') then return json_build_object('status', 'full'); end if;
  insert into public.tournaments (host) values (p_id) returning * into t;
  insert into public.tournament_members (tourney, player, status, joined_at, base_level, base_placed, base_done)
    values (t.id, p_id, 'joined', now(), me.level, me.pz_placed, me.pz_done);
  foreach f in array ok loop insert into public.tournament_members (tourney, player) values (t.id, f) on conflict do nothing; end loop;
  return json_build_object('status', 'created', 'id', t.id);
end $$;

-- Join or decline an invite. Returns joined | declined | full | gone. Joining takes your snapshot.
create or replace function public.tourney_answer(p_id uuid, p_secret text, p_tourney bigint, p_join boolean) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  if not exists (select 1 from public.tournament_members m join public.tournaments t on t.id = m.tourney
      where m.tourney = p_tourney and m.player = p_id and m.status = 'invited' and now() < t.ends_at) then return 'gone'; end if;
  if not p_join then update public.tournament_members set status = 'declined' where tourney = p_tourney and player = p_id; return 'declined'; end if;
  if (select count(*) from public.tournament_members m join public.tournaments x on x.id = m.tourney
      where m.player = p_id and m.status = 'joined' and now() < x.ends_at) >= 3 then return 'full'; end if;
  update public.tournament_members set status = 'joined', joined_at = now(), base_level = me.level, base_placed = me.pz_placed, base_done = me.pz_done
    where tourney = p_tourney and player = p_id;
  return 'joined';
end $$;

-- Leave (keeps nothing: a member who left scores 0 and can't claim).
create or replace function public.tourney_leave(p_id uuid, p_secret text, p_tourney bigint) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  update public.tournament_members set status = 'left' where tourney = p_tourney and player = p_id and status in ('invited', 'joined');
end $$;

-- Your tournaments (invited or joined; live, or finished in the last 7 days) with standings, ties sharing a place.
create or replace function public.tourney_state(p_id uuid, p_secret text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  return json_build_object('now', now(), 'tourneys', coalesce((select json_agg(q.v order by q.starts desc) from (
    select t.starts_at as starts, json_build_object(
      'id', t.id, 'name', shown_name(h) || '''s Troop Tournament',
      'status', case when now() < t.ends_at then 'live' else 'finished' end,
      'starts_at', t.starts_at, 'ends_at', t.ends_at, 'now', now(),
      'host', json_build_object('id', h.id, 'name', shown_name(h), 'avatar', h.avatar, 'tier', h.tier),
      'my_status', mine.status, 'claimed', mine.claimed,
      'points', json_build_object('level', 10, 'piece', 3, 'puzzle', 25),
      'standings', coalesce((select json_agg(json_build_object('id', p.id, 'name', shown_name(p), 'avatar', p.avatar, 'tier', p.tier, 'me', p.id = p_id,
          'levels', s.levels, 'pieces', s.pieces, 'puzzles', s.puzzles, 'points', s.points, 'place', s.place) order by s.points desc, shown_name(p))
        from (select m.player, z.*, rank() over (order by z.points desc) as place
              from public.tournament_members m, lateral public.tourney_points(m, t) z where m.tourney = t.id and m.status = 'joined') s
        join public.players p on p.id = s.player), '[]'),
      'invited', coalesce((select json_agg(json_build_object('id', p.id, 'name', shown_name(p), 'avatar', p.avatar))
        from public.tournament_members m join public.players p on p.id = m.player where m.tourney = t.id and m.status = 'invited'), '[]')) as v
    from public.tournament_members mine join public.tournaments t on t.id = mine.tourney join public.players h on h.id = t.host
    where mine.player = p_id and mine.status in ('invited', 'joined') and (now() < t.ends_at or (mine.status = 'joined' and t.ends_at > now() - interval '7 days'))
  ) q), '[]'));
end $$;

-- Claim the end result once (the app pays the reward only when ok). Returns {ok, place, winner, points}.
create or replace function public.tourney_claim(p_id uuid, p_secret text, p_tourney bigint) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.players := player_auth(p_id, p_secret);
  t public.tournaments;
  r record;
begin
  select * into t from public.tournaments where id = p_tourney and now() >= ends_at;
  if t.id is null then return json_build_object('ok', false); end if;
  update public.tournament_members set claimed = true where tourney = t.id and player = p_id and status = 'joined' and not claimed;
  if not found then return json_build_object('ok', false); end if;
  select s.points, s.place into r from (select m.player, z.points, rank() over (order by z.points desc) as place
    from public.tournament_members m, lateral public.tourney_points(m, t) z where m.tourney = t.id and m.status = 'joined') s where s.player = p_id;
  return json_build_object('ok', true, 'place', r.place, 'winner', r.place = 1 and r.points > 0, 'points', r.points);
end $$;

revoke all on function public.submit_puzzle_stats(uuid, text, int, int) from public;
revoke all on function public.tourney_create(uuid, text, uuid[], text, bigint) from public;
revoke all on function public.tourney_answer(uuid, text, bigint, boolean) from public;
revoke all on function public.tourney_leave(uuid, text, bigint) from public;
revoke all on function public.tourney_state(uuid, text) from public;
revoke all on function public.tourney_claim(uuid, text, bigint) from public;
grant execute on function public.submit_puzzle_stats(uuid, text, int, int) to anon, authenticated;
grant execute on function public.tourney_create(uuid, text, uuid[], text, bigint) to anon, authenticated;
grant execute on function public.tourney_answer(uuid, text, bigint, boolean) to anon, authenticated;
grant execute on function public.tourney_leave(uuid, text, bigint) to anon, authenticated;
grant execute on function public.tourney_state(uuid, text) to anon, authenticated;
grant execute on function public.tourney_claim(uuid, text, bigint) to anon, authenticated;

-- my_news: identical to production plus the 'tourney' key (same signature; grants are kept).
create or replace function public.my_news(p_id uuid, p_secret text, p_mark boolean default false) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.players := player_auth(p_id, p_secret);
  since timestamptz := greatest(coalesce(me.last_played, me.created_at), coalesce(me.news_seen_at, me.created_at), now() - interval '7 days');
  out json;
begin
  out := json_build_object(
    'nudges', coalesce((select json_agg(x order by x.at desc) from (
      select s.id, shown_name(s) as name, s.avatar, s.tier, n.line, n.created_at as at from public.nudges n join public.players s on s.id = n.sender
      where n.receiver = p_id and not n.seen and exists (select 1 from public.friend_links l where l.player = p_id and l.other = s.id and l.status = 'friends')
      order by n.created_at desc limit 10) x), '[]'),
    'passed', coalesce((select json_agg(x order by x.score) from (
      select s.id, shown_name(s) as name, s.avatar, s.tier, s.score,
        exists (select 1 from public.friend_links l where l.player = p_id and l.other = s.id and l.status = 'friends') as friend
      from public.passes ps join public.players s on s.id = ps.passer
      where ps.passed = p_id and ps.at > since and s.score > me.score order by s.score limit 5) x), '[]'),
    'passed_count', (select count(*) from public.passes x join public.players s on s.id = x.passer where x.passed = p_id and x.at > since and s.score > me.score),
    'accepted', coalesce((select json_agg(x order by x.at desc) from (
      select s.id, shown_name(s) as name, s.avatar, s.tier, l.accepted_at as at from public.friend_links l join public.players s on s.id = l.other
      where l.player = p_id and l.status = 'friends' and l.accepted_at is not null and not l.accepted_seen
      order by l.accepted_at desc limit 10) x), '[]'),
    -- Shared puzzles: 'duo' is the one with the newest partner activity (the reminder's line), 'duo_news' how many have any. Each
    -- puzzle has its own seen time per partner (2026-11-18: several at once).
    'duo', (select json_build_object('name', z.name, 'found', z.found, 'placed', z.placed, 'done', z.done) from duo_activity_of(p_id) z
      where z.found + z.placed > 0 or z.done order by z.done desc, z.created_at desc limit 1),
    'duo_news', (select count(*) from duo_activity_of(p_id) z where z.found + z.placed > 0 or z.done),
    'duo_invites', (select count(*) from public.duo_puzzles d where d.b = p_id and d.status = 'pending'),
    -- Who's asking (added 2026-11-17 for the daily reminder: "Sam wants to be friends!").
    'request_names', coalesce((select json_agg(x.name) from (select shown_name(f) as name from public.friend_links l join public.players f on f.id = l.player
      where l.other = p_id and l.status = 'pending' and not exists (select 1 from public.friend_links b where b.player = p_id and b.other = l.player and b.status = 'blocked')
      order by l.created_at desc limit 3) x), '[]'),
    -- Troop Tournaments (1.1.3): invites waiting (and who's hosting the newest), finished ones not yet collected.
    'tourney', (select case when x.invites + x.finished = 0 then null else json_build_object('invites', x.invites, 'finished', x.finished, 'host', x.host) end from (select
        (select count(*) from public.tournament_members m join public.tournaments t on t.id = m.tourney where m.player = p_id and m.status = 'invited' and now() < t.ends_at)::int as invites,
        (select count(*) from public.tournament_members m join public.tournaments t on t.id = m.tourney where m.player = p_id and m.status = 'joined' and not m.claimed and now() >= t.ends_at and t.ends_at > now() - interval '7 days')::int as finished,
        (select shown_name(h) from public.tournament_members m join public.tournaments t on t.id = m.tourney join public.players h on h.id = t.host
          where m.player = p_id and m.status = 'invited' and now() < t.ends_at order by m.invited_at desc limit 1) as host) x),
    'requests', (select count(*) from public.friend_links l where l.other = p_id and l.status = 'pending'
      and not exists (select 1 from public.friend_links b where b.player = p_id and b.other = l.player and b.status = 'blocked')));
  if p_mark then
    update public.nudges set seen = true where receiver = p_id and not seen;
    update public.friend_links set accepted_seen = true where player = p_id and accepted_at is not null and not accepted_seen;
    update public.players set news_seen_at = now() where id = p_id;
  end if;
  return out;
end $$;
