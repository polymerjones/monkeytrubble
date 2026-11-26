# Monkey Trubble development backlog

The persistent backlog, kept by Claude (Master Development Directive, 2026-11-26). Newest first within each section.

**Labels:**
- `[sim]`: verified in headless Chrome, the Social Lab mock, or PGlite.
- `[device]`: verified on Paul's iPhone.
- `[code]`: implemented, not yet verified.

## Release target: 1.1.3 (iOS build 21 / Android vc 30)
**Status:** release candidate, tagged `v1.1.3-rc` on main. Debug build on PolyiPhonePro.
- **Prepared / uploaded / submitted / approved / live:** none of these yet. The archive and AAB are made after Paul's device checks.
- **Store text:** docs/release/1.1.3-store-text.md (EN/ES; Play notes under 500 characters; no emoji for the App Store).
- **Server:** the duo_place lock was run in production by Paul on 2026-11-26.

## In progress: 1.1.4 real push (branch `push-1.1.4`)
- **Built:**
  - server SQL + Edge Function (on main, not deployed);
  - iOS APNs registration (Push enabled on the App ID through automatic signing);
  - Android FCM (off until google-services.json);
  - page registration with no local/remote doubles;
  - diagnostics.
- **Tests:** tests/sql/check-push.mjs (32), tests/push/check-sender.mjs (23), web/tools/check-push-client.mjs (13). All pass.
- **Waiting on Paul:** APNs key, Firebase project + google-services.json + service account, Supabase secrets, pg_cron/pg_net, approval to run the SQL and deploy. Steps: docs/proposals/push-notifications.md, "Go-live steps".
- **Tournaments go live with 1.1.4**, once push is working and 1.1.4 builds are in the stores.

### What's in it
| Item | Status |
|---|---|
| Chapter puzzles stay open on later laps; started puzzles never relock; badge counts only placeable pieces | `[device]` + `[sim]` |
| Ice Age Battle Apes II puzzle + 6 more regular puzzles + 2 Christmas-season scenes | `[device]` (first batch), rest `[sim]` |
| Shared puzzle lifecycle: no relaunch needed, invite count syncs, late finds light the badge, chance 60% | `[sim]` (old code reproduced the bug) |
| Booster badge = free + bank | `[sim]` |
| Drag ghost (stuck big card) fix | `[sim]`: second finger, hide, blur, pagehide, rotate, puzzles open, rapid repeats |
| Streak milestone chests 14/30/60/100 (retroactive, once, union-merged) | `[sim]` |
| FRIEND NEWS setting, news straight into today's reminder, taps open the right screen, invite links, one-time "hear when they answer?" ask, DIAGNOSTICS | `[sim]`; Android tap routing verified on emulator (cold intent → waits for welcome → FRIENDS); **iPhone test owed** |
| SEND AN INVITE IN A MESSAGE (share sheet), `/f/CODE?duo=1` | `[code]`, **device test owed** |
| RATE MONKEY TRUBBLE button (voluntary only) | `[code]`, **device test owed** |
| What's New shows the installed version; check-release | `[sim]` |
| Ice Age thumbs re-framed on each face (Paul approved 11-26; sources and heroes untouched) | `[sim]`, on iPhone |
| Tournament polish: compact layout for short and sideways screens, side-by-side celebration, "waiting for friends", plurals | `[sim]` at 932×430, 614×320, 320×693, 375×667, 430×932, iPad |
| Release builds strip dev/lab, tools, SQL and concept art | `[sim]`: iOS Release bundle and Android release assets inspected |
| Public website can't enter dev mode | `[sim]` |

## Needs Paul
1. ~~Run duo_place lock SQL~~: run by Paul 2026-11-26.
2. ~~LabPaul cleanup~~: run by Paul 2026-11-26.
3. ~~Ice Age crops~~: approved and applied 11-26.
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
| Shared puzzle may never finish | `duo_place` race | Fixed: SQL run by Paul 2026-11-26 |
| Christmas Joker isn't Christmas art | no art | Needs Paul #6 |

## Proposals and next projects (outside 1.1.3)
1. **Real push notifications:** built on branch push-1.1.4 (see In progress); needs Paul's keys and the go-live steps.
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
- [x] Pending SQL run by Paul (duo_place lock, 2026-11-26); tournaments SQL waits for go-live
- [ ] PolyiPhonePro device test and Android emulator smoke test
- [ ] Paul authorizes push and store submission
