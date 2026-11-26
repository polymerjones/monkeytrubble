# Monkey Trubble development backlog

The persistent backlog, kept by Claude (Master Development Directive, 2026-11-26). Newest first within each section.

**Labels:**
- `[sim]`: verified in headless Chrome, the Social Lab mock, or PGlite.
- `[device]`: verified on Paul's iPhone.
- `[code]`: implemented, not yet verified.

## Release target: 1.1.3 (iOS build 21 / Android vc 30)
**Status:** release candidate, on PolyiPhonePro (Debug build). Not pushed, not submitted.

### What's in it
| Item | Status |
|---|---|
| Chapter puzzles stay open on later laps; started puzzles never relock; badge counts only placeable pieces | `[device]` + `[sim]` |
| Ice Age Battle Apes II puzzle + 6 more regular puzzles + 2 Christmas-season scenes | `[device]` (first batch), rest `[sim]` |
| Shared puzzle lifecycle: no relaunch needed, invite count syncs, late finds light the badge, chance 60% | `[sim]` (old code reproduced the bug) |
| Booster badge = free + bank | `[sim]` |
| Drag ghost (stuck big card) fix | `[sim]`: second finger, hide, blur, pagehide, rotate, puzzles open, rapid repeats |
| Streak milestone chests 14/30/60/100 (retroactive, once, union-merged) | `[sim]` |
| FRIEND NEWS setting, news straight into today's reminder, taps open the right screen, invite links, one-time "hear when they answer?" ask, DIAGNOSTICS | `[sim]` page + both apps compile; **device test owed** |
| SEND AN INVITE IN A MESSAGE (share sheet), `/f/CODE?duo=1` | `[code]`, **device test owed** |
| RATE MONKEY TRUBBLE button (voluntary only) | `[code]`, **device test owed** |
| What's New shows the installed version; check-release | `[sim]` |
| Release builds strip dev/lab, tools, SQL and concept art | `[sim]`: iOS Release bundle and Android release assets inspected |
| Public website can't enter dev mode | `[sim]` |

## Needs Paul
1. **Run SQL (before 1.1.3 ships):** `web/supabase/migrations/2026-11-26-duo-place-lock.sql`. It's tested on PGlite against the production schema and old clients are unaffected. Run the SELECT, then the whole file.
2. **Cleanup SQL (my test mistake, 2026-11-26):** one test profile named "LabPaul" (score 0, not on the board) was posted to production before the test harness blocked Supabase.
   `delete from public.players where name = 'LabPaul' and score = 0;`
3. **Ice Age crops:** pick from `~/Downloads/MonkeyTrubble-IceAge-Review/` (look at `actual-size-current-vs-new.jpg` first). Thumbs are regenerated only after your OK.
4. **Tournaments go live:** after you've played them in the lab, run `web/supabase/migrations/2026-11-26-tournaments.sql`, then I flip `TOURNEYS_LIVE`.
5. **Device tests:** see "Testing owed".
6. **Christmas Joker:** Christmas boards show the regular/chapter Joker (no Christmas Joker art). Paint one, or reuse Santa POLY?
7. **Push notifications:** create the Apple APNs key and the Firebase project (docs/proposals/push-notifications.md).

## Testing owed (Paul's iPhone)
- Dev Tools › REMINDERS › DIAGNOSTICS, OPEN: DUO / OPEN: FRIEND, and TEST NEWS IN 10S, then tap the notification: does the right screen open (app closed, and app open)?
- Settings › FRIEND NEWS on with REMINDERS off: the hint text, and DIAGNOSTICS shows the "news-only" slots.
- Shared puzzles → INVITE A FRIEND → SEND AN INVITE IN A MESSAGE; open the link on another device.
- Settings › RATE MONKEY TRUBBLE opens the App Store review page.
- Social Lab: ENTER LAB, then play a whole tournament with TIME › "To tournament end" (exit with EXIT LAB; your real save is untouched).
- Drag ghost on a real device: second finger mid-drag, Notification Center pull-down mid-drag.

## Bugs and root causes
| Bug (reported) | Root cause | Status |
|---|---|---|
| Chapter puzzles / Ice Age Battle missing, badge stuck at 2 (11-25) | `chapterFor().number` restarts each 55-level lap | Fixed `[device]` |
| Can't start a new shared puzzle after finishing (11-25) | stale `duo.state` and `pz.duo` | Fixed `[sim]` |
| Few shared pieces (11-25) | stale skip, and dropped popups | Fixed `[sim]`, chance 60% |
| Power-ups show 1 not 40s (11-25) | display only | Fixed `[sim]` |
| Card stuck big over board (L135) | orphaned drag ghost (second finger) | Fixed `[sim]` |
| Shared puzzle may never finish | `duo_place` race | SQL ready (Needs Paul #1) |
| Christmas Joker isn't Christmas art | no art | Needs Paul #6 |

## Proposals and next projects (outside 1.1.3)
1. **Real push notifications:** docs/proposals/push-notifications.md. Next up; needs Paul's Apple and Firebase keys.
2. **Troop Tournaments go live:** built. Needs SQL + a flag, ideally after push.
3. **Staging Supabase project:** real two-client concurrency tests (duo_place race, tournament syncs).
4. **Long-term puzzle progression:** a new painting per lap, seasonal sets, "golden" re-builds of finished puzzles for small XP. More puzzle paintings wanted.
5. **Streak badge on the friend card** (highest milestone): needs a server field; deferred from 1.1.3.

## Tech debt
- **iCloud booster merge** takes `Math.max` per bank key, so spent boosters can come back. Deferred: it needs a design that never loses earned boosters (memory: no-inventory-loss).
- **perf-baseline.json is stale** for this machine and Chrome: 1.1.2 and 1.1.3 both read about 25–35% over it on startLevel. Re-baseline with `--update` on a quiet machine.
- **iOS 1.1 build 17 clients** ignore shared puzzles, but `duo_invite` can target them. Optional: a version guard (needs SQL).
- **Tests** extract functions from index.html by text, so renames break them.
- **The Android build** needs `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`.
- **iPhone friend news with the daily reminder off** depends on iOS background refresh (best-effort). Push fixes it.

## Pending art
- Ice Age crop approval (above).
- Christmas Joker.
- More puzzle paintings.
- Madagascar, Savannah and Frozen rosters; seasonal POLY; Spanish lines (memory: pending-content).

## Release checklist (each store build)
- [ ] From `web/`, run `node tools/` + each of: check-deals (24-problem baseline), check-tutorial, check-scoring, check-release, check-puzzles, check-social, check-drag, check-streak, check-tourney
- [ ] `node tests/sql/check-migrations.mjs` when SQL changed
- [ ] `node tools/perf-check.mjs` (compare with the old build on the same machine if the baseline is stale)
- [ ] Display Zoom 320×693 and 614×320, iPad landscape
- [ ] RELEASE_NOTES version = MARKETING_VERSION = versionName (check-release)
- [ ] `sw.js` CACHE bumped
- [ ] Release bundle has no web/dev (iOS script phase; Android per-variant bundle)
- [ ] Pending SQL run by Paul, and older clients still work
- [ ] PolyiPhonePro device test and Android emulator smoke test
- [ ] Paul authorizes push and store submission
