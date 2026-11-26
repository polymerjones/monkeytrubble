-- Real push notifications (1.1.4). DO NOT RUN until Paul approves (it also needs the Edge Function deployed and its secrets set;
-- see docs/proposals/push-notifications.md "Go-live steps").
--
-- Production compatibility: additive only. New tables and functions, and AFTER triggers that only add rows to push_outbox (they
-- can't fail the original insert/update: errors are caught). Older apps never register a device, so nothing is ever sent to them,
-- and every existing function keeps its signature and output.
--
-- Design:
--   device_tokens   one row per device (many per player); a token moving to another player moves its row
--   push_outbox     one row per event per recipient, unique by dedupe key, so an event can't be queued twice
--   push_sent       one row per (event, token) once delivered, so a retry never re-sends to a device that already got it
--   push_log        what happened, kept 7 days (dev diagnostics: delivery failure vs. no device vs. rate limited)
-- The Edge Function (supabase/functions/push) calls push_claim(), sends, then push_report(). Claiming leases rows for 2 minutes
-- with FOR UPDATE SKIP LOCKED, so two runs at once never take the same rows.
-- Preferences: a device is registered only while FRIEND NEWS is on (the app unregisters it when turned off). Quiet hours
-- 22:00-08:00 in the device's time zone and at most 8 pushes per player per day; held pushes wait, they aren't dropped.

create table if not exists public.device_tokens (
  token       text primary key check (char_length(token) between 20 and 4096),
  player      uuid not null references public.players(id) on delete cascade,
  platform    text not null check (platform in ('ios', 'android')),
  env         text not null default 'prod' check (env in ('prod', 'sandbox')),
  lang        text not null default 'en' check (lang in ('en', 'es')),
  tz_min      int not null default 0 check (tz_min between -840 and 840),
  app_version text,
  updated_at  timestamptz not null default now()
);
create index if not exists device_tokens_player_idx on public.device_tokens (player);
create table if not exists public.push_outbox (
  id          bigserial primary key,
  player      uuid not null references public.players(id) on delete cascade,
  kind        text not null check (kind in ('duo', 'friend', 'tourney')),
  msg         text not null,
  args        jsonb not null default '[]',
  dedupe      text not null unique,
  created_at  timestamptz not null default now(),
  due_at      timestamptz not null default now(),
  attempts    int not null default 0,
  lease_until timestamptz,
  done_at     timestamptz,
  last_error  text
);
create index if not exists push_outbox_due_idx on public.push_outbox (due_at) where done_at is null;
create table if not exists public.push_sent (
  outbox  bigint not null references public.push_outbox(id) on delete cascade,
  token   text not null,
  sent_at timestamptz not null default now(),
  primary key (outbox, token)
);
create table if not exists public.push_log (
  id      bigserial primary key,
  at      timestamptz not null default now(),
  player  uuid,
  outbox  bigint,
  token   text,
  result  text not null,
  detail  text
);
create index if not exists push_log_player_idx on public.push_log (player, at desc);
alter table public.device_tokens enable row level security;
alter table public.push_outbox enable row level security;
alter table public.push_sent enable row level security;
alter table public.push_log enable row level security;
revoke all on public.device_tokens, public.push_outbox, public.push_sent, public.push_log from anon, authenticated;

-- The app: this device's token (FRIEND NEWS on and notifications allowed). Up to 10 devices per player (the oldest go).
create or replace function public.register_device(p_id uuid, p_secret text, p_platform text, p_token text, p_env text default 'prod',
  p_lang text default 'en', p_tz_min int default 0, p_app_version text default null) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  insert into public.device_tokens (token, player, platform, env, lang, tz_min, app_version, updated_at)
    values (p_token, p_id, p_platform, coalesce(nullif(p_env, ''), 'prod'), case when p_lang = 'es' then 'es' else 'en' end,
            greatest(-840, least(840, coalesce(p_tz_min, 0))), left(p_app_version, 16), now())
    on conflict (token) do update set player = excluded.player, platform = excluded.platform, env = excluded.env, lang = excluded.lang,
      tz_min = excluded.tz_min, app_version = excluded.app_version, updated_at = now();
  delete from public.device_tokens where player = p_id and token in
    (select token from public.device_tokens where player = p_id order by updated_at desc offset 10);
  return true;
end $$;

-- The app: FRIEND NEWS turned off, notifications denied, or the player changed: this device stops getting pushes.
create or replace function public.unregister_device(p_id uuid, p_secret text, p_token text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  delete from public.device_tokens where token = p_token and player = p_id;
  return found;
end $$;

-- Queue one push (internal). Never raises: a push problem must never break the game action that caused it.
create or replace function public.push_enqueue(p_player uuid, p_kind text, p_msg text, p_args jsonb, p_dedupe text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_player is null or not exists (select 1 from public.device_tokens where player = p_player) then return; end if;
  insert into public.push_outbox (player, kind, msg, args, dedupe) values (p_player, p_kind, p_msg, coalesce(p_args, '[]'), p_dedupe)
    on conflict (dedupe) do nothing;
exception when others then
  raise warning 'push_enqueue: %', sqlerrm;
end $$;

-- Events -> pushes.
create or replace function public.push_on_duo() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    perform push_enqueue(new.b, 'duo', 'duoInvite', jsonb_build_array((select shown_name(p) from players p where p.id = new.a)), 'duo-invite:' || new.id);
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status = 'active' then
    perform push_enqueue(new.a, 'duo', 'duoAccepted', jsonb_build_array((select shown_name(p) from players p where p.id = new.b)), 'duo-accepted:' || new.id);
  elsif tg_op = 'UPDATE' and old.status = 'active' and new.status = 'done' then
    perform push_enqueue(new.a, 'duo', 'duoDone', jsonb_build_array((select shown_name(p) from players p where p.id = new.b)), 'duo-done:' || new.id || ':' || new.a);
    perform push_enqueue(new.b, 'duo', 'duoDone', jsonb_build_array((select shown_name(p) from players p where p.id = new.a)), 'duo-done:' || new.id || ':' || new.b);
  end if;
  return null;
exception when others then raise warning 'push_on_duo: %', sqlerrm; return null;
end $$;
drop trigger if exists push_duo on public.duo_puzzles;
create trigger push_duo after insert or update of status on public.duo_puzzles for each row execute function public.push_on_duo();

create or replace function public.push_on_friend() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    perform push_enqueue(new.other, 'friend', 'request', jsonb_build_array((select shown_name(p) from players p where p.id = new.player)), 'friend-req:' || new.player || ':' || new.other || ':' || to_char(now(), 'YYYYMMDD'));
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status = 'friends' and new.accepted_at is not null then
    perform push_enqueue(new.player, 'friend', 'accepted', jsonb_build_array((select shown_name(p) from players p where p.id = new.other)), 'friend-ok:' || new.player || ':' || new.other);
  end if;
  return null;
exception when others then raise warning 'push_on_friend: %', sqlerrm; return null;
end $$;
drop trigger if exists push_friend on public.friend_links;
create trigger push_friend after insert or update of status on public.friend_links for each row execute function public.push_on_friend();

create or replace function public.push_on_nudge() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform push_enqueue(new.receiver, 'friend', 'nudge', jsonb_build_array((select shown_name(p) from players p where p.id = new.sender), new.line), 'nudge:' || new.id);
  return null;
exception when others then raise warning 'push_on_nudge: %', sqlerrm; return null;
end $$;
drop trigger if exists push_nudge on public.nudges;
create trigger push_nudge after insert on public.nudges for each row execute function public.push_on_nudge();

-- Tournaments (only once 2026-11-26-tournaments.sql has run): an invite now; the result when the tournament ends (due_at).
do $tourney$ begin
  if to_regclass('public.tournament_members') is not null then
    create or replace function public.push_on_tourney_member() returns trigger language plpgsql security definer set search_path = public as $f$
    declare t public.tournaments;
    begin
      select * into t from tournaments where id = new.tourney;
      if tg_op = 'INSERT' and new.status = 'invited' then
        perform push_enqueue(new.player, 'tourney', 'tourneyInvite', jsonb_build_array((select shown_name(p) from players p where p.id = t.host)), 'tourney-inv:' || new.tourney || ':' || new.player);
      end if;
      if new.status = 'joined' and (tg_op = 'INSERT' or old.status is distinct from 'joined') then
        perform push_enqueue(new.player, 'tourney', 'tourneyDone', '[]', 'tourney-done:' || new.tourney || ':' || new.player);
        update push_outbox set due_at = t.ends_at + interval '1 minute' where dedupe = 'tourney-done:' || new.tourney || ':' || new.player and done_at is null;
      end if;
      return null;
    exception when others then raise warning 'push_on_tourney_member: %', sqlerrm; return null;
    end $f$;
    drop trigger if exists push_tourney_member on public.tournament_members;
    create trigger push_tourney_member after insert or update of status on public.tournament_members for each row execute function public.push_on_tourney_member();
  end if;
end $tourney$;

-- The sender's side (service role only). Claim up to p_limit due pushes with their devices, honoring quiet hours (per device time
-- zone) and the daily cap; held rows get a later due_at instead of being dropped.
create or replace function public.push_claim(p_limit int default 50) returns json
language plpgsql security definer set search_path = public as $$
declare out json;
begin
  -- Daily cap: a player who already got 8 today waits until tomorrow.
  update push_outbox o set due_at = date_trunc('day', now()) + interval '1 day 8 hours'
    where o.done_at is null and o.due_at <= now()
      and (select count(distinct l.outbox) from push_log l where l.player = o.player and l.result = 'sent' and l.at > now() - interval '1 day') >= 8;
  with due as (
    select o.id from push_outbox o
    where o.done_at is null and o.due_at <= now() and (o.lease_until is null or o.lease_until < now())
    order by o.due_at limit greatest(1, least(p_limit, 200)) for update skip locked
  ), leased as (
    update push_outbox o set lease_until = now() + interval '2 minutes', attempts = o.attempts + 1 from due where o.id = due.id returning o.*
  )
  select coalesce(json_agg(json_build_object('id', l.id, 'player', l.player, 'kind', l.kind, 'msg', l.msg, 'args', l.args, 'attempts', l.attempts,
    'devices', coalesce((select json_agg(json_build_object('token', d.token, 'platform', d.platform, 'env', d.env, 'lang', d.lang, 'tz_min', d.tz_min))
      from device_tokens d where d.player = l.player and not exists (select 1 from push_sent s where s.outbox = l.id and s.token = d.token)), '[]'))), '[]')
    into out from leased l;
  return out;
end $$;

-- The sender always calls this after push_claim (an empty list is fine: it finishes pushes whose player has no devices left).
-- It reports each attempt: [{id, token, result: sent|dead|retry|quiet, detail, retry_in_s}]. sent marks the device done
-- for that push; dead deletes the token; retry tries again later (backoff from the sender, up to 6 attempts); quiet waits for morning.
create or replace function public.push_report(p_results json) returns int
language plpgsql security definer set search_path = public as $$
declare r json; ob push_outbox; n int := 0; again timestamptz;
begin
  for r in select * from json_array_elements(coalesce(p_results, '[]')) loop
    select * into ob from push_outbox where id = (r->>'id')::bigint;
    if ob.id is null then continue; end if;
    insert into push_log (player, outbox, token, result, detail) values (ob.player, ob.id, r->>'token', r->>'result', left(r->>'detail', 300));
    if r->>'result' = 'sent' then insert into push_sent (outbox, token) values (ob.id, r->>'token') on conflict do nothing;
    elsif r->>'result' = 'dead' then delete from device_tokens where token = r->>'token';
    elsif r->>'result' = 'retry' and ob.attempts >= 6 then
      update push_outbox set done_at = now(), lease_until = null, last_error = left('gave up after 6 attempts: ' || coalesce(r->>'detail', ''), 300) where id = ob.id;
    elsif r->>'result' in ('retry', 'quiet') then
      again := now() + make_interval(secs => greatest(30, least(coalesce((r->>'retry_in_s')::int, 300), 86400)));
      update push_outbox set due_at = again, lease_until = null where id = ob.id;
    end if;
    n := n + 1;
  end loop;
  -- A claimed push is finished when every device of the player has it (or none are left). A device that keeps failing
  -- transiently ends it after 6 attempts (above), with the reason in last_error.
  update push_outbox o set done_at = now(), lease_until = null
    where o.done_at is null and o.lease_until is not null and not exists (select 1 from device_tokens d where d.player = o.player
      and not exists (select 1 from push_sent s where s.outbox = o.id and s.token = d.token));
  if random() < 0.05 then
    delete from push_log where at < now() - interval '7 days';
    delete from push_outbox where done_at < now() - interval '7 days';
  end if;
  return n;
end $$;

-- Dev diagnostics for a player (the app's Dev Tools): their devices and the last pushes and results. Only their own.
create or replace function public.push_status(p_id uuid, p_secret text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare me public.players := player_auth(p_id, p_secret);
begin
  return json_build_object(
    'devices', coalesce((select json_agg(json_build_object('platform', platform, 'env', env, 'app_version', app_version, 'updated_at', updated_at, 'tail', right(token, 6)))
      from device_tokens where player = p_id), '[]'),
    'recent', coalesce((select json_agg(x) from (select l.at, l.result, l.detail, o.kind, o.msg from push_log l left join push_outbox o on o.id = l.outbox
      where l.player = p_id order by l.at desc limit 10) x), '[]'),
    'queued', (select count(*) from push_outbox where player = p_id and done_at is null));
end $$;

revoke all on function public.register_device(uuid, text, text, text, text, text, int, text) from public;
revoke all on function public.unregister_device(uuid, text, text) from public;
revoke all on function public.push_status(uuid, text) from public;
revoke all on function public.push_enqueue(uuid, text, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.push_claim(int) from public, anon, authenticated;
revoke all on function public.push_report(json) from public, anon, authenticated;
grant execute on function public.register_device(uuid, text, text, text, text, text, int, text) to anon, authenticated;
grant execute on function public.unregister_device(uuid, text, text) to anon, authenticated;
grant execute on function public.push_status(uuid, text) to anon, authenticated;
do $g$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.push_claim(int) to service_role;
    grant execute on function public.push_report(json) to service_role;
  end if;
end $g$;
