-- 2026-11-26: shared puzzle finish race. Run once in the Supabase SQL editor.
-- Production-safe: same function name, arguments and return shape as before, so every app version (1.1 / 1.1.1 / 1.1.2 and
-- the next build) keeps calling it unchanged; CREATE OR REPLACE keeps the existing grants. Only adds a row lock.

create or replace function public.duo_place(p_id uuid, p_secret text, p_duo bigint, p_piece int) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  me public.players := player_auth(p_id, p_secret);
  d public.duo_puzzles;
begin
  -- FOR UPDATE: both partners placing the last two pieces at once each counted 11 and the puzzle stayed active for good.
  -- The row lock makes the second placing wait, so it sees the first one's piece.
  select * into d from public.duo_puzzles where id = p_duo and (a = p_id or b = p_id) and status = 'active' for update;
  if d.id is null then return json_build_object('placed', false, 'done', false); end if;
  update public.duo_pieces set placed_by = p_id, placed_at = now() where duo = d.id and piece = p_piece and placed_by is null;
  if (select count(*) from public.duo_pieces where duo = d.id and placed_by is not null) >= 12 then
    update public.duo_puzzles set status = 'done', done_at = now() where id = d.id;
    return json_build_object('placed', true, 'done', true);
  end if;
  return json_build_object('placed', true, 'done', false);
end $$;

-- One-off repair: any puzzle the race already left 'active' with all 12 pieces placed becomes 'done' (both partners can then claim).
-- Run the SELECT first to see how many; the UPDATE is safe to run more than once.
select d.id, d.a, d.b from public.duo_puzzles d
 where d.status = 'active' and (select count(*) from public.duo_pieces x where x.duo = d.id and x.placed_by is not null) >= 12;

update public.duo_puzzles d set status = 'done', done_at = now()
 where d.status = 'active' and (select count(*) from public.duo_pieces x where x.duo = d.id and x.placed_by is not null) >= 12;
