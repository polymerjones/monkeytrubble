# Friend Tournaments: proposal (not built)

*Monkey Trubble, 2026-11-26. Scope: a simple first version. Balancing and other formats come later.*

## The idea
A friend starts a **5-day tournament** and invites friends. Everyone just plays the game normally. Levels cleared, puzzle pieces placed and puzzles finished during those 5 days earn points. A standings board with a countdown shows who's ahead. When time runs out, the winner gets a celebration and everyone who took part gets a reward.

No special mode and no seeded boards: it rewards playing on your normal path.

## How it works for the player
1. **Start:** Leaderboard › FRIENDS › **START A TOURNAMENT**. Pick friends (up to 7, so 8 players). It starts now and runs for 5 days.
2. **Invite:** each friend gets a news item (home name pill, 🏆 badge, and the daily reminder line *"Kaulin challenged you to a 5-day tournament!"*). They tap **JOIN** or **NO THANKS**. Nobody is ever added without accepting.
3. **Play:** a slim strip on the home screen: *🏆 Tournament · 2nd of 5 · 3d 4h left*. Tap it for the standings.
4. **Standings:** players ranked by points, with a per-category breakdown (levels / pieces / puzzles), your row highlighted, and a countdown.
5. **End:** the next time each player opens the app after the deadline, they see the result screen. The winner gets confetti and the praiseSting brand sound (saved for big moments), with a podium of the top 3. Rewards are claimed once.

## Scoring (simple, hard to game)
| Action during the 5 days | Points |
|---|---|
| A **new** level cleared (your level number goes up) | 10 |
| A puzzle piece placed (your own puzzles or shared ones) | 3 |
| A puzzle completed | 25 |

**Duplicate-score prevention: points come from server totals that only go up, measured from a snapshot taken when you join.**
- **Levels:** `players.level` already only increases (`greatest(...)` in `submit_score`). Points are `(level now − level at join) × 10`, so replays, retries and Easy re-clears can't add anything.
- **Own pieces and puzzles:** two new running totals on `players` (`pz_placed`, `pz_done`) are sent with the existing profile sync, and the server keeps `greatest(old, new)`. Points are measured from the join snapshot. Counts can't go down, and re-sending the same count adds nothing.
- **Shared pieces:** these are counted straight from `duo_pieces.placed_at` inside the window. Each piece row is placed once, ever.
- **Sanity caps** (server side, per player per tournament, like the existing anti-cheat cap):
  - at most 60 levels a day;
  - piece totals can't exceed what the levels could have produced;
  - impossible jumps are clamped, not rejected, so an honest offline catch-up still counts.

**Fairness across player levels (v1):** everyone starts at 0 from their own snapshot, so a level-300 veteran and a level-20 newcomer race on *activity*, not progress. Puzzle points help newer players, who still have many puzzles open. Handicaps or brackets can come later.

## Rewards
- **Everyone who joined and scored more than 0:** 1 undo + 1 shuffle (into `progress.bank`, through the existing claim pattern).
- **Winner:** 3 undo, 2 shuffle, 2 hint, plus 250 XP and a 🏆 trophy on their friend card ("Tournament winner ×N").
- **Ties:** shared first place; both get the winner reward.
- **Claim once:** `tourney_claim` sets a per-member `claimed` flag, the same as `duo_claim`. A second claim returns false.

## Backend (Supabase, same patterns as friends and shared puzzles)
**Tables**
- **`tournaments`**: `id`, `created_by`, `starts_at`, `ends_at` (= starts_at + 5 days), `created_at`.
- **`tournament_members`**: `tournament`, `player`, `status` (invited / joined / declined / left), `base_level`, `base_pz_placed`, `base_pz_done`, `joined_at`, `claimed`, `seen_at`.
- **New columns:** `players.pz_placed` and `players.pz_done`, default 0.

**RPCs** (security definer, `player_auth`, RLS on, everything revoked from anon; the same as `duo_*`)
- `tourney_create(p_friends uuid[])`: friends only (`friend_links` status 'friends'). One open tournament per creator, at most 3 joined at once per player.
- `tourney_answer(p_id, p_join bool)`: takes the base snapshot on join.
- `tourney_state()`: my current or most recent tournament, standings with points computed on read, time left, and whether I can claim.
- `tourney_claim(p_id)`.
- `my_news` gains a `tourney` key (invites, a lead change, finished and unclaimed). This feeds the home pill, the badges and the native background reminder with **no new native code**.

**No scheduler needed:** status is worked out on read (`now() > ends_at` means finished). That fits the current setup, which has no pg_cron.

**Production compatibility:** every change is additive (new tables, new functions, new nullable or defaulted columns). Existing app versions don't call the new functions and ignore the new `my_news` key. The profile sync sends the new totals through a **new** function (`submit_puzzle_stats`), so `submit_score`'s signature is unchanged.

**Offline:** the totals ride on the existing `pendingSync` retry. A late sync after the deadline only counts toward points if its level/puzzle timestamps are inside the window, so catch-up uploads count but post-deadline play doesn't.

## Client work (web/index.html)
- A FRIENDS-tab button plus a friend picker (reuse the shared-puzzle invite list rows).
- The home tournament strip and the standings sheet (reuse leaderboard row styling and the countdown format).
- A result screen with a winner celebration (reuse the chapter-complete and puzzle-finish effects).
- News and badge wiring through `refreshNews`.
- Spanish strings and a What's New line.

## Risks and open questions
- **Bad timing:** a 5-day tournament started right before a player's vacation. Leaving is allowed (keeping points earned so far) but there's no pause.
- **Notification fatigue:** at most one tournament line a day in reminders, the same as nudges.
- **For Paul to decide:** should Easy-mode clears count? Proposed: yes, since level numbers count either way.
- **For Paul to decide:** 8-player cap and 3 concurrent tournaments; does that feel right?

## Effort estimate
Server about 1 session; client about 2 sessions; testing with two devices (LAN A/B plus a real friend) about 1 session.
