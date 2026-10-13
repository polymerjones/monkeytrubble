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
-- A level-L clear scores at most 200 x (1 + L/10), so a rating above that for the player's level is rejected.
create or replace function public.submit_score(p_id uuid, p_secret text, p_name text, p_rating int, p_xp int, p_streak int, p_level int)
returns table (rank bigint, score int, tier text)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  existing public.players;
  clean_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  new_score int;
begin
  if char_length(coalesce(p_secret, '')) < 16 then raise exception 'bad secret'; end if;
  if char_length(clean_name) not between 2 and 16 then raise exception 'bad name'; end if;
  if not name_ok(clean_name) then raise exception 'name not allowed'; end if;
  if p_level < 1 or p_level > 100000 or p_rating < 0 or p_xp < 0 or p_streak < 0 or p_streak > 100000 then raise exception 'bad values'; end if;
  if p_rating > 200 * (1 + p_level / 10.0) then raise exception 'rating out of range'; end if;
  new_score := round(p_rating * (1 + least(p_streak, 10) * 0.01));

  select * into existing from public.players where id = p_id;
  if not found then
    insert into public.players (id, secret_hash, name, rating, score, xp, streak, level, tier)
    values (p_id, crypt(p_secret, gen_salt('bf')), clean_name, p_rating, new_score, p_xp, p_streak, p_level, tier_for(p_rating));
  else
    if existing.secret_hash <> crypt(p_secret, existing.secret_hash) then raise exception 'bad secret'; end if;
    update public.players set name = clean_name, rating = p_rating, score = new_score, prev_score = existing.score,
      xp = greatest(existing.xp, p_xp), streak = p_streak, level = greatest(existing.level, p_level), tier = tier_for(p_rating),
      name_hidden = existing.name_hidden and existing.name = clean_name, updated_at = now()
    where id = p_id;
    -- A new name starts clean.
    if existing.name <> clean_name then delete from public.name_reports where player = p_id; end if;
  end if;
  return query select (select count(*) + 1 from public.players p where p.score > new_score), new_score, tier_for(p_rating);
end $$;

-- Top of the global board.
create or replace function public.top_players(p_limit int default 50)
returns table (rank bigint, id uuid, name text, score int, rating int, tier text, streak int, xp int, level int)
language sql stable security definer set search_path = public as $$
  -- Players at 0 (named, but no level cleared yet) aren't listed until they score (added 2026-10-13).
  select rank() over (order by p.score desc), p.id, shown_name(p), p.score, p.rating, p.tier, p.streak, p.xp, p.level
  from public.players p where p.score > 0 order by p.score desc, p.updated_at limit least(greatest(p_limit, 1), 200)
$$;

-- One player's row and rank (for the pinned "you" row).
create or replace function public.player_rank(p_id uuid)
returns table (rank bigint, id uuid, name text, score int, rating int, tier text, streak int, xp int, level int)
language sql stable security definer set search_path = public as $$
  select (select count(*) + 1 from public.players o where o.score > p.score), p.id, shown_name(p), p.score, p.rating, p.tier, p.streak, p.xp, p.level
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
returns table (rank bigint, id uuid, name text, score int, rating int, tier text, streak int, xp int, level int, passed bigint)
language sql stable security definer set search_path = public as $$
  with me as (select p.score, p.prev_score from public.players p where p.id = p_id and p.prev_score is not null),
  passed as (select p.* from public.players p, me where p.id <> p_id and p.score > me.prev_score and p.score < me.score)
  select (select count(*) + 1 from public.players o where o.score > q.score), q.id, shown_name(q), q.score, q.rating, q.tier, q.streak, q.xp, q.level,
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
