-- Monkey Trubble online leaderboard. Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Players never log in: each install has a random id plus a private secret. The first submit stores a hash of the secret;
-- later submits for that id must present the same secret. Nobody can read or write the table directly, only through
-- the three functions below, which the game calls with the project's public anon key.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.players (
  id          uuid primary key,
  secret_hash text not null,
  name        text not null check (char_length(name) between 2 and 16),
  rating      int  not null default 0 check (rating >= 0),
  score       int  not null default 0 check (score >= 0),
  xp          int  not null default 0 check (xp >= 0),
  streak      int  not null default 0 check (streak >= 0),
  level       int  not null default 1 check (level >= 1),
  tier        text not null default 'bronze',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists players_score_idx on public.players (score desc, updated_at);
-- Added 2026-10-13: the score before the latest submit (players_passed reads it, so the phone never supplies it) and whether the
-- name is hidden after reports (names shown as "Monkey xxxx" until the player picks a new one).
alter table public.players add column if not exists prev_score int;
alter table public.players add column if not exists name_hidden boolean not null default false;
-- Added 2026-10-23 (player cards): the monkey card the player shows as their avatar (a CARD_DATA id, set by set_avatar), their
-- longest daily streak and their best rank so far (both kept by submit_score).
alter table public.players add column if not exists avatar text check (avatar ~ '^[A-Z0-9_]{1,24}$');
alter table public.players add column if not exists best_streak int not null default 0;
alter table public.players add column if not exists best_rank int;
update public.players set best_streak = streak where best_streak < streak;
-- Added 2026-11-17 (friends): when the player last cleared a level (submit_score sets it when their XP goes up, so a rename
-- doesn't count), and their friend code (made by friends_home the first time they open FRIENDS).
alter table public.players add column if not exists last_played timestamptz;
alter table public.players add column if not exists friend_code text unique;
alter table public.players add column if not exists news_seen_at timestamptz;
-- When the player last looked at their shared puzzle (my_news counts the partner's finds and placings since then).
alter table public.players add column if not exists duo_seen_at timestamptz;
-- passes: (passed, passer) when passer's submit moved them past passed (written by submit_score, read by my_news, kept 8 days).
create table if not exists public.passes (
  passed uuid not null references public.players(id) on delete cascade,
  passer uuid not null references public.players(id) on delete cascade,
  at     timestamptz not null default now(),
  primary key (passed, passer)
);
-- The board functions below gained an avatar column (2026-10-23); a return type can't be changed in place.
drop function if exists public.top_players(int);
drop function if exists public.player_rank(uuid);
drop function if exists public.players_passed(uuid, int);

-- Name filter (App Store guideline 1.2): a name is refused if, lowercased with common look-alikes swapped (0->o, 1->i, 3->e,
-- 4->a, 5->s, 7->t, @->a, $->s) and everything but letters removed, it contains one of these, or has "nazi" as a whole word (so
-- Nazir passes). Same rules as NAME_BLOCKLIST / nameAllowed in index.html.
create or replace function public.name_ok(p_name text) returns boolean language sql immutable as $$
  select not exists (
    select 1 from unnest(array['fuck','shit','cunt','bitch','nigg','fagg','faggot','rapist','porn','slut','whore','retard',
      'hitler','kike','chink','twat','wank','pussy','penis','vagin','dildo','jizz','asshole','bastard','motherf'])
      as w(word)
    where regexp_replace(translate(lower(coalesce(p_name, '')), '013457@$', 'oieastas'), '[^a-z]', '', 'g') like '%' || w.word || '%'
  ) and coalesce(p_name, '') !~* '(^|[^a-z])nazis?([^a-z]|$)'
$$;

-- Reports: one per reporter per player. Three different reporters hide the name.
create table if not exists public.name_reports (
  reporter   uuid not null references public.players(id) on delete cascade,
  player     uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (reporter, player)
);
alter table public.name_reports enable row level security;
revoke all on public.name_reports from anon, authenticated;
-- How a name is shown: hidden names become "Monkey" plus four characters of the player's id.
create or replace function public.shown_name(p public.players) returns text language sql stable as $$
  select case when p.name_hidden then 'Monkey ' || upper(left(p.id::text, 4)) else p.name end
$$;

alter table public.players enable row level security;
revoke all on public.players from anon, authenticated;

-- Same tiers as TIERS in index.html.
create or replace function public.tier_for(p_rating int) returns text language sql immutable as $$
  select case when p_rating >= 450 then 'silverback' when p_rating >= 375 then 'diamond' when p_rating >= 300 then 'platinum'
              when p_rating >= 225 then 'gold' when p_rating >= 150 then 'silver' else 'bronze' end
$$;

-- Creates or updates a player's row and returns their rank. Score and tier are worked out here, not trusted from the phone.
-- A level-L clear scores at most 200 x (1 + L/10) x 1.2 (the combo chain bonus, CHAIN_BONUS_MAX in index.html), so a rating above
-- that for the player's level is rejected. (Was 200 until 2026-11-16: it predated the chain bonus and silently froze top players.)
create or replace function public.submit_score(p_id uuid, p_secret text, p_name text, p_rating int, p_xp int, p_streak int, p_level int)
returns table (rank bigint, score int, tier text)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  existing public.players;
  clean_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  new_score int;
  new_rank bigint;
begin
  if char_length(coalesce(p_secret, '')) < 16 then raise exception 'bad secret'; end if;
  if char_length(clean_name) not between 2 and 16 then raise exception 'bad name'; end if;
  if not name_ok(clean_name) then raise exception 'name not allowed'; end if;
  if p_level < 1 or p_level > 100000 or p_rating < 0 or p_xp < 0 or p_streak < 0 or p_streak > 100000 then raise exception 'bad values'; end if;
  if p_rating > 240 * (1 + p_level / 10.0) then raise exception 'rating out of range'; end if;
  new_score := round(p_rating * (1 + least(p_streak, 10) * 0.01));

  select * into existing from public.players where id = p_id;
  if not found then
    insert into public.players (id, secret_hash, name, rating, score, xp, streak, best_streak, level, tier, last_played)
    values (p_id, crypt(p_secret, gen_salt('bf')), clean_name, p_rating, new_score, p_xp, p_streak, p_streak, p_level, tier_for(p_rating), now());
  else
    if existing.secret_hash <> crypt(p_secret, existing.secret_hash) then raise exception 'bad secret'; end if;
    update public.players set name = clean_name, rating = p_rating, score = new_score, prev_score = existing.score,
      xp = greatest(existing.xp, p_xp), streak = p_streak, best_streak = greatest(existing.best_streak, p_streak), level = greatest(existing.level, p_level), tier = tier_for(p_rating),
      name_hidden = existing.name_hidden and existing.name = clean_name, updated_at = now(),
      last_played = case when p_xp > existing.xp then now() else existing.last_played end
    where id = p_id;
    -- A new name starts clean.
    if existing.name <> clean_name then delete from public.name_reports where player = p_id; end if;
    -- Who this submit passed (added 2026-11-17, read by my_news for "Sam passed you").
    if new_score > existing.score then
      insert into public.passes (passed, passer)
      select o.id, p_id from public.players o where o.id <> p_id and o.score > existing.score and o.score < new_score
      order by o.score desc limit 50
      on conflict (passed, passer) do update set at = now();
      if random() < 0.02 then delete from public.passes where at < now() - interval '8 days'; end if;
    end if;
  end if;
  new_rank := (select count(*) + 1 from public.players p where p.score > new_score);
  if new_score > 0 then update public.players set best_rank = least(coalesce(best_rank, new_rank), new_rank) where id = p_id; end if;
  return query select new_rank, new_score, tier_for(p_rating);
end $$;

-- Top of the global board.
create or replace function public.top_players(p_limit int default 50)
returns table (rank bigint, id uuid, name text, score int, rating int, tier text, streak int, xp int, level int, avatar text)
language sql stable security definer set search_path = public as $$
  -- Players at 0 (named, but no level cleared yet) aren't listed until they score (added 2026-10-13).
  select rank() over (order by p.score desc), p.id, shown_name(p), p.score, p.rating, p.tier, p.streak, p.xp, p.level, p.avatar
  from public.players p where p.score > 0 order by p.score desc, p.updated_at limit least(greatest(p_limit, 1), 200)
$$;

-- One player's row and rank (for the pinned "you" row).
create or replace function public.player_rank(p_id uuid)
returns table (rank bigint, id uuid, name text, score int, rating int, tier text, streak int, xp int, level int, avatar text)
language sql stable security definer set search_path = public as $$
  select (select count(*) + 1 from public.players o where o.score > p.score), p.id, shown_name(p), p.score, p.rating, p.tier, p.streak, p.xp, p.level, p.avatar
  from public.players p where p.id = p_id
$$;

revoke all on function public.submit_score(uuid, text, text, int, int, int, int) from public;
revoke all on function public.top_players(int) from public;
revoke all on function public.player_rank(uuid) from public;
grant execute on function public.submit_score(uuid, text, text, int, int, int, int) to anon, authenticated;
grant execute on function public.top_players(int) to anon, authenticated;
grant execute on function public.player_rank(uuid) to anon, authenticated;

-- Added 2026-10-13. Re-running the whole file is safe.
-- Players the latest submit passed: those now behind the player who were ahead before (previous score < theirs < current score),
-- nearest first, up to p_limit, plus how many were passed in all. Both scores are the server's own (prev_score is kept by
-- submit_score), so the result is bounded by a real score change. Drives the climb screen between levels.
drop function if exists public.players_passed(uuid, int, int);
create or replace function public.players_passed(p_id uuid, p_limit int default 5)
returns table (rank bigint, id uuid, name text, score int, rating int, tier text, streak int, xp int, level int, avatar text, passed bigint)
language sql stable security definer set search_path = public as $$
  with me as (select p.score, p.prev_score from public.players p where p.id = p_id and p.prev_score is not null),
  passed as (select p.* from public.players p, me where p.id <> p_id and p.score > me.prev_score and p.score < me.score)
  select (select count(*) + 1 from public.players o where o.score > q.score), q.id, shown_name(q), q.score, q.rating, q.tier, q.streak, q.xp, q.level, q.avatar,
    (select count(*) from passed)
  from passed q order by q.score desc, q.updated_at limit least(greatest(p_limit, 1), 20)
$$;

-- Report a player's name. The reporter proves who they are with their secret; three different reporters hide the name.
create or replace function public.report_player(p_reporter uuid, p_secret text, p_player uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare me public.players;
begin
  select * into me from public.players where id = p_reporter;
  if not found or me.secret_hash <> crypt(p_secret, me.secret_hash) then raise exception 'bad secret'; end if;
  if p_reporter = p_player then return; end if;
  insert into public.name_reports (reporter, player) values (p_reporter, p_player) on conflict do nothing;
  update public.players set name_hidden = true
  where id = p_player and (select count(*) from public.name_reports r where r.player = p_player) >= 3;
end $$;

revoke all on function public.players_passed(uuid, int) from public;
revoke all on function public.report_player(uuid, text, uuid) from public;
grant execute on function public.players_passed(uuid, int) to anon, authenticated;
grant execute on function public.report_player(uuid, text, uuid) to anon, authenticated;

-- Added 2026-10-14: world records, the fastest Normal clear of each level. Every player gets the same board for a level (it is
-- seeded from the level number), so times compare fairly. p_deal is the game's DEAL_VERSION: it is bumped whenever the dealing
-- changes, which starts every level's record afresh instead of leaving one set on a different board.
create table if not exists public.level_records (
  level   int  not null check (level >= 1),
  deal    int  not null check (deal >= 1),
  player  uuid not null references public.players(id) on delete cascade,
  time_ms int  not null check (time_ms > 0),
  set_at  timestamptz not null default now(),
  primary key (level, deal)
);
alter table public.level_records enable row level security;

-- Records a clear and returns the level's record afterwards: the holder's shown name and id, the time, whether this clear set it
-- (beat), and the record it replaced. The player must exist (submit_score runs first) and must already have cleared the level
-- (their stored level is past it). Under 8 seconds is rejected: a level is 21 pairs.
create or replace function public.submit_time(p_id uuid, p_secret text, p_level int, p_deal int, p_time_ms int)
returns table (holder text, holder_id uuid, time_ms int, beat boolean, previous_holder text, previous_ms int)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  me public.players;
  prev public.level_records;
  prev_name text;
  did_beat boolean := false;
begin
  if p_level < 1 or p_level > 100000 or p_deal < 1 or p_time_ms < 8000 or p_time_ms > 86400000 then raise exception 'bad values'; end if;
  select * into me from public.players where id = p_id;
  if not found or me.secret_hash <> crypt(coalesce(p_secret, ''), me.secret_hash) then raise exception 'bad secret'; end if;
  if me.level <= p_level then raise exception 'level not cleared'; end if;
  select * into prev from public.level_records r where r.level = p_level and r.deal = p_deal for update;
  if not found then
    insert into public.level_records (level, deal, player, time_ms) values (p_level, p_deal, p_id, p_time_ms);
    did_beat := true;
  elsif p_time_ms < prev.time_ms then
    select shown_name(p) into prev_name from public.players p where p.id = prev.player;
    update public.level_records set player = p_id, time_ms = p_time_ms, set_at = now() where level = p_level and deal = p_deal;
    did_beat := true;
  end if;
  return query select shown_name(p), p.id, r.time_ms, did_beat, case when did_beat then prev_name end, case when did_beat then prev.time_ms end
    from public.level_records r join public.players p on p.id = r.player where r.level = p_level and r.deal = p_deal;
end $$;

-- The current record for a level (no row if nobody has set one yet).
create or replace function public.level_record(p_level int, p_deal int)
returns table (holder text, holder_id uuid, time_ms int)
language sql stable security definer set search_path = public as $$
  select shown_name(p), p.id, r.time_ms from public.level_records r join public.players p on p.id = r.player
  where r.level = p_level and r.deal = p_deal
$$;

revoke all on function public.submit_time(uuid, text, int, int, int) from public;
revoke all on function public.level_record(int, int) from public;
grant execute on function public.submit_time(uuid, text, int, int, int) to anon, authenticated;
grant execute on function public.level_record(int, int) to anon, authenticated;

-- Added 2026-10-23: player cards. Tapping a leaderboard row opens that player's card (their avatar monkey and stats).
-- set_avatar: the player picks one of their unlocked monkey cards (null clears it). The id is only checked for shape; the game
-- shows the default card for an id it doesn't know.
create or replace function public.set_avatar(p_id uuid, p_secret text, p_avatar text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare me public.players;
begin
  if p_avatar is not null and p_avatar !~ '^[A-Z0-9_]{1,24}$' then raise exception 'bad avatar'; end if;
  select * into me from public.players where id = p_id;
  if not found or me.secret_hash <> crypt(coalesce(p_secret, ''), me.secret_hash) then raise exception 'bad secret'; end if;
  update public.players set avatar = p_avatar where id = p_id;
end $$;

-- Everything a player card shows: the board row plus best streak, best rank, world records held and when they joined.
create or replace function public.player_profile(p_id uuid)
returns table (rank bigint, id uuid, name text, score int, rating int, tier text, streak int, best_streak int, best_rank int, xp int,
  level int, avatar text, records bigint, joined timestamptz)
language sql stable security definer set search_path = public as $$
  select (select count(*) + 1 from public.players o where o.score > p.score), p.id, shown_name(p), p.score, p.rating, p.tier, p.streak,
    greatest(p.best_streak, p.streak), p.best_rank, p.xp, p.level, p.avatar, (select count(*) from public.level_records r where r.player = p.id), p.created_at
  from public.players p where p.id = p_id
$$;

revoke all on function public.set_avatar(uuid, text, text) from public;
revoke all on function public.player_profile(uuid) from public;
grant execute on function public.set_avatar(uuid, text, text) to anon, authenticated;
grant execute on function public.player_profile(uuid) to anon, authenticated;

-- ===================================================================================================================================
-- Friends (added 2026-11-17). Friend codes only: no search by name, no contacts. Entering a code sends a request, and the other
-- player accepts it in the game. Nudges are a fixed set of lines: the game holds the words, the server stores only the line number,
-- so no player ever types a message to another. Everything goes through the functions below, each checking the caller's secret.
-- friend_links has one row per direction: (player, other, 'friends') both ways once accepted, (player, other, 'pending') for a request
-- player sent, (player, other, 'blocked') when player blocked other. Deleting a player cascades their links, nudges and passes.
create table if not exists public.friend_links (
  player     uuid not null references public.players(id) on delete cascade,
  other      uuid not null references public.players(id) on delete cascade,
  status     text not null check (status in ('pending', 'friends', 'blocked')),
  created_at timestamptz not null default now(),
  primary key (player, other),
  check (player <> other)
);
create index if not exists friend_links_other_idx on public.friend_links (other, status);
-- Added 2026-11-17: when the other player accepted this row's request, and whether the requester has seen that in their news.
alter table public.friend_links add column if not exists accepted_at timestamptz;
alter table public.friend_links add column if not exists accepted_seen boolean not null default false;
create table if not exists public.nudges (
  id         bigserial primary key,
  sender     uuid not null references public.players(id) on delete cascade,
  receiver   uuid not null references public.players(id) on delete cascade,
  line       int  not null check (line between 0 and 31),
  created_at timestamptz not null default now(),
  seen       boolean not null default false
);
create index if not exists nudges_receiver_idx on public.nudges (receiver, seen);
create index if not exists nudges_sender_idx on public.nudges (sender, receiver, created_at desc);
alter table public.friend_links enable row level security;
alter table public.nudges enable row level security;
alter table public.passes enable row level security;
revoke all on public.friend_links from anon, authenticated;
revoke all on public.nudges from anon, authenticated;
revoke all on public.passes from anon, authenticated;

-- The caller's row, or an error if the secret doesn't match. Internal: not granted to the app.
create or replace function public.player_auth(p_id uuid, p_secret text) returns public.players
language plpgsql stable security definer set search_path = public, extensions as $$
declare me public.players;
begin
  select * into me from public.players where id = p_id;
  if not found or me.secret_hash <> crypt(coalesce(p_secret, ''), me.secret_hash) then raise exception 'bad secret'; end if;
  return me;
end $$;
revoke all on function public.player_auth(uuid, text) from public, anon, authenticated;

-- A friend's board row as JSON (the same fields as top_players, plus hours since they last played and whether p_me nudged them lately).
create or replace function public.friend_json(p public.players, p_me uuid) returns json language sql stable security definer set search_path = public as $$
  select json_build_object('rank', (select count(*) + 1 from public.players o where o.score > p.score), 'id', p.id, 'name', shown_name(p),
    'score', p.score, 'rating', p.rating, 'tier', p.tier, 'streak', p.streak, 'xp', p.xp, 'level', p.level, 'avatar', p.avatar,
    'idle_hours', case when p.last_played is null then null else floor(extract(epoch from now() - p.last_played) / 3600)::int end,
    'nudged', exists (select 1 from public.nudges n where n.sender = p_me and n.receiver = p.id and n.created_at > now() - interval '20 hours'))
$$;
revoke all on function public.friend_json(public.players, uuid) from public, anon, authenticated;

-- Everything the FRIENDS tab shows: your code (made here the first time: 6 characters with no 0/O/1/I/L look-alikes), your friends
-- (you included) with board rows, requests to you, and requests you've sent.
create or replace function public.friends_home(p_id uuid, p_secret text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.players := player_auth(p_id, p_secret);
  abc constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code text := me.friend_code;
begin
  for i in 1..20 loop
    exit when code is not null;
    code := (select string_agg(substr(abc, 1 + get_byte(b, k) % length(abc), 1), '' order by k)
             from (select gen_random_bytes(6) as b) x, generate_series(0, 5) k);
    begin update public.players set friend_code = code where id = p_id;
    exception when unique_violation then code := null; end;
  end loop;
  return json_build_object('code', code,
    'friends', coalesce((select json_agg(friend_json(p, p_id) order by p.score desc, p.updated_at) from public.players p
      where p.id = p_id or p.id in (select other from public.friend_links where player = p_id and status = 'friends')), '[]'),
    'incoming', coalesce((select json_agg(json_build_object('id', p.id, 'name', shown_name(p), 'avatar', p.avatar, 'tier', p.tier) order by l.created_at desc)
      from public.friend_links l join public.players p on p.id = l.player
      where l.other = p_id and l.status = 'pending'
        and not exists (select 1 from public.friend_links b where b.player = p_id and b.other = l.player and b.status = 'blocked')), '[]'),
    'outgoing', coalesce((select json_agg(json_build_object('id', p.id, 'name', shown_name(p), 'avatar', p.avatar, 'tier', p.tier) order by l.created_at desc)
      from public.friend_links l join public.players p on p.id = l.other where l.player = p_id and l.status = 'pending'), '[]'));
end $$;

-- A friend request from p_me to them (shared by add_friend and add_friend_id). Returns {status, name}: 'friends' (they'd already asked
-- you, or you were friends), 'sent', 'self' or 'full' (50 friends, or 60 friends plus open requests). Someone who blocked you just sees
-- 'sent'. Internal: not granted to the app.
create or replace function public.friend_request(p_me uuid, them public.players) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  if them.id = p_me then return json_build_object('status', 'self'); end if;
  if exists (select 1 from public.friend_links where player = them.id and other = p_me and status = 'blocked') then
    return json_build_object('status', 'sent', 'name', shown_name(them)); end if;
  delete from public.friend_links where player = p_me and other = them.id and status = 'blocked';
  if exists (select 1 from public.friend_links where player = p_me and other = them.id and status = 'friends') then
    return json_build_object('status', 'friends', 'name', shown_name(them)); end if;
  if (select count(*) from public.friend_links where player = p_me and status = 'friends') >= 50
     or (select count(*) from public.friend_links where player = p_me and status in ('friends', 'pending')) >= 60 then
    return json_build_object('status', 'full'); end if;
  if exists (select 1 from public.friend_links where player = them.id and other = p_me and status = 'pending') then
    if (select count(*) from public.friend_links where player = them.id and status = 'friends') >= 50 then return json_build_object('status', 'full'); end if;
    update public.friend_links set status = 'friends', accepted_at = now() where player = them.id and other = p_me;
    insert into public.friend_links (player, other, status) values (p_me, them.id, 'friends')
      on conflict (player, other) do update set status = 'friends';
    return json_build_object('status', 'friends', 'name', shown_name(them));
  end if;
  insert into public.friend_links (player, other, status) values (p_me, them.id, 'pending') on conflict do nothing;
  return json_build_object('status', 'sent', 'name', shown_name(them));
end $$;
revoke all on function public.friend_request(uuid, public.players) from public, anon, authenticated;

-- Add a friend by code (typed, or from a shared link or QR). Also 'no_code' when nobody has it.
create or replace function public.add_friend(p_id uuid, p_secret text, p_code text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.players := player_auth(p_id, p_secret);
  them public.players;
begin
  select * into them from public.players where friend_code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if not found then return json_build_object('status', 'no_code'); end if;
  return friend_request(p_id, them);
end $$;

-- Add a friend from their player card on the board (a request they still have to accept).
create or replace function public.add_friend_id(p_id uuid, p_secret text, p_other uuid) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.players := player_auth(p_id, p_secret);
  them public.players;
begin
  select * into them from public.players where id = p_other;
  if not found then return json_build_object('status', 'no_code'); end if;
  return friend_request(p_id, them);
end $$;

-- The board row for a friend code, so a shared link or QR opens that player's card (the same public details as the leaderboard).
create or replace function public.player_by_code(p_code text)
returns table (rank bigint, id uuid, name text, score int, rating int, tier text, streak int, xp int, level int, avatar text)
language sql stable security definer set search_path = public as $$
  select (select count(*) + 1 from public.players o where o.score > p.score), p.id, shown_name(p), p.score, p.rating, p.tier, p.streak, p.xp, p.level, p.avatar
  from public.players p where p.friend_code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
$$;
revoke all on function public.add_friend_id(uuid, text, uuid) from public;
revoke all on function public.player_by_code(text) from public;
grant execute on function public.add_friend_id(uuid, text, uuid) to anon, authenticated;
grant execute on function public.player_by_code(text) to anon, authenticated;

-- Accept or decline a request someone sent you.
create or replace function public.answer_friend(p_id uuid, p_secret text, p_other uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  if not exists (select 1 from public.friend_links where player = p_other and other = p_id and status = 'pending') then return; end if;
  if not p_accept then delete from public.friend_links where player = p_other and other = p_id; return; end if;
  if (select count(*) from public.friend_links where player = p_id and status = 'friends') >= 50 then raise exception 'full'; end if;
  update public.friend_links set status = 'friends', accepted_at = now() where player = p_other and other = p_id;
  insert into public.friend_links (player, other, status) values (p_id, p_other, 'friends')
    on conflict (player, other) do update set status = 'friends';
end $$;

-- Unfriend (or cancel a request you sent). Either side can; both directions go.
create or replace function public.remove_friend(p_id uuid, p_secret text, p_other uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  delete from public.friend_links where (player = p_id and other = p_other and status <> 'blocked')
    or (player = p_other and other = p_id and status <> 'blocked');
end $$;

-- Block: ends the friendship or request, and they can't send you requests or nudges again (they aren't told). Their unread nudges go.
create or replace function public.block_friend(p_id uuid, p_secret text, p_other uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  if p_other = p_id then return; end if;
  delete from public.friend_links where (player = p_id and other = p_other) or (player = p_other and other = p_id and status <> 'blocked');
  insert into public.friend_links (player, other, status) values (p_id, p_other, 'blocked');
  update public.nudges set seen = true where sender = p_other and receiver = p_id and not seen;
end $$;

-- Nudge a friend with one of the game's fixed lines. Returns 'sent', 'already' (you nudged them in the last 20 hours), 'played' (they
-- cleared a level in the last 16 hours, so there's nothing to nudge about) or 'not_friends'.
create or replace function public.nudge(p_id uuid, p_secret text, p_friend uuid, p_line int) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  if p_line not between 0 and 31 then raise exception 'bad line'; end if;
  if not exists (select 1 from public.friend_links where player = p_id and other = p_friend and status = 'friends')
     or not exists (select 1 from public.friend_links where player = p_friend and other = p_id and status = 'friends') then return 'not_friends'; end if;
  if exists (select 1 from public.nudges where sender = p_id and receiver = p_friend and created_at > now() - interval '20 hours') then return 'already'; end if;
  if exists (select 1 from public.players where id = p_friend and last_played > now() - interval '16 hours') then return 'played'; end if;
  insert into public.nudges (sender, receiver, line) values (p_id, p_friend, p_line);
  return 'sent';
end $$;

-- News for the home badge, the FRIENDS tab and (later) the daily reminder: unread nudges from friends, players who passed you since you
-- last played or looked (and are still ahead), friends who accepted your requests, and how many friend requests wait. p_mark marks the nudges read and the passes seen.
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
    'requests', (select count(*) from public.friend_links l where l.other = p_id and l.status = 'pending'
      and not exists (select 1 from public.friend_links b where b.player = p_id and b.other = l.player and b.status = 'blocked')));
  if p_mark then
    update public.nudges set seen = true where receiver = p_id and not seen;
    update public.friend_links set accepted_seen = true where player = p_id and accepted_at is not null and not accepted_seen;
    update public.players set news_seen_at = now() where id = p_id;
  end if;
  return out;
end $$;

revoke all on function public.friends_home(uuid, text) from public;
revoke all on function public.add_friend(uuid, text, text) from public;
revoke all on function public.answer_friend(uuid, text, uuid, boolean) from public;
revoke all on function public.remove_friend(uuid, text, uuid) from public;
revoke all on function public.block_friend(uuid, text, uuid) from public;
revoke all on function public.nudge(uuid, text, uuid, int) from public;
revoke all on function public.my_news(uuid, text, boolean) from public;
grant execute on function public.friends_home(uuid, text) to anon, authenticated;
grant execute on function public.add_friend(uuid, text, text) to anon, authenticated;
grant execute on function public.answer_friend(uuid, text, uuid, boolean) to anon, authenticated;
grant execute on function public.remove_friend(uuid, text, uuid) to anon, authenticated;
grant execute on function public.block_friend(uuid, text, uuid) to anon, authenticated;
grant execute on function public.nudge(uuid, text, uuid, int) to anon, authenticated;
grant execute on function public.my_news(uuid, text, boolean) to anon, authenticated;

-- ===================================================================================================================================
-- Shared Puzzles (added 2026-11-17, Paul). Two friends build one jigsaw together: a = the player who invited, b = the friend. Clearing a
-- Normal level can drop a shared piece (an extra, on top of the player's own puzzle pieces); either partner can place any found piece.
-- Up to 5 open shared puzzles per player, one per pair of friends (2026-11-18; it was one per player). Open = active, or a pending invite
-- you sent; invites waiting for you don't count until you accept. When all 12 are placed it's done, and each partner claims the reward once.
create table if not exists public.duo_puzzles (
  id         bigserial primary key,
  a          uuid not null references public.players(id) on delete cascade,
  b          uuid not null references public.players(id) on delete cascade,
  art        text not null check (art ~ '^[a-z0-9-]{1,32}$'),
  status     text not null default 'pending' check (status in ('pending', 'active', 'done', 'left')),
  a_claimed  boolean not null default false,
  b_claimed  boolean not null default false,
  created_at timestamptz not null default now(),
  done_at    timestamptz,
  check (a <> b)
);
create index if not exists duo_puzzles_a_idx on public.duo_puzzles (a, status);
create index if not exists duo_puzzles_b_idx on public.duo_puzzles (b, status);
create table if not exists public.duo_pieces (
  duo         bigint not null references public.duo_puzzles(id) on delete cascade,
  piece       smallint not null check (piece between 0 and 11),
  found_by    uuid references public.players(id) on delete set null,
  found_level int not null,
  found_at    timestamptz not null default now(),
  placed_by   uuid references public.players(id) on delete set null,
  placed_at   timestamptz,
  primary key (duo, piece)
);
create unique index if not exists duo_pieces_level_idx on public.duo_pieces (duo, found_by, found_level);
-- When each partner last looked at this puzzle (its own "new activity" badge; players.duo_seen_at covered the single puzzle before).
alter table public.duo_puzzles add column if not exists a_seen_at timestamptz;
alter table public.duo_puzzles add column if not exists b_seen_at timestamptz;
alter table public.duo_puzzles enable row level security;
alter table public.duo_pieces enable row level security;
revoke all on public.duo_puzzles from anon, authenticated;
revoke all on public.duo_pieces from anon, authenticated;

-- The player's shared puzzle: the open one (pending or active), else a finished one they haven't claimed, else the latest finished
-- one from the last 3 days (so the finished picture stays to look at and share). Internal.
create or replace function public.duo_current(p_me uuid) returns public.duo_puzzles language sql stable security definer set search_path = public as $$
  select d.* from public.duo_puzzles d where (d.a = p_me or d.b = p_me)
    and (d.status in ('pending', 'active') or d.status = 'done' and (not (case when d.a = p_me then d.a_claimed else d.b_claimed end) or d.done_at > now() - interval '3 days'))
  order by (d.status in ('pending', 'active')) desc, d.created_at desc limit 1
$$;
revoke all on function public.duo_current(uuid) from public, anon, authenticated;

-- Open shared puzzles a player has: active, or pending invites they sent (the 5 cap). Internal.
create or replace function public.duo_open_count(p_me uuid) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.duo_puzzles where (a = p_me and status in ('pending', 'active')) or (b = p_me and status = 'active')
$$;
revoke all on function public.duo_open_count(uuid) from public, anon, authenticated;

-- Each of a player's active or unclaimed-finished shared puzzles, with the partner's finds and placings since the player last looked. Internal.
create or replace function public.duo_activity_of(p_me uuid) returns table(id bigint, name text, found int, placed int, done boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select d.id, shown_name(o), 
    (select count(*)::int from public.duo_pieces x where x.duo = d.id and x.found_by = o.id and x.found_at > coalesce(case when d.a = p_me then d.a_seen_at else d.b_seen_at end, d.created_at)),
    (select count(*)::int from public.duo_pieces x where x.duo = d.id and x.placed_by = o.id and x.placed_at > coalesce(case when d.a = p_me then d.a_seen_at else d.b_seen_at end, d.created_at)),
    d.status = 'done' and not (case when d.a = p_me then d.a_claimed else d.b_claimed end), d.created_at
  from public.duo_puzzles d join public.players o on o.id = case when d.a = p_me then d.b else d.a end
  where (d.a = p_me or d.b = p_me) and (d.status = 'active' or d.status = 'done' and not (case when d.a = p_me then d.a_claimed else d.b_claimed end))
$$;
revoke all on function public.duo_activity_of(uuid) from public, anon, authenticated;

-- Everything the SHARED view shows for one puzzle (p_duo, or the latest when null or not yours): the puzzle (art, status, whether you
-- started it, whether you've claimed it), your partner, the pieces (who found and placed each), invites waiting for you, and 'duos', the
-- list of all your shared puzzles (open, unclaimed, or finished in the last 3 days) with each one's new-activity count. Marks the shown
-- puzzle's partner activity seen.
create or replace function public.duo_state(p_id uuid, p_secret text, p_duo bigint) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.players := player_auth(p_id, p_secret);
  d public.duo_puzzles;
  o public.players;
  out json;
begin
  if p_duo is not null then select * into d from public.duo_puzzles where id = p_duo and (a = p_id or b = p_id) and status <> 'left'; end if;
  if d.id is null then d := duo_current(p_id); end if;
  if d.id is not null then select * into o from public.players where id = case when d.a = p_id then d.b else d.a end; end if;
  out := json_build_object(
    'duo', case when d.id is null then null else json_build_object('id', d.id, 'art', d.art, 'status', d.status, 'mine', d.a = p_id,
      'claimed', case when d.a = p_id then d.a_claimed else d.b_claimed end,
      'partner', json_build_object('id', o.id, 'name', shown_name(o), 'avatar', o.avatar, 'tier', o.tier)) end,
    'pieces', coalesce((select json_agg(json_build_object('piece', x.piece, 'found_by', x.found_by, 'placed', x.placed_by is not null, 'placed_by', x.placed_by) order by x.piece)
      from public.duo_pieces x where x.duo = d.id), '[]'),
    'invites', coalesce((select json_agg(json_build_object('id', i.id, 'art', i.art, 'from', json_build_object('id', f.id, 'name', shown_name(f), 'avatar', f.avatar, 'tier', f.tier)) order by i.created_at desc)
      from public.duo_puzzles i join public.players f on f.id = i.a where i.b = p_id and i.status = 'pending'), '[]'),
    'duos', coalesce((select json_agg(json_build_object('id', l.id, 'art', l.art, 'status', l.status, 'mine', l.a = p_id,
        'partner', json_build_object('id', f.id, 'name', shown_name(f), 'avatar', f.avatar, 'tier', f.tier),
        'placed', (select count(*) from public.duo_pieces x where x.duo = l.id and x.placed_by is not null),
        'news', (select count(*) from public.duo_pieces x where x.duo = l.id and (x.found_by = f.id and x.found_at > l.seen or x.placed_by = f.id and x.placed_at > l.seen))
          + case when l.status = 'done' and not l.claimed then 1 else 0 end) order by l.status = 'done', l.created_at)
      from (select y.*, coalesce(case when y.a = p_id then y.a_seen_at else y.b_seen_at end, y.created_at) as seen,
              case when y.a = p_id then y.a_claimed else y.b_claimed end as claimed
            from public.duo_puzzles y where (y.a = p_id and y.status in ('pending', 'active')) or (y.b = p_id and y.status = 'active')
              or ((y.a = p_id or y.b = p_id) and y.status = 'done' and (not (case when y.a = p_id then y.a_claimed else y.b_claimed end) or y.done_at > now() - interval '3 days'))) l
      join public.players f on f.id = case when l.a = p_id then l.b else l.a end), '[]'));
  if d.id is not null then
    update public.duo_puzzles set a_seen_at = case when a = p_id then now() else a_seen_at end, b_seen_at = case when b = p_id then now() else b_seen_at end where id = d.id;
  end if;
  update public.players set duo_seen_at = now() where id = p_id;
  return out;
end $$;

-- The 1.1 app's call: the latest puzzle.
create or replace function public.duo_state(p_id uuid, p_secret text) returns json
language sql security definer set search_path = public, extensions as $$ select public.duo_state(p_id, p_secret, null::bigint) $$;

-- Invite a friend to a shared puzzle. Returns 'sent', 'busy' (you two already have one open), 'full' (you or they have 5 open) or 'not_friends'.
create or replace function public.duo_invite(p_id uuid, p_secret text, p_friend uuid, p_art text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  if not exists (select 1 from public.friend_links where player = p_id and other = p_friend and status = 'friends')
     or not exists (select 1 from public.friend_links where player = p_friend and other = p_id and status = 'friends') then return 'not_friends'; end if;
  if exists (select 1 from public.duo_puzzles where (a = p_id and b = p_friend or a = p_friend and b = p_id) and status in ('pending', 'active')) then return 'busy'; end if;
  if duo_open_count(p_id) >= 5 or duo_open_count(p_friend) >= 5 then return 'full'; end if;
  insert into public.duo_puzzles (a, b, art) values (p_id, p_friend, coalesce(nullif(p_art, ''), 'together-1'));
  return 'sent';
end $$;

-- Accept or decline an invite to you.
create or replace function public.duo_answer(p_id uuid, p_secret text, p_duo bigint, p_accept boolean) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  if not exists (select 1 from public.duo_puzzles where id = p_duo and b = p_id and status = 'pending') then return 'gone'; end if;
  if not p_accept then delete from public.duo_puzzles where id = p_duo; return 'declined'; end if;
  if duo_open_count(p_id) >= 5 then return 'full'; end if;
  update public.duo_puzzles set status = 'active' where id = p_duo;
  return 'active';
end $$;

-- A Normal clear of p_level found a shared piece: the server picks one of the player's active shared puzzles at random (one with a free
-- slot), and a free piece in it. One per player per level across their active puzzles, levels the player has reached, 6 a day in all.
-- Returns {duo, piece, partner}, or null (nothing found: limits, or every puzzle is full). Internal.
create or replace function public.duo_pick(p_id uuid, p_level int) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.players;
  d public.duo_puzzles;
  free int[];
  pick int;
begin
  select * into me from public.players where id = p_id;
  if me.id is null or p_level < 1 or p_level > me.level then return null; end if;
  if exists (select 1 from public.duo_pieces x join public.duo_puzzles y on y.id = x.duo where y.status = 'active' and x.found_by = p_id and x.found_level = p_level) then return null; end if;
  if (select count(*) from public.duo_pieces where found_by = p_id and found_at > now() - interval '1 day') >= 6 then return null; end if;
  select * into d from public.duo_puzzles y where (y.a = p_id or y.b = p_id) and y.status = 'active'
    and (select count(*) from public.duo_pieces x where x.duo = y.id) < 12 order by random() limit 1;
  if d.id is null then return null; end if;
  free := array(select g from generate_series(0, 11) g where not exists (select 1 from public.duo_pieces x where x.duo = d.id and x.piece = g));
  if cardinality(free) = 0 then return null; end if;
  pick := free[1 + floor(random() * cardinality(free))::int];
  insert into public.duo_pieces (duo, piece, found_by, found_level) values (d.id, pick, p_id, p_level) on conflict do nothing;
  if not found then return null; end if;
  return json_build_object('duo', d.id, 'art', d.art, 'piece', pick,
    'partner', (select json_build_object('id', o.id, 'name', shown_name(o), 'avatar', o.avatar) from public.players o where o.id = case when d.a = p_id then d.b else d.a end));
end $$;
revoke all on function public.duo_pick(uuid, int) from public, anon, authenticated;

-- The 1.1 app's call: just the piece number.
create or replace function public.duo_find(p_id uuid, p_secret text, p_level int) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  return (duo_pick(p_id, p_level)->>'piece')::int;
end $$;

-- 1.1.1 on (p_v = 2): which puzzle it went to, too.
create or replace function public.duo_find(p_id uuid, p_secret text, p_level int, p_v int) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  return duo_pick(p_id, p_level);
end $$;

-- Place a found piece of shared puzzle p_duo (either partner). Returns {placed, done}; the 12th placing finishes the puzzle.
create or replace function public.duo_place(p_id uuid, p_secret text, p_duo bigint, p_piece int) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.players := player_auth(p_id, p_secret);
  d public.duo_puzzles;
begin
  select * into d from public.duo_puzzles where id = p_duo and (a = p_id or b = p_id) and status = 'active';
  if d.id is null then return json_build_object('placed', false, 'done', false); end if;
  update public.duo_pieces set placed_by = p_id, placed_at = now() where duo = d.id and piece = p_piece and placed_by is null;
  if (select count(*) from public.duo_pieces where duo = d.id and placed_by is not null) >= 12 then
    update public.duo_puzzles set status = 'done', done_at = now() where id = d.id;
    return json_build_object('placed', true, 'done', true);
  end if;
  return json_build_object('placed', true, 'done', false);
end $$;

-- The 1.1 app's call: the latest puzzle (the one its SHARED view shows).
create or replace function public.duo_place(p_id uuid, p_secret text, p_piece int) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  return public.duo_place(p_id, p_secret, (duo_current(p_id)).id, p_piece);
end $$;

-- Claim a finished shared puzzle's reward: true the first time for each partner, false after.
create or replace function public.duo_claim(p_id uuid, p_secret text, p_duo bigint) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  update public.duo_puzzles set a_claimed = true where id = p_duo and a = p_id and status = 'done' and not a_claimed;
  if found then return true; end if;
  update public.duo_puzzles set b_claimed = true where id = p_duo and b = p_id and status = 'done' and not b_claimed;
  return found;
end $$;

-- Leave (or cancel) one open shared puzzle; it ends for both. Found pieces stay in the history.
create or replace function public.duo_leave(p_id uuid, p_secret text, p_duo bigint) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  update public.duo_puzzles set status = 'left' where id = p_duo and (a = p_id or b = p_id) and status in ('pending', 'active');
end $$;

-- The 1.1 app's call: leaves the latest open one (the one its SHARED view shows), not all of them.
create or replace function public.duo_leave(p_id uuid, p_secret text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  update public.duo_puzzles set status = 'left' where id = (duo_current(p_id)).id and status in ('pending', 'active');
end $$;

revoke all on function public.duo_state(uuid, text) from public;
revoke all on function public.duo_invite(uuid, text, uuid, text) from public;
revoke all on function public.duo_answer(uuid, text, bigint, boolean) from public;
revoke all on function public.duo_find(uuid, text, int) from public;
revoke all on function public.duo_place(uuid, text, int) from public;
revoke all on function public.duo_claim(uuid, text, bigint) from public;
revoke all on function public.duo_leave(uuid, text) from public;
revoke all on function public.duo_state(uuid, text, bigint) from public;
revoke all on function public.duo_find(uuid, text, int, int) from public;
revoke all on function public.duo_place(uuid, text, bigint, int) from public;
revoke all on function public.duo_leave(uuid, text, bigint) from public;
grant execute on function public.duo_state(uuid, text) to anon, authenticated;
grant execute on function public.duo_invite(uuid, text, uuid, text) to anon, authenticated;
grant execute on function public.duo_answer(uuid, text, bigint, boolean) to anon, authenticated;
grant execute on function public.duo_find(uuid, text, int) to anon, authenticated;
grant execute on function public.duo_place(uuid, text, int) to anon, authenticated;
grant execute on function public.duo_claim(uuid, text, bigint) to anon, authenticated;
grant execute on function public.duo_leave(uuid, text) to anon, authenticated;
grant execute on function public.duo_state(uuid, text, bigint) to anon, authenticated;
grant execute on function public.duo_find(uuid, text, int, int) to anon, authenticated;
grant execute on function public.duo_place(uuid, text, bigint, int) to anon, authenticated;
grant execute on function public.duo_leave(uuid, text, bigint) to anon, authenticated;
